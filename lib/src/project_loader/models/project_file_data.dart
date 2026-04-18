import 'package_reference_spec.dart';

/// Intermediate data extracted from a `.csproj` file by [IInputParser].
///
/// This is the raw parsed form before SDK/NuGet resolution and Compilation
/// construction. Source file paths are stored as globs; they are expanded
/// by the [ProjectLoader] coordinator.
final class ProjectFileData {
  /// Absolute path to the `.csproj` file.
  final String absolutePath;

  /// The assembly name from `<AssemblyName>`, or null to derive from file name.
  final String? assemblyName;

  /// The target framework moniker from `<TargetFramework>`, e.g. "net8.0".
  final String? targetFramework;

  /// The output type string from `<OutputType>`, e.g. "Exe" or "Library".
  final String? outputType;

  /// The C# language version from `<LangVersion>`, e.g. "12.0" or "Latest".
  final String? langVersion;

  /// True when `<Nullable>enable</Nullable>` is present in the project file.
  final bool nullableEnabled;

  /// Source file glob patterns relative to the project directory.
  final List<String> sourceGlobs;

  /// Absolute paths of `<ProjectReference>` entries.
  final List<String> projectReferencePaths;

  /// Raw `<PackageReference>` entries before NuGet resolution.
  final List<PackageReferenceSpec> packageReferences;

  const ProjectFileData({
    required this.absolutePath,
    this.assemblyName,
    this.targetFramework,
    this.outputType,
    this.langVersion,
    this.nullableEnabled = false,
    this.sourceGlobs = const [],
    this.projectReferencePaths = const [],
    this.packageReferences = const [],
  });
}
