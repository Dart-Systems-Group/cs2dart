import '../models/stage_results.dart';
import '../models/transpiler_result.dart';

export '../models/stage_results.dart' show GenResult;
export '../models/transpiler_result.dart';

/// The Orchestrator-facing interface for the Validator stage.
///
/// Accepts a [GenResult] (with output paths already assigned) from the
/// Dart_Generator and returns the final [TranspilerResult].
///
/// The Validator internally invokes the Result_Collector to write artifacts
/// to disk and assemble the [TranspilerResult]. The Orchestrator depends only
/// on this interface; the concrete [Validator] implementation is injected at
/// construction time.
abstract interface class IValidator {
  /// Validates the generated packages in [genResult], runs any configured
  /// tooling (dart format, dart analyze), and assembles the final
  /// [TranspilerResult].
  ///
  /// Returns a [TranspilerResult] that is always non-null.
  Future<TranspilerResult> validate(GenResult genResult);
}
