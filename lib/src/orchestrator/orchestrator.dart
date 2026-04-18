import '../config/i_config_service.dart';
import 'config_bootstrap.dart';
import 'directory_manager.dart';
import 'interfaces/i_dart_generator.dart';
import 'interfaces/i_ir_builder.dart';
import 'interfaces/i_project_loader.dart';
import 'interfaces/i_roslyn_frontend.dart';
import 'interfaces/i_validator.dart';
import 'models/transpiler_options.dart';
import 'output_path_assigner.dart';
import 'override_config_service.dart';

export 'interfaces/i_config_bootstrap.dart';
export 'interfaces/i_dart_generator.dart';
export 'interfaces/i_ir_builder.dart';
export 'interfaces/i_project_loader.dart';
export 'interfaces/i_roslyn_frontend.dart';
export 'interfaces/i_validator.dart';
export 'models/stage_results.dart' hide FrontendResult;
export 'models/transpiler_options.dart';
export 'models/transpiler_result.dart';

/// Internal sentinel thrown by [_invokeStage] when a stage throws an
/// unhandled exception, carrying the pre-built early-exit [TranspilerResult].
final class _StageException implements Exception {
  final TranspilerResult earlyExitResult;
  const _StageException(this.earlyExitResult);
}

/// The top-level coordinator of the cs2dart transpiler pipeline.
///
/// Wires all six pipeline stages together in the fixed order defined by the
/// Pipeline Orchestrator specification, enforces the early-exit policy,
/// manages output directory layout, and assembles the final [TranspilerResult].
///
/// All stage dependencies are injected at construction time, making the
/// Orchestrator fully testable with fakes.
final class Orchestrator {
  final IProjectLoader _projectLoader;
  final IRoslynFrontend _roslynFrontend;
  final IIrBuilder _irBuilder;
  final IDartGenerator _dartGenerator;
  final IValidator _validator;
  final IConfigBootstrap _configBootstrap;
  final OutputPathAssigner _pathAssigner;
  final IDirectoryManager _directoryManager;

  const Orchestrator({
    required IProjectLoader projectLoader,
    required IRoslynFrontend roslynFrontend,
    required IIrBuilder irBuilder,
    required IDartGenerator dartGenerator,
    required IValidator validator,
    IConfigBootstrap? configBootstrap,
    OutputPathAssigner? pathAssigner,
    IDirectoryManager? directoryManager,
  })  : _projectLoader = projectLoader,
        _roslynFrontend = roslynFrontend,
        _irBuilder = irBuilder,
        _dartGenerator = dartGenerator,
        _validator = validator,
        _configBootstrap = configBootstrap ?? const ConfigBootstrap(),
        _pathAssigner = pathAssigner ?? const OutputPathAssigner(),
        _directoryManager = directoryManager ?? const DirectoryManager();

  /// Runs the full transpiler pipeline for the given [options].
  ///
  /// Always returns a [TranspilerResult] — never throws. Any unhandled
  /// exception from a pipeline stage is caught, wrapped in an [OR0001]
  /// diagnostic, and returned as a failed result.
  Future<TranspilerResult> transpile(TranspilerOptions options) async {
    // ── 7.2: Options validation ──────────────────────────────────────────────
    if (options.inputPath.isEmpty) {
      return TranspilerResult(
        success: false,
        packages: const [],
        diagnostics: const [
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'OR0002',
            message: 'InputPath is null or empty.',
          ),
        ],
      );
    }

    if (options.outputDirectory.isEmpty) {
      return TranspilerResult(
        success: false,
        packages: const [],
        diagnostics: const [
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'OR0003',
            message: 'OutputDirectory is null or empty.',
          ),
        ],
      );
    }

    // Accumulated diagnostics from all stages that have run so far.
    final collectedDiagnostics = <Diagnostic>[];

    try {
      // ── 7.3: Config bootstrapping ──────────────────────────────────────────
      final ConfigLoadResult configLoadResult;
      final PipelineContainer? container;

      try {
        (configLoadResult, container) = await _configBootstrap.load(
          entryPath: options.inputPath,
          explicitConfigPath: options.configPath,
        );
      } catch (e) {
        // Requirement 11.5: config bootstrap itself threw.
        final orDiag = Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'OR0001',
          message: 'Unhandled exception in Config_Service: $e',
        );
        return TranspilerResult(
          success: false,
          packages: const [],
          diagnostics: [...collectedDiagnostics, orDiag],
        );
      }

      // Collect CFG diagnostics (converted from ConfigDiagnostic to Diagnostic).
      for (final cfgDiag in configLoadResult.diagnostics) {
        collectedDiagnostics.add(Diagnostic(
          severity: cfgDiag.severity,
          code: cfgDiag.code,
          message: cfgDiag.message,
        ));
      }

      // Early-exit when config has errors (Requirement 2.6 / 4.1).
      if (configLoadResult.hasErrors) {
        return _earlyExit(
          collectedDiagnostics: collectedDiagnostics,
          stageName: 'Config_Service',
        );
      }

      // Apply SkipFormat / SkipAnalyze overrides (Requirement 2.4, 2.5).
      final IConfigService configService =
          _applyOverrides(container!.configService, options);

      // ── 7.4 + 7.6: Stage wiring with exception wrapping ───────────────────

      // Stage 1: ProjectLoader
      final loadResult = await _invokeStage(
        stageName: 'Project_Loader',
        collectedDiagnostics: collectedDiagnostics,
        invoke: () => _projectLoader.load(options.inputPath, configService),
      );

      collectedDiagnostics.addAll(loadResult.diagnostics);

      if (!loadResult.success && loadResult.projects.isEmpty) {
        return _earlyExit(
          collectedDiagnostics: collectedDiagnostics,
          stageName: 'Project_Loader',
        );
      }

      // Stage 2: RoslynFrontend
      final frontendResult = await _invokeStage(
        stageName: 'Roslyn_Frontend',
        collectedDiagnostics: collectedDiagnostics,
        invoke: () => _roslynFrontend.process(loadResult, configService),
      );

      collectedDiagnostics.addAll(frontendResult.diagnostics);

      if (!frontendResult.success && frontendResult.units.isEmpty) {
        return _earlyExit(
          collectedDiagnostics: collectedDiagnostics,
          stageName: 'Roslyn_Frontend',
        );
      }

      // Stage 3: IrBuilder
      final irBuildResult = await _invokeStage(
        stageName: 'IR_Builder',
        collectedDiagnostics: collectedDiagnostics,
        invoke: () => _irBuilder.build(frontendResult),
      );

      collectedDiagnostics.addAll(irBuildResult.diagnostics);

      if (!irBuildResult.success && irBuildResult.units.isEmpty) {
        return _earlyExit(
          collectedDiagnostics: collectedDiagnostics,
          stageName: 'IR_Builder',
        );
      }

      // Stage 4: DartGenerator
      final genResult = await _invokeStage(
        stageName: 'Dart_Generator',
        collectedDiagnostics: collectedDiagnostics,
        invoke: () => _dartGenerator.generate(irBuildResult),
      );

      collectedDiagnostics.addAll(genResult.diagnostics);

      if (!genResult.success && genResult.packages.isEmpty) {
        return _earlyExit(
          collectedDiagnostics: collectedDiagnostics,
          stageName: 'Dart_Generator',
        );
      }

      // ── 7.5: Output path assignment and directory creation ─────────────────

      // Assign output paths to each package.
      final assignedGenResult =
          _pathAssigner.assign(genResult, options.outputDirectory);

      // Collect any OR0006 collision diagnostics emitted by the assigner
      // (the assigner appends them after the original genResult diagnostics).
      final assignerDiags = assignedGenResult.diagnostics
          .skip(genResult.diagnostics.length)
          .toList();
      collectedDiagnostics.addAll(assignerDiags);

      // Ensure the output directory exists.
      final dirCreated =
          await _directoryManager.ensureExists(options.outputDirectory);
      if (!dirCreated) {
        final orDiag = Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'OR0004',
          message:
              'Output directory creation failed: "${options.outputDirectory}".',
        );
        collectedDiagnostics.add(orDiag);
        return TranspilerResult(
          success: false,
          packages: const [],
          diagnostics: List.unmodifiable(collectedDiagnostics),
        );
      }

      // Stage 5: Validator
      final validatorResult = await _invokeStage(
        stageName: 'Validator',
        collectedDiagnostics: collectedDiagnostics,
        invoke: () => _validator.validate(assignedGenResult),
      );

      return validatorResult;
    } on _StageException catch (ex) {
      // Propagated from _invokeStage when a stage throws an unhandled exception.
      return ex.earlyExitResult;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Applies [TranspilerOptions.skipFormat] / [skipAnalyze] overrides to
  /// [base], returning an [OverrideConfigService] when any override is needed,
  /// or [base] unchanged when neither flag is set.
  IConfigService _applyOverrides(
      IConfigService base, TranspilerOptions opts) {
    final overrides = <String, bool>{};
    if (opts.skipFormat) overrides['validation.skip_format'] = true;
    if (opts.skipAnalyze) overrides['validation.skip_analyze'] = true;
    if (overrides.isEmpty) return base;
    return OverrideConfigService(base, overrides);
  }

  /// Constructs a [TranspilerResult] representing an early exit after
  /// [stageName], appending an [OR0005] Info diagnostic.
  TranspilerResult _earlyExit({
    required List<Diagnostic> collectedDiagnostics,
    required String stageName,
  }) {
    final orDiag = Diagnostic(
      severity: DiagnosticSeverity.info,
      code: 'OR0005',
      message: 'Early exit after $stageName: stage returned empty result set.',
    );
    return TranspilerResult(
      success: false,
      packages: const [],
      diagnostics: [...collectedDiagnostics, orDiag],
    );
  }

  /// Invokes [invoke] inside a try/catch.
  ///
  /// On success, returns the result. On any exception, emits [OR0001] and
  /// throws a [_StageException] carrying the early-exit [TranspilerResult].
  Future<T> _invokeStage<T>({
    required String stageName,
    required List<Diagnostic> collectedDiagnostics,
    required Future<T> Function() invoke,
  }) async {
    try {
      return await invoke();
    } catch (e) {
      final orDiag = Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'OR0001',
        message: 'Unhandled exception in $stageName: $e',
      );
      throw _StageException(
        TranspilerResult(
          success: false,
          packages: const [],
          diagnostics: [...collectedDiagnostics, orDiag],
        ),
      );
    }
  }
}
