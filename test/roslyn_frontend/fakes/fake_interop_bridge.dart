import 'package:cs2dart/src/roslyn_frontend/interfaces/i_interop_bridge.dart';
import 'package:cs2dart/src/roslyn_frontend/models/interop_exception.dart';

/// A test double for [IInteropBridge] that records calls and returns
/// pre-configured results.
///
/// By default returns a successful [FrontendResult] with no units and no
/// diagnostics, so that tests can focus on the behaviour under test.
///
/// Set [throwOnInvoke] to make [invoke] throw an [InteropException] instead
/// of returning a result, which exercises error-path logic in [RoslynFrontend].
///
/// Set [invokeCallback] to compute the result dynamically based on the
/// [InteropRequest] that was passed in.
final class FakeInteropBridge implements IInteropBridge {
  final FrontendResult? _fixedResult;
  final Future<FrontendResult> Function(InteropRequest)? _invokeCallback;
  final InteropException? _throwOnInvoke;

  /// How many times [invoke] has been called.
  int invokeCallCount = 0;

  /// All [InteropRequest] arguments passed to [invoke], in call order.
  final List<InteropRequest> invokeRequests = [];

  /// How many times [dispose] has been called.
  int disposeCallCount = 0;

  /// True if [dispose] has been called at least once.
  bool get wasDisposed => disposeCallCount > 0;

  /// The most recent [InteropRequest] passed to [invoke], or null if [invoke]
  /// has not been called yet.
  InteropRequest? get lastRequest =>
      invokeRequests.isEmpty ? null : invokeRequests.last;

  FakeInteropBridge({
    FrontendResult? result,
    Future<FrontendResult> Function(InteropRequest)? invokeCallback,
    InteropException? throwOnInvoke,
  })  : _fixedResult = result,
        _invokeCallback = invokeCallback,
        _throwOnInvoke = throwOnInvoke;

  @override
  Future<FrontendResult> invoke(InteropRequest request) async {
    invokeCallCount++;
    invokeRequests.add(request);
    if (_throwOnInvoke != null) throw _throwOnInvoke!;
    if (_invokeCallback != null) return _invokeCallback!(request);
    return _fixedResult ??
        const FrontendResult(units: [], diagnostics: [], success: true);
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
  }
}
