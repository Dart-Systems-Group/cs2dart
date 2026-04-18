import '../models/frontend_result.dart';
import '../models/interop_request.dart';

export '../models/frontend_result.dart';
export '../models/interop_request.dart';

/// Abstracts the .NET worker process communication.
///
/// Injected into [RoslynFrontend] so tests can supply a fake without
/// spawning a real .NET process.
abstract interface class IInteropBridge {
  /// Sends [request] to the .NET worker and returns the deserialized response.
  ///
  /// Throws [InteropException] if the worker process exits unexpectedly or
  /// returns a malformed response.
  Future<FrontendResult> invoke(InteropRequest request);

  /// Terminates the worker process if it is running.
  Future<void> dispose();
}
