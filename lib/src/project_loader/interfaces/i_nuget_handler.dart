import '../../config/i_config_service.dart';
import '../models/nuget_resolve_result.dart';
import '../models/package_reference_spec.dart';

/// Resolves and classifies NuGet package references for a project.
abstract interface class INuGetHandler {
  /// Resolves all [packageReferences] for [targetFramework].
  ///
  /// Queries configured NuGet feeds in order before falling back to nuget.org.
  /// Resolves transitive dependencies and classifies each package into a tier.
  ///
  /// Returns a [NuGetResolveResult] containing resolved assembly paths,
  /// tier classifications, Dart mappings, and NR-prefixed diagnostics.
  Future<NuGetResolveResult> resolve(
    List<PackageReferenceSpec> packageReferences,
    String targetFramework,
    IConfigService config,
  );
}
