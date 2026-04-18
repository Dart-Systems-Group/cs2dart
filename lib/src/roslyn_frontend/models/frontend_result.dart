import '../../project_loader/models/diagnostic.dart';
import 'frontend_unit.dart';

export '../../project_loader/models/diagnostic.dart';

/// The complete output of the Roslyn_Frontend stage.
///
/// This is the full model defined in the Roslyn Frontend specification.
/// The stub in `lib/src/orchestrator/models/stage_results.dart` remains
/// unchanged; this class is the authoritative definition.
final class FrontendResult {
  /// One [FrontendUnit] per project, in the same order as
  /// [LoadResult.projects] (topological, leaf-first).
  ///
  /// Empty when [success] is false and no units could be processed.
  final List<FrontendUnit> units;

  /// Aggregated diagnostics: PL diagnostics propagated from LoadResult,
  /// followed by RF-prefixed diagnostics from the frontend, followed by
  /// CS-prefixed Roslyn compiler diagnostics.
  final List<Diagnostic> diagnostics;

  /// True if and only if [diagnostics] contains no Error-severity entry.
  final bool success;

  const FrontendResult({
    required this.units,
    required this.diagnostics,
    required this.success,
  });
}
