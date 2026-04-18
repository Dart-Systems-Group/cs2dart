import 'package:cs2dart/src/orchestrator/interfaces/i_dart_generator.dart';
import 'package:cs2dart/src/orchestrator/models/stage_results.dart';

/// A test double for [IDartGenerator] that records whether it was called and
/// returns a pre-configured [GenResult].
///
/// By default returns a successful [GenResult] with one [OutputPackage] and no
/// diagnostics, so that the pipeline does not trigger an early exit.
///
/// Set [throwException] to make the fake throw instead of returning a result,
/// which exercises the Orchestrator's exception-wrapping logic.
final class FakeDartGenerator implements IDartGenerator {
  /// Whether [generate] has been called at least once.
  bool wasCalled = false;

  /// The result returned by [generate]. Defaults to a successful single-package result.
  GenResult result = const GenResult(
    packages: [
      OutputPackage(
        projectName: 'FakeProject',
        outputPath: '/fake/output/fake_project',
      ),
    ],
    diagnostics: [],
    success: true,
  );

  /// When non-null, [generate] throws this exception instead of returning [result].
  Exception? throwException;

  @override
  Future<GenResult> generate(IrBuildResult irBuildResult) async {
    wasCalled = true;
    if (throwException != null) throw throwException!;
    return result;
  }
}
