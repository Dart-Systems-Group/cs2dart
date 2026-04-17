import 'config/config_load_result.dart';
import 'config/config_loader.dart';
import 'config/i_config_service.dart';

/// A minimal service container that holds the [IConfigService] singleton
/// for the current pipeline run.
///
/// Constructed by [bootstrapPipeline] after a successful config load.
/// Pipeline modules receive [IConfigService] via constructor injection
/// from this container — they never call [ConfigLoader] directly.
final class PipelineContainer {
  /// The single [IConfigService] instance for this pipeline run.
  final IConfigService configService;

  const PipelineContainer({required this.configService});
}

/// Loads configuration and, when successful, returns a [PipelineContainer]
/// holding the registered [IConfigService] singleton.
///
/// Always returns the [ConfigLoadResult] so the caller (CLI layer) can render
/// diagnostics. The [PipelineContainer] is non-null only when
/// [ConfigLoadResult.hasErrors] is false.
///
/// Example usage:
/// ```dart
/// final (result, container) = await bootstrapPipeline(entryPath: 'MyApp.csproj');
/// for (final diag in result.diagnostics) {
///   DiagnosticRenderer.render(diag);
/// }
/// if (result.hasErrors) exit(1);
/// final irBuilder = IrBuilder(config: container!.configService);
/// ```
Future<(ConfigLoadResult, PipelineContainer?)> bootstrapPipeline({
  required String entryPath,
  String? explicitConfigPath,
}) async {
  final result = await ConfigLoader.load(
    entryPath: entryPath,
    explicitConfigPath: explicitConfigPath,
  );

  if (result.hasErrors) {
    return (result, null);
  }

  final container = PipelineContainer(configService: result.service!);
  return (result, container);
}
