import '../../project_loader/models/output_kind.dart';
import '../../project_loader/models/package_reference_entry.dart';
import 'normalized_syntax_tree.dart';

export '../../project_loader/models/output_kind.dart';
export '../../project_loader/models/package_reference_entry.dart';

/// The normalized, fully-annotated representation of one C# project.
final class FrontendUnit {
  /// The assembly name of the project.
  final String projectName;

  /// Output kind: Exe, Library, or WinExe.
  final OutputKind outputKind;

  /// Resolved target framework moniker, e.g. "net8.0".
  final String targetFramework;

  /// Resolved C# language version string, e.g. "12.0".
  final String langVersion;

  /// True when `<Nullable>enable</Nullable>` is set in the project file.
  final bool nullableEnabled;

  /// Resolved NuGet package references (propagated from ProjectEntry).
  final List<PackageReferenceEntry> packageReferences;

  /// One [NormalizedSyntaxTree] per source file, in alphabetical order
  /// by file path. Partial class merging may reduce the logical count
  /// of declaration nodes but does not reduce the tree count.
  final List<NormalizedSyntaxTree> normalizedTrees;

  const FrontendUnit({
    required this.projectName,
    required this.outputKind,
    required this.targetFramework,
    required this.langVersion,
    required this.nullableEnabled,
    required this.packageReferences,
    required this.normalizedTrees,
  });
}
