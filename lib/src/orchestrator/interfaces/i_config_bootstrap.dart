import '../../config/config_load_result.dart';
import '../../pipeline_bootstrap.dart';

export '../../config/config_load_result.dart';
export '../../pipeline_bootstrap.dart' show PipelineContainer;

/// The Orchestrator-facing interface for configuration bootstrapping.
///
/// Wraps the [bootstrapPipeline] function from [pipeline_bootstrap.dart] as
/// an injectable collaborator, allowing tests to supply a fake config without
/// touching the file system.
///
/// The Orchestrator calls [load] as the very first action of every
/// [Orchestrator.transpile] invocation, before constructing or invoking any
/// other pipeline stage.
abstract interface class IConfigBootstrap {
  /// Loads and validates the transpiler configuration.
  ///
  /// When [explicitConfigPath] is non-null, it is used as the config file
  /// path directly, bypassing directory search. When null, the standard
  /// directory search starting from the directory containing [entryPath]
  /// is performed.
  ///
  /// Always returns the [ConfigLoadResult] so the caller can render
  /// diagnostics. The [PipelineContainer] is non-null only when
  /// [ConfigLoadResult.hasErrors] is false.
  Future<(ConfigLoadResult, PipelineContainer?)> load({
    required String entryPath,
    String? explicitConfigPath,
  });
}
