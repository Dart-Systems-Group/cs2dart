import 'interfaces/i_interop_bridge.dart';

/// Placeholder production implementation of [IInteropBridge].
///
/// This stub satisfies the interface so the pipeline bootstrap compiles while
/// the real named-pipe / JSON interop bridge to the .NET worker process is
/// developed. Every method throws [UnimplementedError] with a descriptive
/// message so callers fail loudly rather than silently.
///
/// Replace this class with the real implementation once the .NET worker
/// communication layer is ready.
final class PipeInteropBridge implements IInteropBridge {
  const PipeInteropBridge();

  @override
  Future<FrontendResult> invoke(InteropRequest request) =>
      throw UnimplementedError(
        'PipeInteropBridge.invoke() is not yet implemented. '
        'The .NET worker process communication layer has not been built yet.',
      );

  @override
  Future<void> dispose() =>
      throw UnimplementedError(
        'PipeInteropBridge.dispose() is not yet implemented. '
        'The .NET worker process communication layer has not been built yet.',
      );
}
