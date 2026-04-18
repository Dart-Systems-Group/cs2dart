/// A raw package reference extracted from a `.csproj` file.
///
/// This is the unresolved form used as input to [INuGetHandler.resolve].
/// After resolution, it becomes a [PackageReferenceEntry].
final class PackageReferenceSpec {
  /// The NuGet package ID, e.g. "Newtonsoft.Json".
  final String packageName;

  /// The version string as written in the project file, e.g. "13.0.3".
  final String version;

  const PackageReferenceSpec({
    required this.packageName,
    required this.version,
  });
}
