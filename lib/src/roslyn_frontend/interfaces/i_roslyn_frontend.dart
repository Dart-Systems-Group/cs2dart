import '../../config/i_config_service.dart';
import '../../project_loader/models/load_result.dart';
import '../models/frontend_result.dart';

export '../models/frontend_result.dart';

/// The public interface for the Roslyn_Frontend stage.
///
/// Accepts a [LoadResult] from the Project_Loader and an [IConfigService]
/// for all configuration values, and returns a [FrontendResult] containing
/// fully-normalized, semantically-annotated syntax trees.
///
/// The Orchestrator depends only on this interface; the concrete
/// [RoslynFrontend] implementation is injected at construction time.
abstract interface class IRoslynFrontend {
  /// Processes [loadResult] using [config] for all configuration values.
  ///
  /// Returns a [FrontendResult] that is always non-null.
  /// [FrontendResult.success] is false when any Error-severity diagnostic
  /// is present in [FrontendResult.diagnostics].
  Future<FrontendResult> process(LoadResult loadResult, IConfigService config);
}
