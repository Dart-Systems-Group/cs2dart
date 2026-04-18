import 'diagnostic.dart';
import 'package_reference_entry.dart';

/// The result of resolving NuGet package references for a project.
final class NuGetResolveResult {
  /// Absolute paths to the resolved assembly `.dll` files.
  final List<String> assemblyPaths;

  /// Resolved package references with tier classification and Dart mappings.
  final List<PackageReferenceEntry> packageReferences;

  /// Diagnostics emitted during NuGet resolution (NR-prefixed).
  final List<Diagnostic> diagnostics;

  const NuGetResolveResult({
    required this.assemblyPaths,
    required this.packageReferences,
    required this.diagnostics,
  });
}
