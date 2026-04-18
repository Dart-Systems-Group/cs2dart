import 'diagnostic.dart';

/// The result of resolving .NET SDK reference assemblies for a target framework.
final class SdkResolveResult {
  /// Absolute paths to the SDK reference assembly `.dll` files,
  /// sorted by file name for determinism.
  final List<String> assemblyPaths;

  /// Diagnostics emitted during SDK resolution (PL-prefixed).
  final List<Diagnostic> diagnostics;

  const SdkResolveResult({
    required this.assemblyPaths,
    required this.diagnostics,
  });
}
