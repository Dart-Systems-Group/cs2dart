// Validates: Requirements 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 12.7
import 'package:test/test.dart';
import 'package:cs2dart/src/config/models/config_object.dart';
import 'package:cs2dart/src/config/models/source_location.dart';
import 'package:cs2dart/src/project_loader/models/compilation_options.dart';
import 'package:cs2dart/src/project_loader/models/dependency_graph.dart';
import 'package:cs2dart/src/project_loader/models/load_result.dart';
import 'package:cs2dart/src/project_loader/models/output_kind.dart';
import 'package:cs2dart/src/project_loader/models/project_entry.dart';
import 'package:cs2dart/src/project_loader/models/roslyn_interop.dart';
import 'package:cs2dart/src/roslyn_frontend/frontend_result_assembler.dart';
import 'package:cs2dart/src/roslyn_frontend/models/frontend_result.dart';
import 'package:cs2dart/src/roslyn_frontend/roslyn_frontend_impl.dart';
import 'fakes/fake_interop_bridge.dart';
import 'fakes/fake_config_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [Diagnostic] with the given fields.
Diagnostic _diag({
  required String code,
  DiagnosticSeverity severity = DiagnosticSeverity.warning,
  String message = 'test diagnostic',
  String? source,
  SourceLocation? location,
}) =>
    Diagnostic(
      severity: severity,
      code: code,
      message: message,
      source: source,
      location: location,
    );

/// Minimal [FrontendResult] with the given diagnostics and no units.
FrontendResult _workerResult(List<Diagnostic> diagnostics) => FrontendResult(
      units: const [],
      diagnostics: diagnostics,
      success: true,
    );

/// Minimal [LoadResult] with the given diagnostics and projects.
LoadResult _loadResult({
  List<Diagnostic> diagnostics = const [],
  List<ProjectEntry> projects = const [],
}) =>
    LoadResult(
      projects: projects,
      dependencyGraph: DependencyGraph.empty,
      diagnostics: diagnostics,
      success: true,
      config: ConfigObject.defaults,
    );

/// Creates a minimal [ProjectEntry] with the given name and diagnostics.
ProjectEntry _projectEntry({
  String name = 'TestProject',
  String path = '/src/TestProject.csproj',
  List<Diagnostic> diagnostics = const [],
}) =>
    ProjectEntry(
      projectPath: path,
      projectName: name,
      targetFramework: 'net8.0',
      outputKind: OutputKind.library,
      langVersion: '12.0',
      nullableEnabled: false,
      compilation: CSharpCompilation(
        assemblyName: name,
        syntaxTreePaths: const [],
        metadataReferences: const [],
        options: const CompilationOptions(
          outputKind: OutputKind.library,
          nullableEnabled: false,
          langVersion: '12.0',
        ),
      ),
      packageReferences: const [],
      diagnostics: diagnostics,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Requirement 12.2 — RF-prefixed diagnostic codes are in range RF0001–RF9999
  // -------------------------------------------------------------------------
  group('RF diagnostic code range (Requirement 12.2)', () {
    test('RF0001 is a valid RF-prefixed code', () {
      final diag = _diag(code: 'RF0001');
      expect(diag.code, startsWith('RF'));
      final number = int.parse(diag.code.substring(2));
      expect(number, inInclusiveRange(1, 9999));
    });

    test('RF9999 is a valid RF-prefixed code (upper boundary)', () {
      final diag = _diag(code: 'RF9999');
      expect(diag.code, startsWith('RF'));
      final number = int.parse(diag.code.substring(2));
      expect(number, inInclusiveRange(1, 9999));
    });

    test('all known RF diagnostic codes are in range RF0001–RF9999', () {
      // All RF codes used in the spec.
      const knownRfCodes = [
        'RF0001', // InteropException error
        'RF0002', // Unsupported LINQ / pattern warning
        'RF0003', // __arglist warning
        'RF0004', // Semantically incomplete declaration error
        'RF0005', // unsafe/fixed/stackalloc error
        'RF0006', // goto/labeled statement warning
        'RF0007', // dynamic type warning
        'RF0008', // UnresolvedType warning
        'RF0009', // fire-and-forget async info
        'RF0010', // unknown attribute info
        'RF0011', // project skipped warning
        'RF0012', // duplicate suppressed warning
      ];

      for (final code in knownRfCodes) {
        expect(code, startsWith('RF'),
            reason: '$code should start with RF');
        final number = int.tryParse(code.substring(2));
        expect(number, isNotNull,
            reason: '$code suffix should be numeric');
        expect(number, inInclusiveRange(1, 9999),
            reason: '$code should be in range RF0001–RF9999');
      }
    });

    test('RF code format is exactly RF followed by 4 digits', () {
      const codes = ['RF0001', 'RF0012', 'RF9999'];
      final pattern = RegExp(r'^RF\d{4}$');
      for (final code in codes) {
        expect(pattern.hasMatch(code), isTrue,
            reason: '$code should match RF followed by 4 digits');
      }
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 12.3 — Duplicate diagnostics are suppressed with RF0012
  // (tested via FrontendResultAssembler)
  // -------------------------------------------------------------------------
  group('duplicate diagnostic suppression with RF0012 (Requirement 12.3)', () {
    final assembler = const FrontendResultAssembler();

    test('duplicate diagnostic (same code, source, location) emits RF0012 Warning',
        () {
      const loc = SourceLocation(filePath: 'Foo.cs', line: 5, column: 3);
      final diag = _diag(code: 'RF0001', source: 'Foo.cs', location: loc);

      final result = assembler.assemble(
        _workerResult([diag, diag]),
        _loadResult(),
      );

      final rf0012s = result.diagnostics.where((d) => d.code == 'RF0012');
      expect(rf0012s, hasLength(1));
      expect(rf0012s.first.severity, DiagnosticSeverity.warning);
    });

    test('original diagnostic is kept; only the duplicate is suppressed', () {
      const loc = SourceLocation(filePath: 'Foo.cs', line: 5, column: 3);
      final diag = _diag(code: 'RF0002', source: 'Foo.cs', location: loc);

      final result = assembler.assemble(
        _workerResult([diag, diag]),
        _loadResult(),
      );

      final rf0002s = result.diagnostics.where((d) => d.code == 'RF0002');
      expect(rf0002s, hasLength(1));
    });

    test('three copies of the same diagnostic emit two RF0012 warnings', () {
      const loc = SourceLocation(filePath: 'Bar.cs', line: 1, column: 1);
      final diag = _diag(code: 'RF0003', source: 'Bar.cs', location: loc);

      final result = assembler.assemble(
        _workerResult([diag, diag, diag]),
        _loadResult(),
      );

      final rf0012s = result.diagnostics.where((d) => d.code == 'RF0012');
      expect(rf0012s, hasLength(2));
    });

    test('RF0012 message references the suppressed diagnostic code', () {
      const loc = SourceLocation(filePath: 'X.cs', line: 10, column: 2);
      final diag = _diag(code: 'RF0007', source: 'X.cs', location: loc);

      final result = assembler.assemble(
        _workerResult([diag, diag]),
        _loadResult(),
      );

      final rf0012 = result.diagnostics.firstWhere((d) => d.code == 'RF0012');
      expect(rf0012.message, contains('RF0007'));
    });

    test('diagnostics with different codes at same location are not duplicates',
        () {
      const loc = SourceLocation(filePath: 'A.cs', line: 1, column: 1);
      final diag1 = _diag(code: 'RF0001', source: 'A.cs', location: loc);
      final diag2 = _diag(code: 'RF0002', source: 'A.cs', location: loc);

      final result = assembler.assemble(
        _workerResult([diag1, diag2]),
        _loadResult(),
      );

      expect(result.diagnostics.where((d) => d.code == 'RF0012'), isEmpty);
    });

    test('diagnostics with same code at different locations are not duplicates',
        () {
      const loc1 = SourceLocation(filePath: 'A.cs', line: 1, column: 1);
      const loc2 = SourceLocation(filePath: 'A.cs', line: 2, column: 1);
      final diag1 = _diag(code: 'RF0001', source: 'A.cs', location: loc1);
      final diag2 = _diag(code: 'RF0001', source: 'A.cs', location: loc2);

      final result = assembler.assemble(
        _workerResult([diag1, diag2]),
        _loadResult(),
      );

      expect(result.diagnostics.where((d) => d.code == 'RF0012'), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 12.7 — Roslyn CS-prefixed diagnostics are propagated unchanged
  // (tested via FrontendResultAssembler)
  // -------------------------------------------------------------------------
  group('CS-prefixed Roslyn diagnostics propagated unchanged (Requirement 12.7)',
      () {
    final assembler = const FrontendResultAssembler();

    test('CS-prefixed diagnostic in worker result appears in FrontendResult.diagnostics',
        () {
      final csDiag = _diag(
        code: 'CS0246',
        severity: DiagnosticSeverity.error,
        message: "The type or namespace name 'Foo' could not be found",
        source: 'Program.cs',
      );

      final result = assembler.assemble(
        _workerResult([csDiag]),
        _loadResult(),
      );

      final cs0246s = result.diagnostics.where((d) => d.code == 'CS0246');
      expect(cs0246s, hasLength(1));
    });

    test('CS diagnostic code is preserved unchanged', () {
      final csDiag = _diag(
        code: 'CS1002',
        severity: DiagnosticSeverity.error,
        message: '; expected',
        source: 'Foo.cs',
      );

      final result = assembler.assemble(
        _workerResult([csDiag]),
        _loadResult(),
      );

      expect(result.diagnostics.first.code, 'CS1002');
    });

    test('CS diagnostic severity is preserved unchanged', () {
      final csError = _diag(
        code: 'CS0246',
        severity: DiagnosticSeverity.error,
        message: 'type not found',
      );
      final csWarning = _diag(
        code: 'CS8600',
        severity: DiagnosticSeverity.warning,
        message: 'Converting null literal',
      );

      final result = assembler.assemble(
        _workerResult([csError, csWarning]),
        _loadResult(),
      );

      final cs0246 = result.diagnostics.firstWhere((d) => d.code == 'CS0246');
      final cs8600 = result.diagnostics.firstWhere((d) => d.code == 'CS8600');
      expect(cs0246.severity, DiagnosticSeverity.error);
      expect(cs8600.severity, DiagnosticSeverity.warning);
    });

    test('CS diagnostic message is preserved unchanged', () {
      const originalMessage = "The type or namespace name 'Bar' could not be found";
      final csDiag = _diag(
        code: 'CS0246',
        severity: DiagnosticSeverity.error,
        message: originalMessage,
        source: 'Bar.cs',
      );

      final result = assembler.assemble(
        _workerResult([csDiag]),
        _loadResult(),
      );

      expect(result.diagnostics.first.message, originalMessage);
    });

    test('CS diagnostic source location is preserved unchanged', () {
      const loc = SourceLocation(filePath: 'Program.cs', line: 42, column: 7);
      final csDiag = _diag(
        code: 'CS0103',
        severity: DiagnosticSeverity.error,
        message: "The name 'x' does not exist in the current context",
        source: 'Program.cs',
        location: loc,
      );

      final result = assembler.assemble(
        _workerResult([csDiag]),
        _loadResult(),
      );

      final propagated = result.diagnostics.firstWhere((d) => d.code == 'CS0103');
      expect(propagated.source, 'Program.cs');
      expect(propagated.location?.line, 42);
      expect(propagated.location?.column, 7);
    });

    test('multiple CS diagnostics are all propagated', () {
      final cs1 = _diag(code: 'CS0246', severity: DiagnosticSeverity.error);
      final cs2 = _diag(code: 'CS1002', severity: DiagnosticSeverity.error);
      final cs3 = _diag(code: 'CS8600', severity: DiagnosticSeverity.warning);

      final result = assembler.assemble(
        _workerResult([cs1, cs2, cs3]),
        _loadResult(),
      );

      expect(result.diagnostics.any((d) => d.code == 'CS0246'), isTrue);
      expect(result.diagnostics.any((d) => d.code == 'CS1002'), isTrue);
      expect(result.diagnostics.any((d) => d.code == 'CS8600'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 12.6 — FrontendResult.success = false when any Error present
  // (tested via FrontendResultAssembler)
  // -------------------------------------------------------------------------
  group('FrontendResult.success = false when Error diagnostic present (Requirement 12.6)',
      () {
    final assembler = const FrontendResultAssembler();

    test('success = false when RF Error diagnostic is present', () {
      final errorDiag = _diag(
        code: 'RF0005',
        severity: DiagnosticSeverity.error,
      );

      final result = assembler.assemble(
        _workerResult([errorDiag]),
        _loadResult(),
      );

      expect(result.success, isFalse);
    });

    test('success = false when CS Error diagnostic is present', () {
      final csDiag = _diag(
        code: 'CS0246',
        severity: DiagnosticSeverity.error,
      );

      final result = assembler.assemble(
        _workerResult([csDiag]),
        _loadResult(),
      );

      expect(result.success, isFalse);
    });

    test('success = false when PL Error diagnostic is present', () {
      final plError = _diag(
        code: 'PL0001',
        severity: DiagnosticSeverity.error,
      );

      final result = assembler.assemble(
        _workerResult([]),
        _loadResult(diagnostics: [plError]),
      );

      expect(result.success, isFalse);
    });

    test('success = false when mixed severities include at least one Error', () {
      final warn = _diag(code: 'RF0001', severity: DiagnosticSeverity.warning);
      final error = _diag(code: 'RF0005', severity: DiagnosticSeverity.error);
      final info = _diag(code: 'RF0009', severity: DiagnosticSeverity.info);

      final result = assembler.assemble(
        _workerResult([warn, error, info]),
        _loadResult(),
      );

      expect(result.success, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 12.5 — FrontendResult.success = true when only Warning/Info
  // (tested via FrontendResultAssembler)
  // -------------------------------------------------------------------------
  group('FrontendResult.success = true when only Warning/Info (Requirement 12.5)',
      () {
    final assembler = const FrontendResultAssembler();

    test('success = true when only Warning diagnostics are present', () {
      final warn = _diag(
        code: 'RF0001',
        severity: DiagnosticSeverity.warning,
      );

      final result = assembler.assemble(
        _workerResult([warn]),
        _loadResult(),
      );

      expect(result.success, isTrue);
    });

    test('success = true when only Info diagnostics are present', () {
      final info = _diag(
        code: 'RF0009',
        severity: DiagnosticSeverity.info,
      );

      final result = assembler.assemble(
        _workerResult([info]),
        _loadResult(),
      );

      expect(result.success, isTrue);
    });

    test('success = true when Warning and Info diagnostics are mixed', () {
      final warn = _diag(code: 'RF0001', severity: DiagnosticSeverity.warning);
      final info = _diag(code: 'RF0009', severity: DiagnosticSeverity.info);

      final result = assembler.assemble(
        _workerResult([warn, info]),
        _loadResult(),
      );

      expect(result.success, isTrue);
    });

    test('success = true when no diagnostics are present', () {
      final result = assembler.assemble(
        _workerResult([]),
        _loadResult(),
      );

      expect(result.success, isTrue);
    });

    test('success = true when CS Warning diagnostic is present', () {
      final csWarn = _diag(
        code: 'CS8600',
        severity: DiagnosticSeverity.warning,
      );

      final result = assembler.assemble(
        _workerResult([csWarn]),
        _loadResult(),
      );

      expect(result.success, isTrue);
    });

    test('RF0012 Warning does not cause success = false', () {
      const loc = SourceLocation(filePath: 'X.cs', line: 1, column: 1);
      final diag = _diag(
        code: 'RF0001',
        severity: DiagnosticSeverity.warning,
        source: 'X.cs',
        location: loc,
      );

      // Two copies → RF0012 Warning is emitted; no Error → success = true.
      final result = assembler.assemble(
        _workerResult([diag, diag]),
        _loadResult(),
      );

      expect(result.success, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 12.1 / 1.7 — RF0011 Warning for each project skipped due to
  // upstream Error diagnostics (tested via RoslynFrontend.process())
  // -------------------------------------------------------------------------
  group('RF0011 Warning for skipped projects (Requirement 12.1 / 1.7)', () {
    test('RF0011 Warning is emitted for a project with upstream Error diagnostics',
        () async {
      final errorProject = _projectEntry(
        name: 'BrokenProject',
        path: '/src/BrokenProject.csproj',
        diagnostics: [
          _diag(
            code: 'PL0001',
            severity: DiagnosticSeverity.error,
            message: 'project load failed',
          ),
        ],
      );

      final bridge = FakeInteropBridge();
      final frontend = RoslynFrontend(bridge: bridge);
      final config = FakeConfigService();

      final result = await frontend.process(
        _loadResult(projects: [errorProject]),
        config,
      );

      final rf0011s = result.diagnostics.where((d) => d.code == 'RF0011');
      expect(rf0011s, hasLength(1));
      expect(rf0011s.first.severity, DiagnosticSeverity.warning);
    });

    test('RF0011 message references the skipped project name', () async {
      final errorProject = _projectEntry(
        name: 'FailingLib',
        path: '/src/FailingLib.csproj',
        diagnostics: [
          _diag(
            code: 'PL0002',
            severity: DiagnosticSeverity.error,
            message: 'compilation error',
          ),
        ],
      );

      final bridge = FakeInteropBridge();
      final frontend = RoslynFrontend(bridge: bridge);
      final config = FakeConfigService();

      final result = await frontend.process(
        _loadResult(projects: [errorProject]),
        config,
      );

      final rf0011 = result.diagnostics.firstWhere((d) => d.code == 'RF0011');
      expect(rf0011.message, contains('FailingLib'));
    });

    test('one RF0011 is emitted per skipped project', () async {
      final errorProject1 = _projectEntry(
        name: 'BrokenA',
        path: '/src/BrokenA.csproj',
        diagnostics: [
          _diag(
            code: 'PL0001',
            severity: DiagnosticSeverity.error,
          ),
        ],
      );
      final errorProject2 = _projectEntry(
        name: 'BrokenB',
        path: '/src/BrokenB.csproj',
        diagnostics: [
          _diag(
            code: 'PL0001',
            severity: DiagnosticSeverity.error,
          ),
        ],
      );

      final bridge = FakeInteropBridge();
      final frontend = RoslynFrontend(bridge: bridge);
      final config = FakeConfigService();

      final result = await frontend.process(
        _loadResult(projects: [errorProject1, errorProject2]),
        config,
      );

      final rf0011s = result.diagnostics.where((d) => d.code == 'RF0011');
      expect(rf0011s, hasLength(2));
    });

    test('healthy project is not skipped and does not emit RF0011', () async {
      final healthyProject = _projectEntry(
        name: 'HealthyProject',
        path: '/src/HealthyProject.csproj',
        diagnostics: const [],
      );

      final bridge = FakeInteropBridge();
      final frontend = RoslynFrontend(bridge: bridge);
      final config = FakeConfigService();

      final result = await frontend.process(
        _loadResult(projects: [healthyProject]),
        config,
      );

      final rf0011s = result.diagnostics.where((d) => d.code == 'RF0011');
      expect(rf0011s, isEmpty);
    });

    test('skipped project is not included in the InteropRequest sent to bridge',
        () async {
      final errorProject = _projectEntry(
        name: 'SkippedProject',
        path: '/src/SkippedProject.csproj',
        diagnostics: [
          _diag(
            code: 'PL0001',
            severity: DiagnosticSeverity.error,
          ),
        ],
      );
      final healthyProject = _projectEntry(
        name: 'HealthyProject',
        path: '/src/HealthyProject.csproj',
        diagnostics: const [],
      );

      final bridge = FakeInteropBridge();
      final frontend = RoslynFrontend(bridge: bridge);
      final config = FakeConfigService();

      await frontend.process(
        _loadResult(projects: [errorProject, healthyProject]),
        config,
      );

      // Only the healthy project should be in the request.
      expect(bridge.lastRequest?.projects, hasLength(1));
      expect(bridge.lastRequest?.projects.first.projectName, 'HealthyProject');
    });

    test('RF0011 is a Warning (not Error), so success can still be true when only RF0011 present',
        () async {
      final errorProject = _projectEntry(
        name: 'BrokenProject',
        path: '/src/BrokenProject.csproj',
        diagnostics: [
          _diag(
            code: 'PL0001',
            severity: DiagnosticSeverity.error,
          ),
        ],
      );

      // Bridge returns a clean result with no errors.
      final bridge = FakeInteropBridge(
        result: const FrontendResult(
          units: [],
          diagnostics: [],
          success: true,
        ),
      );
      final frontend = RoslynFrontend(bridge: bridge);
      final config = FakeConfigService();

      final result = await frontend.process(
        // LoadResult itself has no PL Error diagnostics at the top level,
        // only the project-scoped ones.
        _loadResult(projects: [errorProject]),
        config,
      );

      // RF0011 is a Warning; no Error diagnostics → success = true.
      final rf0011s = result.diagnostics.where((d) => d.code == 'RF0011');
      expect(rf0011s, isNotEmpty);
      expect(rf0011s.first.severity, DiagnosticSeverity.warning);
      expect(result.success, isTrue);
    });
  });
}
