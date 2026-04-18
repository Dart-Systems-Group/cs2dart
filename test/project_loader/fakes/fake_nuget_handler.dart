import 'package:cs2dart/src/config/i_config_service.dart';
import 'package:cs2dart/src/project_loader/interfaces/i_nuget_handler.dart';
import 'package:cs2dart/src/project_loader/models/nuget_resolve_result.dart';
import 'package:cs2dart/src/project_loader/models/package_reference_spec.dart';

/// A test double for [INuGetHandler] that returns a pre-classified
/// [NuGetResolveResult] without network access.
///
/// If [result] is null, an empty [NuGetResolveResult] is returned for every
/// call. Otherwise the provided [result] is returned regardless of the
/// [packageReferences] or [targetFramework] arguments.
final class FakeNuGetHandler implements INuGetHandler {
  final NuGetResolveResult _result;

  FakeNuGetHandler({NuGetResolveResult? result})
      : _result = result ??
            const NuGetResolveResult(
              assemblyPaths: [],
              packageReferences: [],
              diagnostics: [],
            );

  @override
  Future<NuGetResolveResult> resolve(
    List<PackageReferenceSpec> packageReferences,
    String targetFramework,
    IConfigService config,
  ) async {
    return _result;
  }
}
