import '../pipeline_bootstrap.dart';
import 'interfaces/i_config_bootstrap.dart';

export 'interfaces/i_config_bootstrap.dart';

/// Production implementation of [IConfigBootstrap].
///
/// Thin wrapper around [bootstrapPipeline] from `pipeline_bootstrap.dart`,
/// extracted as an injectable collaborator so tests can supply a fake config
/// without touching the file system.
///
/// The Orchestrator calls [load] as the very first action of every
/// `transpile()` invocation, before constructing or invoking any other
/// pipeline stage.
final class ConfigBootstrap implements IConfigBootstrap {
  const ConfigBootstrap();

  @override
  Future<(ConfigLoadResult, PipelineContainer?)> load({
    required String entryPath,
    String? explicitConfigPath,
  }) =>
      bootstrapPipeline(
        entryPath: entryPath,
        explicitConfigPath: explicitConfigPath,
      );
}
