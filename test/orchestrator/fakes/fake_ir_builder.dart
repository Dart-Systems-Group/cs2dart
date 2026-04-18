import 'package:cs2dart/src/orchestrator/interfaces/i_ir_builder.dart';

/// A test double for [IIrBuilder] that records whether it was called and
/// returns a pre-configured [IrBuildResult].
///
/// By default returns a successful [IrBuildResult] with one unit and no
/// diagnostics, so that the pipeline does not trigger an early exit.
///
/// Set [throwException] to make the fake throw instead of returning a result,
/// which exercises the Orchestrator's exception-wrapping logic.
final class FakeIrBuilder implements IIrBuilder {
  /// Whether [build] has been called at least once.
  bool wasCalled = false;

  /// The result returned by [build]. Defaults to a successful single-unit result.
  IrBuildResult result = const IrBuildResult(
    units: [Object()],
    diagnostics: [],
    success: true,
  );

  /// When non-null, [build] throws this exception instead of returning [result].
  Exception? throwException;

  @override
  Future<IrBuildResult> build(FrontendResult frontendResult) async {
    wasCalled = true;
    if (throwException != null) throw throwException!;
    return result;
  }
}
