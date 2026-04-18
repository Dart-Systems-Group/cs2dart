import '../../project_loader/models/output_kind.dart';
import '../../project_loader/models/package_reference_entry.dart';
import 'ir_nodes.dart';

export '../../project_loader/models/output_kind.dart';
export '../../project_loader/models/package_reference_entry.dart';
export 'ir_nodes.dart';

/// The complete output of the IR_Builder stage.
///
/// Contains one [IrCompilationUnit] per [FrontendUnit], in the same
/// topological order as the input [FrontendResult.units].
final class IrBuildResult {
  /// One [IrCompilationUnit] per [FrontendUnit], in topological order.
  final List<IrCompilationUnit> units;

  /// Aggregated IR-prefixed diagnostics from all units.
  final List<Diagnostic> diagnostics;

  /// True if and only if [diagnostics] contains no Error-severity entry.
  final bool success;

  const IrBuildResult({
    required this.units,
    required this.diagnostics,
    required this.success,
  });
}

/// The IR representation of one compiled C# project.
///
/// Corresponds to one [FrontendUnit] from the [FrontendResult].
final class IrCompilationUnit {
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

  /// NuGet package references with Tier and DartMapping populated.
  final List<PackageReferenceEntry> packageReferences;

  /// Top-level declaration nodes (namespaces, top-level types).
  final List<IrDeclarationNode> declarations;

  /// Diagnostics scoped to this compilation unit.
  final List<Diagnostic> diagnostics;

  const IrCompilationUnit({
    required this.projectName,
    required this.outputKind,
    required this.targetFramework,
    required this.langVersion,
    required this.nullableEnabled,
    required this.packageReferences,
    required this.declarations,
    required this.diagnostics,
  });
}
