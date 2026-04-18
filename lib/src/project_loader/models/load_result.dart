import '../../config/models/config_object.dart';
import 'dependency_graph.dart';
import 'diagnostic.dart';
import 'project_entry.dart';

/// The complete output of the [IProjectLoader].
///
/// Always non-null. [success] is false when any Error-severity diagnostic
/// is present in [diagnostics].
final class LoadResult {
  /// Projects in topological dependency order (leaf projects first).
  ///
  /// Empty when [success] is false and no projects could be loaded.
  final List<ProjectEntry> projects;

  /// The full dependency graph of inter-project references.
  final DependencyGraph dependencyGraph;

  /// Aggregated diagnostics from all sub-components (PL + NR + CS prefixes).
  ///
  /// Ordered: PL diagnostics first, then NR diagnostics, within each group
  /// ordered by source file path then line number then column.
  final List<Diagnostic> diagnostics;

  /// True if and only if [diagnostics] contains no Error-severity entry.
  final bool success;

  /// The active [ConfigObject] for this pipeline run.
  ///
  /// Never null; contains default values when no `transpiler.yaml` was found.
  final ConfigObject config;

  const LoadResult({
    required this.projects,
    required this.dependencyGraph,
    required this.diagnostics,
    required this.success,
    required this.config,
  });
}
