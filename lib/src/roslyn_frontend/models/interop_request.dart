import '../../project_loader/models/output_kind.dart';
import '../../project_loader/models/package_reference_entry.dart';

export '../../project_loader/models/output_kind.dart';
export '../../project_loader/models/package_reference_entry.dart';

/// The plain-data payload sent to the .NET worker.
final class InteropRequest {
  /// Serialized LoadResult projects (paths, compilation options, references).
  final List<ProjectEntryRequest> projects;

  /// Active configuration values relevant to the frontend.
  final FrontendConfig config;

  const InteropRequest({required this.projects, required this.config});
}

/// Configuration values extracted from [IConfigService] for the worker.
final class FrontendConfig {
  /// LINQ strategy: "preserve_functional" | "lower_to_loops".
  final String linqStrategy;

  /// True when nullable reference type analysis is enabled.
  final bool nullabilityEnabled;

  /// Experimental feature flags keyed by feature name.
  final Map<String, bool> experimentalFeatures;

  const FrontendConfig({
    required this.linqStrategy,
    required this.nullabilityEnabled,
    required this.experimentalFeatures,
  });
}

/// A plain-data representation of a [ProjectEntry] for the interop request.
///
/// Contains only the fields needed by the .NET worker; Roslyn-typed fields
/// (e.g. [CSharpCompilation]) are excluded.
final class ProjectEntryRequest {
  /// The assembly name of the project.
  final String projectName;

  /// Absolute path to the `.csproj` file.
  final String projectFilePath;

  /// Output kind: exe, library, or winExe.
  final OutputKind outputKind;

  /// Resolved target framework moniker, e.g. "net8.0".
  final String targetFramework;

  /// Resolved C# language version string, e.g. "12.0".
  final String langVersion;

  /// True when `<Nullable>enable</Nullable>` is set in the project file.
  final bool nullableEnabled;

  /// Resolved NuGet package references.
  final List<PackageReferenceEntry> packageReferences;

  /// Absolute paths to all source files, sorted alphabetically.
  final List<String> sourceFilePaths;

  const ProjectEntryRequest({
    required this.projectName,
    required this.projectFilePath,
    required this.outputKind,
    required this.targetFramework,
    required this.langVersion,
    required this.nullableEnabled,
    required this.packageReferences,
    required this.sourceFilePaths,
  });
}
