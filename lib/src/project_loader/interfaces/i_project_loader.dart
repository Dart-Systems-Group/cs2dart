import '../../config/i_config_service.dart';
import '../models/load_result.dart';

/// The public interface for the Project_Loader, exposed to the Orchestrator.
///
/// Accepts a `.csproj` or `.sln` file path and returns a [LoadResult]
/// containing all loaded projects, the dependency graph, and diagnostics.
abstract interface class IProjectLoader {
  /// Loads the project or solution at [inputPath] using [config] for all
  /// configuration values.
  ///
  /// Returns a [LoadResult] that is always non-null. [LoadResult.success]
  /// is false when any Error-severity diagnostic is present.
  Future<LoadResult> load(String inputPath, IConfigService config);
}
