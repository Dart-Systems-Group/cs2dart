import '../../config/i_config_service.dart';
import '../../project_loader/models/load_result.dart';

export '../../project_loader/models/load_result.dart';

/// The Orchestrator-facing interface for the Project_Loader stage.
///
/// Accepts a `.csproj` or `.sln` file path and an [IConfigService] instance,
/// and returns a [LoadResult] containing all loaded projects, the dependency
/// graph, and diagnostics.
///
/// The Orchestrator depends only on this interface; the concrete
/// [ProjectLoader] implementation is injected at construction time.
abstract interface class IProjectLoader {
  /// Loads the project or solution at [inputPath] using [config] for all
  /// configuration values.
  ///
  /// Returns a [LoadResult] that is always non-null. [LoadResult.success]
  /// is false when any Error-severity diagnostic is present.
  Future<LoadResult> load(String inputPath, IConfigService config);
}
