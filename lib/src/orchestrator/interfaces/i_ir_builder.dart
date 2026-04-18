import '../../roslyn_frontend/models/frontend_result.dart';
import '../models/stage_results.dart' hide FrontendResult;

export '../../roslyn_frontend/models/frontend_result.dart' show FrontendResult;
export '../models/stage_results.dart' show IrBuildResult;

/// The Orchestrator-facing interface for the IR_Builder stage.
///
/// Accepts a [FrontendResult] from the Roslyn_Frontend and returns an
/// [IrBuildResult] containing the intermediate representation units and
/// diagnostics.
///
/// The Orchestrator depends only on this interface; the concrete
/// [IrBuilder] implementation is injected at construction time.
abstract interface class IIrBuilder {
  /// Builds the intermediate representation from [frontendResult].
  ///
  /// Returns an [IrBuildResult] that is always non-null. [IrBuildResult.success]
  /// is false when any Error-severity diagnostic is present.
  Future<IrBuildResult> build(FrontendResult frontendResult);
}
