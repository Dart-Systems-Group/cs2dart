import '../config/i_config_service.dart';
import '../project_loader/models/load_result.dart';
import '../project_loader/models/project_entry.dart';
import 'frontend_result_assembler.dart';
import 'interfaces/i_interop_bridge.dart';
import 'interfaces/i_roslyn_frontend.dart';
import 'models/interop_exception.dart';

/// Production implementation of [IRoslynFrontend].
///
/// Delegates all Roslyn work to the .NET worker process via [IInteropBridge],
/// then assembles the final [FrontendResult] using [FrontendResultAssembler].
final class RoslynFrontend implements IRoslynFrontend {
  final IInteropBridge _bridge;
  final FrontendResultAssembler _assembler;

  RoslynFrontend({
    required IInteropBridge bridge,
    FrontendResultAssembler? assembler,
  })  : _bridge = bridge,
        _assembler = assembler ?? const FrontendResultAssembler();

  @override
  Future<FrontendResult> process(
    LoadResult loadResult,
    IConfigService config,
  ) async {
    try {
      // 1. Build FrontendConfig from IConfigService.
      final frontendConfig = FrontendConfig(
        linqStrategy: config.linqStrategy.yamlValue,
        nullabilityEnabled: config.nullability.preserveNullableAnnotations,
        experimentalFeatures: config.experimentalFeatures,
      );

      // 2. Build InteropRequest, skipping projects with upstream Error diagnostics.
      final skippedWarnings = <Diagnostic>[];
      final projectRequests = <ProjectEntryRequest>[];

      for (final project in loadResult.projects) {
        if (_hasUpstreamErrors(project, loadResult)) {
          skippedWarnings.add(_buildRf0011Warning(project));
        } else {
          projectRequests.add(_buildProjectEntryRequest(project));
        }
      }

      final request = InteropRequest(
        projects: projectRequests,
        config: frontendConfig,
      );

      // 3. Invoke the .NET worker.
      final workerResult = await _bridge.invoke(request);

      // 4. Prepend RF0011 warnings to the worker result before assembling.
      final workerResultWithWarnings = skippedWarnings.isEmpty
          ? workerResult
          : FrontendResult(
              units: workerResult.units,
              diagnostics: [...skippedWarnings, ...workerResult.diagnostics],
              success: workerResult.success,
            );

      // 5. Assemble the final FrontendResult (merges PL diagnostics, deduplicates, sets success).
      return _assembler.assemble(workerResultWithWarnings, loadResult);
    } on InteropException catch (e) {
      // 6. Wrap InteropException as an RF-prefixed Error diagnostic; never rethrow.
      final errorDiag = Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'RF0001',
        message: 'Interop bridge failure: ${e.message}',
      );
      return FrontendResult(
        units: const [],
        diagnostics: [errorDiag],
        success: false,
      );
    }
  }

  /// Returns true if [project] has any Error-severity diagnostic in [loadResult].
  ///
  /// Checks both the project's own [ProjectEntry.diagnostics] and the
  /// load-result-level diagnostics whose [Diagnostic.source] matches the
  /// project file path.
  bool _hasUpstreamErrors(ProjectEntry project, LoadResult loadResult) {
    // Check project-scoped diagnostics.
    if (project.diagnostics.any(
      (d) => d.severity == DiagnosticSeverity.error,
    )) {
      return true;
    }
    // Check load-result diagnostics scoped to this project's file path.
    return loadResult.diagnostics.any(
      (d) =>
          d.severity == DiagnosticSeverity.error &&
          d.source == project.projectPath,
    );
  }

  /// Builds an [RF0011] Warning for a project skipped due to upstream errors.
  Diagnostic _buildRf0011Warning(ProjectEntry project) {
    return Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: 'RF0011',
      message:
          'Project "${project.projectName}" skipped due to upstream '
          'Error-severity diagnostics in Load_Result.',
      source: project.projectPath,
    );
  }

  /// Converts a [ProjectEntry] to a [ProjectEntryRequest] for the interop bridge.
  ///
  /// Source file paths are sorted alphabetically as required by the spec.
  ProjectEntryRequest _buildProjectEntryRequest(ProjectEntry project) {
    final sortedPaths = List<String>.from(
      project.compilation.syntaxTreePaths,
    )..sort();

    return ProjectEntryRequest(
      projectName: project.projectName,
      projectFilePath: project.projectPath,
      outputKind: project.outputKind,
      targetFramework: project.targetFramework,
      langVersion: project.langVersion,
      nullableEnabled: project.nullableEnabled,
      packageReferences: project.packageReferences,
      sourceFilePaths: sortedPaths,
    );
  }
}
