import '../models/stage_results.dart';

export '../models/stage_results.dart' show GenResult, IrBuildResult;

/// The Orchestrator-facing interface for the Dart_Generator stage.
///
/// Accepts an [IrBuildResult] from the IR_Builder and returns a [GenResult]
/// containing the generated Dart packages and diagnostics.
///
/// The Orchestrator depends only on this interface; the concrete
/// [DartGenerator] implementation is injected at construction time.
abstract interface class IDartGenerator {
  /// Generates Dart packages from [irBuildResult].
  ///
  /// Returns a [GenResult] that is always non-null. [GenResult.success]
  /// is false when any Error-severity diagnostic is present.
  Future<GenResult> generate(IrBuildResult irBuildResult);
}
