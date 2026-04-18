import '../../project_loader/models/load_result.dart';
import '../models/stage_results.dart';

export '../models/stage_results.dart' show FrontendResult;

/// The Orchestrator-facing interface for the Roslyn_Frontend stage.
///
/// Accepts a [LoadResult] from the Project_Loader and returns a
/// [FrontendResult] containing the parsed compilation units and diagnostics.
///
/// The Orchestrator depends only on this interface; the concrete
/// [RoslynFrontend] implementation is injected at construction time.
abstract interface class IRoslynFrontend {
  /// Processes the loaded projects in [loadResult] through the Roslyn
  /// frontend, producing syntax trees and semantic models.
  ///
  /// Returns a [FrontendResult] that is always non-null. [FrontendResult.success]
  /// is false when any Error-severity diagnostic is present.
  Future<FrontendResult> process(LoadResult loadResult);
}
