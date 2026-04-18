// Feature: pipeline-orchestrator
// Tests for DiagnosticRenderer — unit tests and property-based tests.

import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import 'package:cs2dart/src/config/models/source_location.dart';
import 'package:cs2dart/src/orchestrator/diagnostic_renderer.dart';
import 'package:cs2dart/src/orchestrator/models/transpiler_result.dart';
import 'package:cs2dart/src/project_loader/models/diagnostic.dart';

// ---------------------------------------------------------------------------
// forAll helper (mirrors the pattern used in config_properties_test.dart)
// ---------------------------------------------------------------------------

void forAll<T>(
  T Function(Random) generator,
  void Function(T) property, {
  int iterations = 100,
}) {
  for (var i = 0; i < iterations; i++) {
    final random = Random(i);
    final value = generator(random);
    property(value);
  }
}

// ---------------------------------------------------------------------------
// Generators
// ---------------------------------------------------------------------------

const _codes = ['OR0001', 'PL0042', 'CFG0010', 'NR0003', 'VA0007'];
const _messages = [
  'Something went wrong',
  'File not found',
  'Invalid configuration',
  'Package resolution failed',
  'Dart analyze failed',
];
const _sources = [
  null,
  '/path/to/file.cs',
  'relative/path.csproj',
  'C:\\Windows\\path.sln',
];

DiagnosticSeverity _randomSeverity(Random r) =>
    DiagnosticSeverity.values[r.nextInt(DiagnosticSeverity.values.length)];

SourceLocation? _randomLocation(Random r) {
  if (r.nextBool()) return null;
  return SourceLocation(
    filePath: _sources[r.nextInt(_sources.length - 1) + 1]!,
    line: r.nextInt(1000) + 1,
    column: r.nextInt(200) + 1,
  );
}

String? _randomSource(Random r) => _sources[r.nextInt(_sources.length)];

Diagnostic _randomDiagnostic(Random r) {
  final source = _randomSource(r);
  final location = source != null ? _randomLocation(r) : null;
  return Diagnostic(
    severity: _randomSeverity(r),
    code: _codes[r.nextInt(_codes.length)],
    message: _messages[r.nextInt(_messages.length)],
    source: source,
    location: location,
  );
}

// ---------------------------------------------------------------------------
// Unit tests: DiagnosticRenderer.format
// ---------------------------------------------------------------------------

void main() {
  group('DiagnosticRenderer.format', () {
    test('formats error severity correctly', () {
      final d = Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'OR0001',
        message: 'Something failed',
      );
      expect(DiagnosticRenderer.format(d), equals('error OR0001: Something failed'));
    });

    test('formats warning severity correctly', () {
      final d = Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'OR0006',
        message: 'Name collision',
      );
      expect(DiagnosticRenderer.format(d), equals('warning OR0006: Name collision'));
    });

    test('formats info severity correctly', () {
      final d = Diagnostic(
        severity: DiagnosticSeverity.info,
        code: 'OR0005',
        message: 'Early exit triggered',
      );
      expect(DiagnosticRenderer.format(d), equals('info OR0005: Early exit triggered'));
    });

    test('omits bracket when source is null', () {
      final d = Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'PL0001',
        message: 'No source',
        source: null,
        location: null,
      );
      final result = DiagnosticRenderer.format(d);
      expect(result, equals('error PL0001: No source'));
      expect(result, isNot(contains('[')));
    });

    test('includes [source] bracket when source is present but location is null', () {
      final d = Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'PL0002',
        message: 'Source only',
        source: '/path/to/file.cs',
        location: null,
      );
      expect(
        DiagnosticRenderer.format(d),
        equals('warning PL0002: Source only [/path/to/file.cs]'),
      );
    });

    test('includes [source:line:column] bracket when both source and location are present', () {
      final d = Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CS0001',
        message: 'Syntax error',
        source: '/path/to/file.cs',
        location: SourceLocation(filePath: '/path/to/file.cs', line: 42, column: 7),
      );
      expect(
        DiagnosticRenderer.format(d),
        equals('error CS0001: Syntax error [/path/to/file.cs:42:7]'),
      );
    });

    test('uses line and column from location', () {
      final d = Diagnostic(
        severity: DiagnosticSeverity.info,
        code: 'NR0001',
        message: 'Package resolved',
        source: 'project.csproj',
        location: SourceLocation(filePath: 'project.csproj', line: 10, column: 1),
      );
      expect(
        DiagnosticRenderer.format(d),
        equals('info NR0001: Package resolved [project.csproj:10:1]'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Unit tests: DiagnosticRenderer.renderAll
  // -------------------------------------------------------------------------

  group('DiagnosticRenderer.renderAll', () {
    late List<String> stdoutLines;
    late List<String> stderrLines;

    setUp(() {
      stdoutLines = [];
      stderrLines = [];
    });

    /// Runs [body] with stdout/stderr captured into [stdoutLines]/[stderrLines].
    void runWithCapture(void Function() body) {
      IOOverrides.runZoned(
        body,
        stdout: () => _ListSink(stdoutLines),
        stderr: () => _ListSink(stderrLines),
      );
    }

    test('silent clean run: no output when verbose=false, success=true, no warnings', () {
      final result = TranspilerResult(
        success: true,
        packages: const [],
        diagnostics: const [],
      );
      runWithCapture(() {
        DiagnosticRenderer.renderAll(result, verbose: false);
      });
      expect(stdoutLines, isEmpty);
      expect(stderrLines, isEmpty);
    });

    test('success with verbose=true prints summary to stdout', () {
      final result = TranspilerResult(
        success: true,
        packages: const [],
        diagnostics: const [],
      );
      runWithCapture(() {
        DiagnosticRenderer.renderAll(
          result,
          verbose: true,
          outputDirectory: '/out',
        );
      });
      expect(stdoutLines, contains('Transpilation succeeded. 0 package(s) written to /out.'));
      expect(stderrLines, isEmpty);
    });

    test('success with warnings prints summary to stdout', () {
      final result = TranspilerResult(
        success: true,
        packages: const [],
        diagnostics: [
          Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'OR0006',
            message: 'Collision',
          ),
        ],
      );
      runWithCapture(() {
        DiagnosticRenderer.renderAll(
          result,
          verbose: false,
          outputDirectory: '/out',
        );
      });
      expect(stdoutLines, contains('Transpilation succeeded. 0 package(s) written to /out.'));
      expect(stderrLines, contains('warning OR0006: Collision'));
    });

    test('failure prints summary to stderr', () {
      final result = TranspilerResult(
        success: false,
        packages: const [],
        diagnostics: [
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'OR0001',
            message: 'Stage failed',
          ),
        ],
      );
      runWithCapture(() {
        DiagnosticRenderer.renderAll(result, verbose: false);
      });
      expect(stderrLines, contains('error OR0001: Stage failed'));
      expect(
        stderrLines,
        contains('Transpilation failed with 1 error(s) and 0 warning(s).'),
      );
      expect(stdoutLines, isEmpty);
    });

    test('error and warning diagnostics go to stderr', () {
      final result = TranspilerResult(
        success: false,
        packages: const [],
        diagnostics: [
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'PL0001',
            message: 'Error diag',
          ),
          Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'PL0002',
            message: 'Warning diag',
          ),
        ],
      );
      runWithCapture(() {
        DiagnosticRenderer.renderAll(result, verbose: false);
      });
      expect(stderrLines, contains('error PL0001: Error diag'));
      expect(stderrLines, contains('warning PL0002: Warning diag'));
      expect(stdoutLines, isEmpty);
    });

    test('info diagnostics suppressed when verbose=false', () {
      final result = TranspilerResult(
        success: true,
        packages: const [],
        diagnostics: [
          Diagnostic(
            severity: DiagnosticSeverity.info,
            code: 'OR0005',
            message: 'Early exit info',
          ),
        ],
      );
      runWithCapture(() {
        DiagnosticRenderer.renderAll(result, verbose: false);
      });
      expect(stdoutLines, isEmpty);
      expect(stderrLines, isEmpty);
    });

    test('info diagnostics go to stdout when verbose=true', () {
      final result = TranspilerResult(
        success: true,
        packages: const [],
        diagnostics: [
          Diagnostic(
            severity: DiagnosticSeverity.info,
            code: 'OR0005',
            message: 'Early exit info',
          ),
        ],
      );
      runWithCapture(() {
        DiagnosticRenderer.renderAll(
          result,
          verbose: true,
          outputDirectory: '/out',
        );
      });
      expect(stdoutLines, contains('info OR0005: Early exit info'));
    });

    test('failure counts errors and warnings correctly in summary', () {
      final result = TranspilerResult(
        success: false,
        packages: const [],
        diagnostics: [
          Diagnostic(severity: DiagnosticSeverity.error, code: 'E1', message: 'e1'),
          Diagnostic(severity: DiagnosticSeverity.error, code: 'E2', message: 'e2'),
          Diagnostic(severity: DiagnosticSeverity.warning, code: 'W1', message: 'w1'),
        ],
      );
      runWithCapture(() {
        DiagnosticRenderer.renderAll(result, verbose: false);
      });
      expect(
        stderrLines,
        contains('Transpilation failed with 2 error(s) and 1 warning(s).'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Property 12: Diagnostic Format Completeness
  // Feature: pipeline-orchestrator, Property 12: Diagnostic format completeness
  // For any Diagnostic with any combination of severity, code, message,
  // source, and location, DiagnosticRenderer.format() SHALL return a string
  // that contains the severity label, the code, and the message; and SHALL
  // contain the [source:line:column] bracket if and only if source is non-null.
  // Validates: Requirements 8.1, 8.2, 8.3
  // -------------------------------------------------------------------------
  test(
    'Property 12: Diagnostic format completeness — rendered string contains severity, code, message; bracket iff source present',
    () {
      forAll(_randomDiagnostic, (d) {
        final result = DiagnosticRenderer.format(d);

        final severityLabel = switch (d.severity) {
          DiagnosticSeverity.error => 'error',
          DiagnosticSeverity.warning => 'warning',
          DiagnosticSeverity.info => 'info',
        };
        expect(
          result,
          contains(severityLabel),
          reason: 'Formatted string missing severity label for $d',
        );

        expect(
          result,
          contains(d.code),
          reason: 'Formatted string missing code for $d',
        );

        expect(
          result,
          contains(d.message),
          reason: 'Formatted string missing message for $d',
        );

        if (d.source != null) {
          expect(
            result,
            contains('['),
            reason: 'Expected bracket when source is present for $d',
          );
          expect(
            result,
            contains(d.source!),
            reason: 'Expected source in bracket for $d',
          );
        } else {
          expect(
            result,
            isNot(contains('[')),
            reason: 'Expected no bracket when source is null for $d',
          );
        }
      });
    },
  );
}

// ---------------------------------------------------------------------------
// Helper: IOSink that captures writeln calls into a list
// ---------------------------------------------------------------------------

class _ListSink implements Stdout {
  final List<String> lines;

  _ListSink(this.lines);

  @override
  void writeln([Object? object = '']) {
    lines.add(object?.toString() ?? '');
  }

  @override
  void write(Object? object) {
    // Not used by DiagnosticRenderer (it only calls writeln)
  }

  // Stub out all other required members of Stdout/IOSink
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
