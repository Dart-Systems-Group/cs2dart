import '../config/i_config_service.dart';
import '../project_loader/interfaces/i_compilation_builder.dart';
import '../project_loader/interfaces/i_input_parser.dart';
import '../project_loader/interfaces/i_nuget_handler.dart';
import '../project_loader/interfaces/i_sdk_resolver.dart';
import '../project_loader/project_loader_impl.dart';
import 'interfaces/i_project_loader.dart';

/// Adapts the concrete [ProjectLoader] to the orchestrator-facing
/// [IProjectLoader] interface.
///
/// The two [IProjectLoader] interfaces (one in `project_loader/interfaces/`
/// and one in `orchestrator/interfaces/`) have identical signatures but are
/// separate Dart types. This adapter bridges them so that [OrchestratorFactory]
/// can wire the real [ProjectLoader] without creating a circular dependency.
final class ProjectLoaderAdapter implements IProjectLoader {
  final ProjectLoader _inner;

  ProjectLoaderAdapter({
    required IInputParser inputParser,
    required ISdkResolver sdkResolver,
    required INuGetHandler nugetHandler,
    required ICompilationBuilder compilationBuilder,
  }) : _inner = ProjectLoader(
          inputParser: inputParser,
          sdkResolver: sdkResolver,
          nugetHandler: nugetHandler,
          compilationBuilder: compilationBuilder,
        );

  @override
  Future<LoadResult> load(String inputPath, IConfigService config) =>
      _inner.load(inputPath, config);
}
