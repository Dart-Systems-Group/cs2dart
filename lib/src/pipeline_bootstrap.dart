import 'config/config_load_result.dart';
import 'config/config_loader.dart';
import 'config/i_config_service.dart';
import 'project_loader/compilation_builder.dart';
import 'project_loader/input_parser.dart';
import 'project_loader/interfaces/i_project_loader.dart';
import 'project_loader/nuget_handler.dart';
import 'project_loader/project_loader_impl.dart';
import 'project_loader/sdk_resolver.dart';
import 'roslyn_frontend/frontend_result_assembler.dart';
import 'roslyn_frontend/interfaces/i_roslyn_frontend.dart';
import 'roslyn_frontend/pipe_interop_bridge.dart';
import 'roslyn_frontend/roslyn_frontend_impl.dart';

/// A minimal service container that holds the [IConfigService] singleton
/// and pre-wired pipeline stage instances for the current pipeline run.
///
/// Constructed by [bootstrapPipeline] after a successful config load.
/// Pipeline modules receive [IConfigService] via constructor injection
/// from this container — they never call [ConfigLoader] directly.
final class PipelineContainer {
  /// The single [IConfigService] instance for this pipeline run.
  final IConfigService configService;

  /// The fully-wired [IRoslynFrontend] instance for this pipeline run.
  final IRoslynFrontend roslynFrontend;

  const PipelineContainer({
    required this.configService,
    required this.roslynFrontend,
  });
}

/// Creates a fully wired [IProjectLoader] with all sub-component dependencies.
///
/// The [IConfigService] is passed to [IProjectLoader.load] at call time, not
/// at construction — so this factory requires no arguments.
IProjectLoader createProjectLoader() {
  return const ProjectLoader(
    inputParser: InputParser(),
    sdkResolver: SdkResolver(),
    nugetHandler: NuGetHandler(),
    compilationBuilder: CompilationBuilder(),
  );
}

/// Creates a fully wired [IRoslynFrontend] with all sub-component dependencies.
///
/// Uses [PipeInteropBridge] as the production [IInteropBridge] implementation.
/// [PipeInteropBridge] currently throws [UnimplementedError] — it is a
/// placeholder until the .NET worker communication layer is built.
///
/// The [IConfigService] is passed to [IRoslynFrontend.process] at call time,
/// not at construction — so this factory requires no arguments.
IRoslynFrontend createRoslynFrontend() {
  return RoslynFrontend(
    bridge: const PipeInteropBridge(),
    assembler: const FrontendResultAssembler(),
  );
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

  final container = PipelineContainer(
    configService: result.service!,
    roslynFrontend: createRoslynFrontend(),
  );
  return (result, container);
}
