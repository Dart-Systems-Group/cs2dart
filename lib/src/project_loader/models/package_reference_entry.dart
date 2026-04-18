import 'roslyn_interop.dart';

/// A resolved NuGet package reference with tier classification and Dart mapping.
final class PackageReferenceEntry {
  /// NuGet package ID, e.g. "Newtonsoft.Json".
  final String packageName;

  /// Resolved version string, e.g. "13.0.3".
  final String version;

  /// Tier classification:
  /// - 1: mapped — has a known Dart equivalent ([dartMapping] is non-null)
  /// - 2: transpiled — C# source is included in the Compilation
  /// - 3: stubbed — no reference added; Roslyn binding errors expected
  final int tier;

  /// Dart mapping record. Non-null for Tier 1 packages; null for Tier 2/3.
  final DartMapping? dartMapping;

  const PackageReferenceEntry({
    required this.packageName,
    required this.version,
    required this.tier,
    this.dartMapping,
  });
}
