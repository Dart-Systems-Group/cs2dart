import 'package:cs2dart/src/orchestrator/interfaces/i_validator.dart';

/// A test double for [IValidator] that records whether it was called and
/// returns a pre-configured [TranspilerResult].
///
/// By default returns a successful [TranspilerResult] whose [packages] mirror
/// the packages from the [GenResult] passed to [validate], with no diagnostics.
///
/// Set [throwException] to make the fake throw instead of returning a result,
/// which exercises the Orchestrator's exception-wrapping logic.
final class FakeValidator implements IValidator {
  /// Whether [validate] has been called at least once.
  bool wasCalled = false;

  /// When non-null, [validate] returns this result instead of deriving one
  /// from the [GenResult] argument.
  TranspilerResult? result;

  /// When non-null, [validate] throws this exception instead of returning a result.
  Exception? throwException;

  @override
  Future<TranspilerResult> validate(GenResult genResult) async {
    wasCalled = true;
    if (throwException != null) throw throwException!;
    return result ??
        TranspilerResult(
          success: true,
          packages: genResult.packages,
          diagnostics: const [],
        );
  }
}
