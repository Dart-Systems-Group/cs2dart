import 'package:cs2dart/src/orchestrator/interfaces/i_config_bootstrap.dart';

import 'fake_config_service.dart';
import 'fake_roslyn_frontend.dart';

/// A test double for [IConfigBootstrap] that records whether it was called and
/// returns a pre-configured [(ConfigLoadResult, PipelineContainer?)] tuple.
///
/// By default returns a [ConfigLoadResult] with no diagnostics and a non-null
/// [PipelineContainer] backed by a [FakeConfigService], so that the pipeline
/// does not trigger an early exit at the config stage.
///
/// Set [throwException] to make the fake throw instead of returning a result,
/// which exercises the Orchestrator's exception-wrapping logic for config
/// bootstrap failures.
final class FakeConfigBootstrap implements IConfigBootstrap {
  /// Whether [load] has been called at least once.
  bool wasCalled = false;

  /// The result returned by [load]. Defaults to a no-error result with a
  /// non-null [PipelineContainer].
  (ConfigLoadResult, PipelineContainer?) result = (
    const ConfigLoadResult(
      service: null, // populated via container below
      config: null,
      diagnostics: [],
    ),
    PipelineContainer(
      configService: FakeConfigService(),
      roslynFrontend: FakeRoslynFrontend(),
    ),
  );

  /// When non-null, [load] throws this exception instead of returning [result].
  Exception? throwException;

  @override
  Future<(ConfigLoadResult, PipelineContainer?)> load({
    required String entryPath,
    String? explicitConfigPath,
  }) async {
    wasCalled = true;
    if (throwException != null) throw throwException!;
    return result;
  }
}
