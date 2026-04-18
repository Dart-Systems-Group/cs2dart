import 'diagnostic.dart';
import 'output_kind.dart';
import 'package_reference_entry.dart';
import 'roslyn_interop.dart';

/// One loaded C# project within a [LoadResult].
final class ProjectEntry {
  /// Absolute path to the `.csproj` file.
  final String projectPath;

  /// The assembly name (from `<AssemblyName>` or derived from the project file name).
  final String projectName;

  /// Resolved target framework moniker, e.g. "net8.0".
  final String targetFramework;

  /// Output kind derived from `<OutputType>`. Defaults to [OutputKind.library].
  final OutputKind outputKind;

  /// Resolved C# language version string, e.g. "12.0". Defaults to "Latest".
  final String langVersion;

  /// True when `<Nullable>enable</Nullable>` is set in the project file.
  final bool nullableEnabled;

  /// The fully-configured Roslyn CSharpCompilation for this project.
  final CSharpCompilation compilation;

  /// Resolved NuGet package references with tier and Dart mapping annotations.
  final List<PackageReferenceEntry> packageReferences;

  /// Diagnostics scoped to this project (PL + NR + CS prefixes).
  final List<Diagnostic> diagnostics;

  const ProjectEntry({
    required this.projectPath,
    required this.projectName,
    required this.targetFramework,
    required this.outputKind,
    required this.langVersion,
    required this.nullableEnabled,
    required this.compilation,
    required this.packageReferences,
    required this.diagnostics,
  });
}
