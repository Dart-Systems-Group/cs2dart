import 'package:cs2dart/src/orchestrator/interfaces/i_roslyn_frontend.dart';
import 'package:cs2dart/src/project_loader/models/load_result.dart';

/// A test double for [IRoslynFrontend] that records whether it was called and
/// returns a pre-configured [FrontendResult].
///
/// By default returns a successful [FrontendResult] with one unit and no
/// diagnostics, so that the pipeline does not trigger an early exit.
///
/// Set [throwException] to make the fake throw instead of returning a result,
/// which exercises the Orchestrator's exception-wrapping logic.
final class FakeRoslynFrontend implements IRoslynFrontend {
  /// Whether [process] has been called at least once.
  bool wasCalled = false;

  /// The result returned by [process]. Defaults to a successful single-unit result.
  FrontendResult result = const FrontendResult(
    units: [Object()],
    diagnostics: [],
    success: true,
  );

  /// When non-null, [process] throws this exception instead of returning [result].
  Exception? throwException;

  @override
  Future<FrontendResult> process(LoadResult loadResult) async {
    wasCalled = true;
    if (throwException != null) throw throwException!;
    return result;
  }
}
