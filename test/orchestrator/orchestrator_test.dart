// Feature: pipeline-orchestrator
// Unit tests for Orchestrator.
// Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.1, 4.1–4.11,
//            5.6, 11.1–11.5

import 'package:test/test.dart';

import 'package:cs2dart/src/config/i_config_service.dart';
import 'package:cs2dart/src/config/models/config_diagnostic.dart';
import 'package:cs2dart/src/config/models/config_object.dart';
import 'package:cs2dart/src/config/models/diagnostic_severity.dart';
import 'package:cs2dart/src/orchestrator/orchestrator.dart';
import 'package:cs2dart/src/project_loader/models/dependency_graph.dart';

import 'fakes/fake_config_bootstrap.dart';
import 'fakes/fake_dart_generator.dart';
import 'fakes/fake_directory_manager.dart';
import 'fakes/fake_ir_builder.dart';
import 'fakes/fake_project_loader.dart';
import 'fakes/fake_roslyn_frontend.dart';
import 'fakes/fake_validator.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a fully-wired [Orchestrator] with all fakes injected.
///
/// Individual fakes can be overridden by passing them as named arguments.
Orchestrator _makeOrchestrator({
  FakeProjectLoader? projectLoader,
  FakeRoslynFrontend? roslynFrontend,
  FakeIrBuilder? irBuilder,
  FakeDartGenerator? dartGenerator,
  FakeValidator? validator,
  FakeConfigBootstrap? configBootstrap,
  FakeDirectoryManager? directoryManager,
}) {
  return Orchestrator(
    projectLoader: projectLoader ?? FakeProjectLoader(),
    roslynFrontend: roslynFrontend ?? FakeRoslynFrontend(),
    irBuilder: irBuilder ?? FakeIrBuilder(),
    dartGenerator: dartGenerator ?? FakeDartGenerator(),
    validator: validator ?? FakeValidator(),
    configBootstrap: configBootstrap ?? FakeConfigBootstrap(),
    directoryManager: directoryManager ?? FakeDirectoryManager(),
  );
}

/// Default valid [TranspilerOptions] for tests that don't care about options.
const _validOptions = TranspilerOptions(
  inputPath: '/fake/input.csproj',
  outputDirectory: '/fake/output',
);

// ---------------------------------------------------------------------------
// 1. TranspilerOptions field defaults
// ---------------------------------------------------------------------------

void main() {
  group('TranspilerOptions defaults', () {
    test('verbose defaults to false', () {
      const opts = TranspilerOptions(
        inputPath: '/a.csproj',
        outputDirectory: '/out',
      );
      expect(opts.verbose, isFalse);
    });

    test('skipFormat defaults to false', () {
      const opts = TranspilerOptions(
        inputPath: '/a.csproj',
        outputDirectory: '/out',
      );
      expect(opts.skipFormat, isFalse);
    });

    test('skipAnalyze defaults to false', () {
      const opts = TranspilerOptions(
        inputPath: '/a.csproj',
        outputDirectory: '/out',
      );
      expect(opts.skipAnalyze, isFalse);
    });

    test('configPath defaults to null', () {
      const opts = TranspilerOptions(
        inputPath: '/a.csproj',
        outputDirectory: '/out',
      );
      expect(opts.configPath, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // 2. Stage invocation order
  // -------------------------------------------------------------------------

  group('Stage invocation order', () {
    test('all stages are called in order on a successful run', () async {
      final callOrder = <String>[];

      final projectLoader = FakeProjectLoader();
      final roslynFrontend = FakeRoslynFrontend();
      final irBuilder = FakeIrBuilder();
      final dartGenerator = FakeDartGenerator();
      final validator = FakeValidator();
      final configBootstrap = FakeConfigBootstrap();

      // Wrap each fake to record call order.
      final recordingProjectLoader = _RecordingProjectLoader(
        projectLoader, callOrder, 'ProjectLoader');
      final recordingRoslynFrontend = _RecordingRoslynFrontend(
        roslynFrontend, callOrder, 'RoslynFrontend');
      final recordingIrBuilder = _RecordingIrBuilder(
        irBuilder, callOrder, 'IrBuilder');
      final recordingDartGenerator = _RecordingDartGenerator(
        dartGenerator, callOrder, 'DartGenerator');
      final recordingValidator = _RecordingValidator(
        validator, callOrder, 'Validator');
      final recordingConfigBootstrap = _RecordingConfigBootstrap(
        configBootstrap, callOrder, 'ConfigBootstrap');

      final orchestrator = Orchestrator(
        projectLoader: recordingProjectLoader,
        roslynFrontend: recordingRoslynFrontend,
        irBuilder: recordingIrBuilder,
        dartGenerator: recordingDartGenerator,
        validator: recordingValidator,
        configBootstrap: recordingConfigBootstrap,
        directoryManager: FakeDirectoryManager(),
      );

      await orchestrator.transpile(_validOptions);

      expect(callOrder, equals([
        'ConfigBootstrap',
        'ProjectLoader',
        'RoslynFrontend',
        'IrBuilder',
        'DartGenerator',
        'Validator',
      ]));
    });

    test('ConfigBootstrap is called before any stage', () async {
      final callOrder = <String>[];

      final configBootstrap = _RecordingConfigBootstrap(
        FakeConfigBootstrap(), callOrder, 'ConfigBootstrap');
      final projectLoader = _RecordingProjectLoader(
        FakeProjectLoader(), callOrder, 'ProjectLoader');

      final orchestrator = Orchestrator(
        projectLoader: projectLoader,
        roslynFrontend: FakeRoslynFrontend(),
        irBuilder: FakeIrBuilder(),
        dartGenerator: FakeDartGenerator(),
        validator: FakeValidator(),
        configBootstrap: configBootstrap,
        directoryManager: FakeDirectoryManager(),
      );

      await orchestrator.transpile(_validOptions);

      expect(callOrder.first, equals('ConfigBootstrap'));
      expect(callOrder.indexOf('ConfigBootstrap'),
          lessThan(callOrder.indexOf('ProjectLoader')));
    });
  });

  // -------------------------------------------------------------------------
  // 3. Early-exit conditions
  // -------------------------------------------------------------------------

  group('Early-exit: Config has errors', () {
    test('only ConfigBootstrap called; OR0005 in diagnostics', () async {
      final configBootstrap = FakeConfigBootstrap();
      configBootstrap.result = (
        ConfigLoadResult(
          service: null,
          config: null,
          diagnostics: [
            const ConfigDiagnostic(
              severity: DiagnosticSeverity.error,
              code: 'CFG0001',
              message: 'Bad config',
            ),
          ],
        ),
        null,
      );

      final projectLoader = FakeProjectLoader();
      final roslynFrontend = FakeRoslynFrontend();
      final irBuilder = FakeIrBuilder();
      final dartGenerator = FakeDartGenerator();
      final validator = FakeValidator();

      final orchestrator = _makeOrchestrator(
        configBootstrap: configBootstrap,
        projectLoader: projectLoader,
        roslynFrontend: roslynFrontend,
        irBuilder: irBuilder,
        dartGenerator: dartGenerator,
        validator: validator,
      );

      final result = await orchestrator.transpile(_validOptions);

      expect(result.success, isFalse);
      expect(projectLoader.wasCalled, isFalse);
      expect(roslynFrontend.wasCalled, isFalse);
      expect(irBuilder.wasCalled, isFalse);
      expect(dartGenerator.wasCalled, isFalse);
      expect(validator.wasCalled, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0005'), isTrue);
    });
  });

  group('Early-exit: ProjectLoader returns success=false AND empty projects', () {
    test('ProjectLoader called; RoslynFrontend NOT called; OR0005 in diagnostics', () async {
      final projectLoader = FakeProjectLoader();
      projectLoader.result = LoadResult(
        projects: const [],
        dependencyGraph: DependencyGraph.empty,
        diagnostics: const [],
        success: false,
        config: ConfigObject.defaults,
      );

      final roslynFrontend = FakeRoslynFrontend();
      final irBuilder = FakeIrBuilder();
      final dartGenerator = FakeDartGenerator();
      final validator = FakeValidator();

      final orchestrator = _makeOrchestrator(
        projectLoader: projectLoader,
        roslynFrontend: roslynFrontend,
        irBuilder: irBuilder,
        dartGenerator: dartGenerator,
        validator: validator,
      );

      final result = await orchestrator.transpile(_validOptions);

      expect(result.success, isFalse);
      expect(projectLoader.wasCalled, isTrue);
      expect(roslynFrontend.wasCalled, isFalse);
      expect(irBuilder.wasCalled, isFalse);
      expect(dartGenerator.wasCalled, isFalse);
      expect(validator.wasCalled, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0005'), isTrue);
    });
  });

  group('Early-exit: RoslynFrontend returns success=false AND empty units', () {
    test('IrBuilder NOT called; OR0005 in diagnostics', () async {
      final roslynFrontend = FakeRoslynFrontend();
      roslynFrontend.result = const FrontendResult(
        units: [],
        diagnostics: [],
        success: false,
      );

      final irBuilder = FakeIrBuilder();
      final dartGenerator = FakeDartGenerator();
      final validator = FakeValidator();

      final orchestrator = _makeOrchestrator(
        roslynFrontend: roslynFrontend,
        irBuilder: irBuilder,
        dartGenerator: dartGenerator,
        validator: validator,
      );

      final result = await orchestrator.transpile(_validOptions);

      expect(result.success, isFalse);
      expect(roslynFrontend.wasCalled, isTrue);
      expect(irBuilder.wasCalled, isFalse);
      expect(dartGenerator.wasCalled, isFalse);
      expect(validator.wasCalled, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0005'), isTrue);
    });
  });

  group('Early-exit: IrBuilder returns success=false AND empty units', () {
    test('DartGenerator NOT called; OR0005 in diagnostics', () async {
      final irBuilder = FakeIrBuilder();
      irBuilder.result = const IrBuildResult(
        units: [],
        diagnostics: [],
        success: false,
      );

      final dartGenerator = FakeDartGenerator();
      final validator = FakeValidator();

      final orchestrator = _makeOrchestrator(
        irBuilder: irBuilder,
        dartGenerator: dartGenerator,
        validator: validator,
      );

      final result = await orchestrator.transpile(_validOptions);

      expect(result.success, isFalse);
      expect(irBuilder.wasCalled, isTrue);
      expect(dartGenerator.wasCalled, isFalse);
      expect(validator.wasCalled, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0005'), isTrue);
    });
  });

  group('Early-exit: DartGenerator returns success=false AND empty packages', () {
    test('Validator NOT called; OR0005 in diagnostics', () async {
      final dartGenerator = FakeDartGenerator();
      dartGenerator.result = const GenResult(
        packages: [],
        diagnostics: [],
        success: false,
      );

      final validator = FakeValidator();

      final orchestrator = _makeOrchestrator(
        dartGenerator: dartGenerator,
        validator: validator,
      );

      final result = await orchestrator.transpile(_validOptions);

      expect(result.success, isFalse);
      expect(dartGenerator.wasCalled, isTrue);
      expect(validator.wasCalled, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0005'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // 4. No early-exit when success=false but collection non-empty
  // -------------------------------------------------------------------------

  group('No early-exit when success=false but collection non-empty', () {
    test('ProjectLoader success=false but non-empty projects → pipeline continues to RoslynFrontend', () async {
      final projectLoader = FakeProjectLoader();
      // Keep the default result (has one project) but mark success=false.
      projectLoader.result = LoadResult(
        projects: projectLoader.result.projects, // non-empty
        dependencyGraph: DependencyGraph.empty,
        diagnostics: const [],
        success: false,
        config: ConfigObject.defaults,
      );

      final roslynFrontend = FakeRoslynFrontend();

      final orchestrator = _makeOrchestrator(
        projectLoader: projectLoader,
        roslynFrontend: roslynFrontend,
      );

      await orchestrator.transpile(_validOptions);

      expect(projectLoader.wasCalled, isTrue);
      expect(roslynFrontend.wasCalled, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // 5. Exception wrapping (OR0001)
  // -------------------------------------------------------------------------

  group('Exception wrapping: OR0001 emitted, no re-throw', () {
    test('ProjectLoader throws → OR0001 in diagnostics, success=false, no exception propagated', () async {
      final projectLoader = FakeProjectLoader();
      projectLoader.throwException = Exception('ProjectLoader boom');

      final orchestrator = _makeOrchestrator(projectLoader: projectLoader);

      final TranspilerResult result;
      try {
        result = await orchestrator.transpile(_validOptions);
      } catch (_) {
        fail('Orchestrator should not propagate exceptions from stages');
      }

      expect(result.success, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0001'), isTrue);
    });

    test('RoslynFrontend throws → OR0001 in diagnostics, success=false, no exception propagated', () async {
      final roslynFrontend = FakeRoslynFrontend();
      roslynFrontend.throwException = Exception('RoslynFrontend boom');

      final orchestrator = _makeOrchestrator(roslynFrontend: roslynFrontend);

      final TranspilerResult result;
      try {
        result = await orchestrator.transpile(_validOptions);
      } catch (_) {
        fail('Orchestrator should not propagate exceptions from stages');
      }

      expect(result.success, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0001'), isTrue);
    });

    test('IrBuilder throws → OR0001 in diagnostics, success=false, no exception propagated', () async {
      final irBuilder = FakeIrBuilder();
      irBuilder.throwException = Exception('IrBuilder boom');

      final orchestrator = _makeOrchestrator(irBuilder: irBuilder);

      final TranspilerResult result;
      try {
        result = await orchestrator.transpile(_validOptions);
      } catch (_) {
        fail('Orchestrator should not propagate exceptions from stages');
      }

      expect(result.success, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0001'), isTrue);
    });

    test('DartGenerator throws → OR0001 in diagnostics, success=false, no exception propagated', () async {
      final dartGenerator = FakeDartGenerator();
      dartGenerator.throwException = Exception('DartGenerator boom');

      final orchestrator = _makeOrchestrator(dartGenerator: dartGenerator);

      final TranspilerResult result;
      try {
        result = await orchestrator.transpile(_validOptions);
      } catch (_) {
        fail('Orchestrator should not propagate exceptions from stages');
      }

      expect(result.success, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0001'), isTrue);
    });

    test('Validator throws → OR0001 in diagnostics, success=false, no exception propagated', () async {
      final validator = FakeValidator();
      validator.throwException = Exception('Validator boom');

      final orchestrator = _makeOrchestrator(validator: validator);

      final TranspilerResult result;
      try {
        result = await orchestrator.transpile(_validOptions);
      } catch (_) {
        fail('Orchestrator should not propagate exceptions from stages');
      }

      expect(result.success, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0001'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // 6. OR0002 / OR0003 for empty options
  // -------------------------------------------------------------------------

  group('OR0002 / OR0003 for empty options', () {
    test('empty inputPath → OR0002, no stages called', () async {
      final projectLoader = FakeProjectLoader();
      final configBootstrap = FakeConfigBootstrap();

      final orchestrator = _makeOrchestrator(
        projectLoader: projectLoader,
        configBootstrap: configBootstrap,
      );

      final result = await orchestrator.transpile(
        const TranspilerOptions(inputPath: '', outputDirectory: '/out'),
      );

      expect(result.success, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0002'), isTrue);
      expect(configBootstrap.wasCalled, isFalse);
      expect(projectLoader.wasCalled, isFalse);
    });

    test('empty outputDirectory → OR0003, no stages called', () async {
      final projectLoader = FakeProjectLoader();
      final configBootstrap = FakeConfigBootstrap();

      final orchestrator = _makeOrchestrator(
        projectLoader: projectLoader,
        configBootstrap: configBootstrap,
      );

      final result = await orchestrator.transpile(
        const TranspilerOptions(inputPath: '/a.csproj', outputDirectory: ''),
      );

      expect(result.success, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0003'), isTrue);
      expect(configBootstrap.wasCalled, isFalse);
      expect(projectLoader.wasCalled, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // 7. OR0004 for directory creation failure
  // -------------------------------------------------------------------------

  group('OR0004 for directory creation failure', () {
    test('DirectoryManager returns false → OR0004 in diagnostics, Validator NOT called', () async {
      final directoryManager = FakeDirectoryManager();
      directoryManager.result = false;

      final validator = FakeValidator();

      final orchestrator = _makeOrchestrator(
        directoryManager: directoryManager,
        validator: validator,
      );

      final result = await orchestrator.transpile(_validOptions);

      expect(result.success, isFalse);
      expect(result.diagnostics.any((d) => d.code == 'OR0004'), isTrue);
      expect(validator.wasCalled, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // 8. ConfigBootstrap called before any stage
  // -------------------------------------------------------------------------

  group('ConfigBootstrap called before any stage', () {
    test('configBootstrap.wasCalled is true before any stage is invoked', () async {
      bool configBootstrapCalledBeforeStages = false;
      final callOrder = <String>[];

      final configBootstrap = _RecordingConfigBootstrap(
        FakeConfigBootstrap(), callOrder, 'ConfigBootstrap');
      final projectLoader = _RecordingProjectLoader(
        FakeProjectLoader(), callOrder, 'ProjectLoader');

      final orchestrator = Orchestrator(
        projectLoader: projectLoader,
        roslynFrontend: FakeRoslynFrontend(),
        irBuilder: FakeIrBuilder(),
        dartGenerator: FakeDartGenerator(),
        validator: FakeValidator(),
        configBootstrap: configBootstrap,
        directoryManager: FakeDirectoryManager(),
      );

      await orchestrator.transpile(_validOptions);

      // ConfigBootstrap must appear before ProjectLoader in the call order.
      final configIdx = callOrder.indexOf('ConfigBootstrap');
      final projectIdx = callOrder.indexOf('ProjectLoader');
      configBootstrapCalledBeforeStages = configIdx >= 0 &&
          projectIdx >= 0 &&
          configIdx < projectIdx;

      expect(configBootstrapCalledBeforeStages, isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// Recording wrappers — delegate to fakes and append to a call-order list
// ---------------------------------------------------------------------------

final class _RecordingConfigBootstrap implements IConfigBootstrap {
  final FakeConfigBootstrap _inner;
  final List<String> _order;
  final String _name;

  _RecordingConfigBootstrap(this._inner, this._order, this._name);

  @override
  Future<(ConfigLoadResult, PipelineContainer?)> load({
    required String entryPath,
    String? explicitConfigPath,
  }) async {
    _order.add(_name);
    return _inner.load(entryPath: entryPath, explicitConfigPath: explicitConfigPath);
  }
}

final class _RecordingProjectLoader implements IProjectLoader {
  final FakeProjectLoader _inner;
  final List<String> _order;
  final String _name;

  _RecordingProjectLoader(this._inner, this._order, this._name);

  @override
  Future<LoadResult> load(String inputPath, IConfigService config) async {
    _order.add(_name);
    return _inner.load(inputPath, config);
  }
}

final class _RecordingRoslynFrontend implements IRoslynFrontend {
  final FakeRoslynFrontend _inner;
  final List<String> _order;
  final String _name;

  _RecordingRoslynFrontend(this._inner, this._order, this._name);

  @override
  Future<FrontendResult> process(LoadResult loadResult) async {
    _order.add(_name);
    return _inner.process(loadResult);
  }
}

final class _RecordingIrBuilder implements IIrBuilder {
  final FakeIrBuilder _inner;
  final List<String> _order;
  final String _name;

  _RecordingIrBuilder(this._inner, this._order, this._name);

  @override
  Future<IrBuildResult> build(FrontendResult frontendResult) async {
    _order.add(_name);
    return _inner.build(frontendResult);
  }
}

final class _RecordingDartGenerator implements IDartGenerator {
  final FakeDartGenerator _inner;
  final List<String> _order;
  final String _name;

  _RecordingDartGenerator(this._inner, this._order, this._name);

  @override
  Future<GenResult> generate(IrBuildResult irBuildResult) async {
    _order.add(_name);
    return _inner.generate(irBuildResult);
  }
}

final class _RecordingValidator implements IValidator {
  final FakeValidator _inner;
  final List<String> _order;
  final String _name;

  _RecordingValidator(this._inner, this._order, this._name);

  @override
  Future<TranspilerResult> validate(GenResult genResult) async {
    _order.add(_name);
    return _inner.validate(genResult);
  }
}
