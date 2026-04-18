import 'package:cs2dart/src/project_loader/interfaces/i_sdk_resolver.dart';
import 'package:cs2dart/src/project_loader/models/diagnostic.dart';
import 'package:cs2dart/src/project_loader/models/sdk_resolve_result.dart';

/// A test double for [ISdkResolver] that returns a fixed [SdkResolveResult]
/// without probing the file system.
///
/// The same result is returned regardless of [targetFramework] or [sdkPath].
final class FakeSdkResolver implements ISdkResolver {
  final List<String> _assemblyPaths;
  final List<Diagnostic> _diagnostics;

  const FakeSdkResolver({
    List<String> assemblyPaths = const [],
    List<Diagnostic> diagnostics = const [],
  })  : _assemblyPaths = assemblyPaths,
        _diagnostics = diagnostics;

  @override
  Future<SdkResolveResult> resolve(String targetFramework, {String? sdkPath}) async {
    return SdkResolveResult(
      assemblyPaths: _assemblyPaths,
      diagnostics: _diagnostics,
    );
  }
}
