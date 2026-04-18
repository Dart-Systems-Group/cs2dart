import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'interfaces/i_interop_bridge.dart';
import 'models/interop_exception.dart';
import 'serialization/frontend_result_deserializer.dart';
import 'serialization/interop_request_serializer.dart';
import 'worker_binary_locator.dart';

/// Production implementation of [IInteropBridge].
///
/// Maintains a pool of `cs2dart_roslyn_worker` processes and dispatches
/// [invoke] calls to free workers over stdin/stdout using a 4-byte
/// little-endian length-prefixed JSON protocol.
///
/// The pool is created lazily on the first [invoke] call. Each worker handles
/// one request at a time; concurrent calls are queued and dispatched to the
/// next free worker. All workers are terminated on [dispose].
///
/// ## Construction
///
/// ```dart
/// // Synchronous — binary path resolved lazily on first invoke():
/// final bridge = PipeInteropBridge();
///
/// // Explicit path:
/// final bridge = PipeInteropBridge(workerBinaryPath: '/path/to/worker');
///
/// // Custom pool size:
/// final bridge = PipeInteropBridge(poolSize: 4);
/// ```
final class PipeInteropBridge implements IInteropBridge {
  /// Number of worker processes to maintain.
  ///
  /// Defaults to [Platform.numberOfProcessors], clamped to [1, 8].
  final int poolSize;

  /// Absolute path to the `cs2dart_roslyn_worker` binary, or `null` to
  /// resolve via [WorkerBinaryLocator] on the first [invoke] call.
  final String? _workerBinaryPathOverride;

  final InteropRequestSerializer _serializer;
  final FrontendResultDeserializer _deserializer;

  // Pool state — all access is single-threaded (Dart event loop).
  final List<_WorkerState> _workers = [];
  final List<_PendingRequest> _queue = [];
  bool _poolInitialized = false;
  bool _disposed = false;

  // Resolved binary path (set during _initPool).
  String? _resolvedBinaryPath;

  /// Creates a [PipeInteropBridge].
  ///
  /// [poolSize] defaults to [Platform.numberOfProcessors] clamped to [1, 8].
  /// [workerBinaryPath] is resolved via [WorkerBinaryLocator] on the first
  /// [invoke] call if not provided here.
  PipeInteropBridge({
    int? poolSize,
    String? workerBinaryPath,
    InteropRequestSerializer? serializer,
    FrontendResultDeserializer? deserializer,
  })  : poolSize = (poolSize ?? Platform.numberOfProcessors).clamp(1, 8),
        _workerBinaryPathOverride = workerBinaryPath,
        _serializer = serializer ?? const InteropRequestSerializer(),
        _deserializer = deserializer ?? const FrontendResultDeserializer();

  // ---------------------------------------------------------------------------
  // IInteropBridge
  // ---------------------------------------------------------------------------

  @override
  Future<FrontendResult> invoke(InteropRequest request) async {
    if (_disposed) {
      throw InteropException(message: 'Bridge disposed');
    }

    if (!_poolInitialized) {
      await _initPool();
    }

    // Find a free worker or queue the request.
    final freeWorker = _workers.where((w) => w.isFree).firstOrNull;
    if (freeWorker != null) {
      return _dispatch(freeWorker, request);
    }

    // All workers busy — queue the request.
    final completer = Completer<FrontendResult>();
    _queue.add(_PendingRequest(request: request, completer: completer));
    return completer.future;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // Cancel all queued requests.
    final disposedException = InteropException(message: 'Bridge disposed');
    for (final pending in _queue) {
      pending.completer.completeError(disposedException);
    }
    _queue.clear();

    // Signal EOF to all workers by closing their stdin.
    for (final worker in _workers) {
      try {
        await worker.process.stdin.close();
      } catch (_) {
        // Ignore errors during shutdown.
      }
    }

    // Wait for all worker processes to exit with a timeout.
    const timeout = Duration(seconds: 10);
    await Future.wait(
      _workers.map(
        (w) => w.process.exitCode.timeout(
          timeout,
          onTimeout: () {
            w.process.kill();
            return -1;
          },
        ),
      ),
      eagerError: false,
    );

    _workers.clear();
  }

  // ---------------------------------------------------------------------------
  // Pool initialization
  // ---------------------------------------------------------------------------

  Future<void> _initPool() async {
    _poolInitialized = true;

    // Resolve the binary path (async) before spawning any workers.
    _resolvedBinaryPath = await WorkerBinaryLocator.resolve(
      override: _workerBinaryPathOverride,
    );

    for (var i = 0; i < poolSize; i++) {
      final worker = await _spawnWorker();
      _workers.add(worker);
    }
  }

  Future<_WorkerState> _spawnWorker() async {
    final process = await Process.start(
      _resolvedBinaryPath!,
      [],
      mode: ProcessStartMode.normal,
    );

    final stderrBuffer = StringBuffer();
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) => stderrBuffer.write(chunk));

    final worker = _WorkerState(
      process: process,
      stderrBuffer: stderrBuffer,
    );

    // Monitor for unexpected process exit.
    process.exitCode.then((code) {
      if (!_disposed) {
        _onWorkerExited(worker, code);
      }
    });

    return worker;
  }

  // ---------------------------------------------------------------------------
  // Request dispatch
  // ---------------------------------------------------------------------------

  Future<FrontendResult> _dispatch(
      _WorkerState worker, InteropRequest request) async {
    worker.isFree = false;

    try {
      // Serialize request to UTF-8 JSON.
      final jsonMap = _serializer.toJson(request);
      final jsonBytes = utf8.encode(jsonEncode(jsonMap));

      // Write 4-byte LE length prefix + JSON bytes to stdin.
      final lengthPrefix = _encodeLe32(jsonBytes.length);
      worker.process.stdin.add(lengthPrefix);
      worker.process.stdin.add(jsonBytes);
      await worker.process.stdin.flush();

      // Read the response from stdout.
      final responseBytes = await _readResponse(worker);

      // Deserialize the response.
      final responseJson =
          jsonDecode(utf8.decode(responseBytes)) as Map<String, dynamic>;
      final result = _deserializer.fromJson(responseJson);

      // Mark worker free and dispatch next queued request.
      worker.isFree = true;
      _dispatchNext(worker);

      return result;
    } catch (e) {
      // If the worker is still alive, mark it free so it can be reused.
      // If it exited, _onWorkerExited will handle replacement.
      if (!worker.isFree) {
        worker.isFree = true;
        _dispatchNext(worker);
      }
      rethrow;
    }
  }

  /// Reads a length-prefixed response from the worker's stdout.
  ///
  /// Returns the raw response bytes (without the length prefix).
  /// Throws [InteropException] if the worker exits or stdout closes before
  /// the full response is received.
  Future<Uint8List> _readResponse(_WorkerState worker) async {
    // We need to read exactly 4 bytes for the length prefix, then exactly N
    // bytes for the payload. Since stdout is a Stream<List<int>>, we buffer
    // incoming chunks and satisfy reads sequentially.
    final reader = _ByteReader(worker.process.stdout);

    try {
      final Uint8List lengthBytes;
      try {
        lengthBytes = await reader.readExactly(4);
      } catch (e) {
        throw InteropException(
          message:
              'Worker stdout closed before length prefix was received. '
              'stderr: ${worker.stderrBuffer}',
          cause: e,
        );
      }

      final payloadLength = _decodeLe32(lengthBytes);

      final Uint8List payloadBytes;
      try {
        payloadBytes = await reader.readExactly(payloadLength);
      } catch (e) {
        throw InteropException(
          message:
              'Worker stdout closed before full payload was received '
              '(expected $payloadLength bytes). '
              'stderr: ${worker.stderrBuffer}',
          cause: e,
        );
      }

      return payloadBytes;
    } finally {
      reader.cancel();
    }
  }

  void _dispatchNext(_WorkerState worker) {
    if (_queue.isEmpty || _disposed) return;
    final pending = _queue.removeAt(0);
    _dispatch(worker, pending.request).then(
      pending.completer.complete,
      onError: pending.completer.completeError,
    );
  }

  // ---------------------------------------------------------------------------
  // Worker crash handling
  // ---------------------------------------------------------------------------

  void _onWorkerExited(_WorkerState worker, int exitCode) {
    // If the worker was busy, its pending request will have already thrown
    // (stdout EOF). We just need to replace the worker in the pool.
    _workers.remove(worker);

    if (!_disposed) {
      // Spawn a replacement worker asynchronously.
      _spawnWorker().then((replacement) {
        if (!_disposed) {
          _workers.add(replacement);
          // If there are queued requests, dispatch one to the new worker.
          if (_queue.isNotEmpty) {
            _dispatchNext(replacement);
          }
        } else {
          // Bridge was disposed while we were spawning; clean up.
          replacement.process.stdin.close().ignore();
          replacement.process.kill();
        }
      }).catchError((Object e) {
        // Could not spawn replacement — nothing we can do here.
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Wire-protocol helpers
  // ---------------------------------------------------------------------------

  /// Encodes [value] as a 4-byte little-endian uint32.
  static Uint8List _encodeLe32(int value) {
    final data = ByteData(4);
    data.setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  /// Decodes a 4-byte little-endian uint32 from [bytes].
  static int _decodeLe32(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    return data.getUint32(0, Endian.little);
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Tracks the state of a single worker process.
final class _WorkerState {
  final Process process;
  final StringBuffer stderrBuffer;
  bool isFree = true;

  _WorkerState({required this.process, required this.stderrBuffer});
}

/// A queued [invoke] call waiting for a free worker.
final class _PendingRequest {
  final InteropRequest request;
  final Completer<FrontendResult> completer;

  _PendingRequest({required this.request, required this.completer});
}

/// Buffers bytes from a [Stream<List<int>>] and provides exact-length reads.
final class _ByteReader {
  final Stream<List<int>> _stream;
  StreamSubscription<List<int>>? _subscription;
  final List<int> _buffer = [];
  Completer<void>? _waiter;
  bool _done = false;
  Object? _error;

  _ByteReader(this._stream) {
    _subscription = _stream.listen(
      (chunk) {
        _buffer.addAll(chunk);
        _waiter?.complete();
        _waiter = null;
      },
      onError: (Object e, StackTrace st) {
        _error = e;
        _waiter?.completeError(e, st);
        _waiter = null;
      },
      onDone: () {
        _done = true;
        _waiter?.complete();
        _waiter = null;
      },
    );
  }

  /// Reads exactly [count] bytes, waiting for more data if necessary.
  ///
  /// Throws if the stream closes before [count] bytes are available.
  Future<Uint8List> readExactly(int count) async {
    while (_buffer.length < count) {
      if (_error != null) throw _error!;
      if (_done) {
        throw StateError(
          'Stream ended with only ${_buffer.length} bytes available; '
          'expected $count.',
        );
      }
      _waiter = Completer<void>();
      await _waiter!.future;
    }

    final result = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return result;
  }

  void cancel() {
    _subscription?.cancel();
    _subscription = null;
  }
}
