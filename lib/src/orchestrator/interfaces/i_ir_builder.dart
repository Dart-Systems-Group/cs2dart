import '../models/stage_results.dart';

export '../models/stage_results.dart' show FrontendResult, IrBuildResult;

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
