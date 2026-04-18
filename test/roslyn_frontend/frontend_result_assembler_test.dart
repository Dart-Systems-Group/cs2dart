import 'package:test/test.dart';
import 'package:cs2dart/src/config/models/config_object.dart';
import 'package:cs2dart/src/config/models/source_location.dart';
import 'package:cs2dart/src/project_loader/models/dependency_graph.dart';
import 'package:cs2dart/src/project_loader/models/load_result.dart';
import 'package:cs2dart/src/roslyn_frontend/frontend_result_assembler.dart';
import 'package:cs2dart/src/roslyn_frontend/models/frontend_result.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Minimal [LoadResult] with the given diagnostics.
LoadResult _loadResult(List<Diagnostic> diagnostics) => LoadResult(
      projects: const [],
      dependencyGraph: DependencyGraph.empty,
      diagnostics: diagnostics,
      success: true,
      config: ConfigObject.defaults,
    );

/// Minimal [FrontendResult] with the given diagnostics and no units.
FrontendResult _workerResult(List<Diagnostic> diagnostics) => FrontendResult(
      units: const [],
      diagnostics: diagnostics,
      success: true,
    );

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final assembler = const FrontendResultAssembler();

  // -------------------------------------------------------------------------
  // Requirement 1.4 — PL diagnostics are prepended before RF diagnostics
  // -------------------------------------------------------------------------
  group('PL diagnostics are prepended before worker diagnostics', () {
    test('PL diagnostic appears before RF diagnostic in merged list', () {
      final plDiag = _diag(code: 'PL0001', message: 'project loader error');
      final rfDiag = _diag(code: 'RF0001', message: 'frontend warning');

      final result = assembler.assemble(
        _workerResult([rfDiag]),
        _loadResult([plDiag]),
      );

      expect(result.diagnostics, hasLength(2));
      expect(result.diagnostics[0].code, 'PL0001');
      expect(result.diagnostics[1].code, 'RF0001');
    });

    test('multiple PL diagnostics all appear before worker diagnostics', () {
      final pl1 = _diag(code: 'PL0001');
      final pl2 = _diag(code: 'PL0002');
      final rf1 = _diag(code: 'RF0001');
      final rf2 = _diag(code: 'RF0002');

      final result = assembler.assemble(
        _workerResult([rf1, rf2]),
        _loadResult([pl1, pl2]),
      );

      expect(result.diagnostics.map((d) => d.code).toList(),
          ['PL0001', 'PL0002', 'RF0001', 'RF0002']);
    });

    test('non-PL diagnostics in loadResult are not included', () {
      // NR-prefixed diagnostics from loadResult should NOT be propagated
      // (only PL-prefixed ones are propagated per the spec).
      final nrDiag = _diag(code: 'NR0001', message: 'nuget warning');
      final rfDiag = _diag(code: 'RF0001');

      final result = assembler.assemble(
        _workerResult([rfDiag]),
        _loadResult([nrDiag]),
      );

      // NR diagnostic is not PL-prefixed, so it should not appear.
      expect(result.diagnostics.any((d) => d.code == 'NR0001'), isFalse);
      expect(result.diagnostics.any((d) => d.code == 'RF0001'), isTrue);
    });

    test('empty loadResult diagnostics — only worker diagnostics appear', () {
      final rfDiag = _diag(code: 'RF0003');

      final result = assembler.assemble(
        _workerResult([rfDiag]),
        _loadResult([]),
      );

      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics[0].code, 'RF0003');
    });

    test('empty worker diagnostics — only PL diagnostics appear', () {
      final plDiag = _diag(code: 'PL0005');

      final result = assembler.assemble(
        _workerResult([]),
        _loadResult([plDiag]),
      );

      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics[0].code, 'PL0005');
    });

    test('units from workerResult are preserved unchanged', () {
      final result = assembler.assemble(
        _workerResult([]),
        _loadResult([]),
      );

      expect(result.units, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Requirement 1.5 — success flag
  // -------------------------------------------------------------------------
  group('success flag', () {
    test('success = false when an Error diagnostic is present in merged list',
        () {
      final errorDiag = _diag(
        code: 'RF0005',
        severity: DiagnosticSeverity.error,
      );

      final result = assembler.assemble(
        _workerResult([errorDiag]),
        _loadResult([]),
      );

      expect(result.success, isFalse);
    });

    test('success = false when a PL Error diagnostic is present', () {
      final plError = _diag(
        code: 'PL0001',
        severity: DiagnosticSeverity.error,
      );

      final result = assembler.assemble(
        _workerResult([]),
        _loadResult([plError]),
      );

      expect(result.success, isFalse);
    });

    test('success = true when only Warning diagnostics are present', () {
      final warn = _diag(
        code: 'RF0001',
        severity: DiagnosticSeverity.warning,
      );

      final result = assembler.assemble(
        _workerResult([warn]),
        _loadResult([]),
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
        _loadResult([]),
      );

      expect(result.success, isTrue);
    });

    test('success = true when no diagnostics are present', () {
      final result = assembler.assemble(
        _workerResult([]),
        _loadResult([]),
      );

      expect(result.success, isTrue);
    });

    test('success = false when mixed severities include at least one Error', () {
      final warn = _diag(code: 'RF0001', severity: DiagnosticSeverity.warning);
      final error = _diag(code: 'RF0005', severity: DiagnosticSeverity.error);
      final info = _diag(code: 'RF0009', severity: DiagnosticSeverity.info);

      final result = assembler.assemble(
        _workerResult([warn, error, info]),
        _loadResult([]),
      );

      expect(result.success, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Requirements 12.3, 12.4 — deduplication and RF0012
  // -------------------------------------------------------------------------
  group('deduplication and RF0012', () {
    test('duplicate diagnostic (same code, source, location) is suppressed', () {
      const loc = SourceLocation(filePath: 'Foo.cs', line: 10, column: 5);
      final diag1 = _diag(code: 'RF0001', source: 'Foo.cs', location: loc);
      final diag2 = _diag(code: 'RF0001', source: 'Foo.cs', location: loc);

      final result = assembler.assemble(
        _workerResult([diag1, diag2]),
        _loadResult([]),
      );

      // Only one RF0001 should remain; one RF0012 should be emitted.
      final rf0001s = result.diagnostics.where((d) => d.code == 'RF0001');
      final rf0012s = result.diagnostics.where((d) => d.code == 'RF0012');
      expect(rf0001s, hasLength(1));
      expect(rf0012s, hasLength(1));
    });

    test('RF0012 Warning is emitted for each suppressed duplicate', () {
      const loc = SourceLocation(filePath: 'Bar.cs', line: 3, column: 1);
      final diag = _diag(code: 'RF0002', source: 'Bar.cs', location: loc);

      // Three copies of the same diagnostic.
      final result = assembler.assemble(
        _workerResult([diag, diag, diag]),
        _loadResult([]),
      );

      final rf0012s = result.diagnostics.where((d) => d.code == 'RF0012');
      // Two duplicates suppressed → two RF0012 warnings.
      expect(rf0012s, hasLength(2));
    });

    test('RF0012 has Warning severity', () {
      const loc = SourceLocation(filePath: 'X.cs', line: 1, column: 1);
      final diag = _diag(code: 'RF0001', source: 'X.cs', location: loc);

      final result = assembler.assemble(
        _workerResult([diag, diag]),
        _loadResult([]),
      );

      final rf0012 =
          result.diagnostics.firstWhere((d) => d.code == 'RF0012');
      expect(rf0012.severity, DiagnosticSeverity.warning);
    });

    test('RF0012 message includes the suppressed diagnostic code', () {
      const loc = SourceLocation(filePath: 'X.cs', line: 5, column: 2);
      final diag = _diag(code: 'RF0007', source: 'X.cs', location: loc);

      final result = assembler.assemble(
        _workerResult([diag, diag]),
        _loadResult([]),
      );

      final rf0012 =
          result.diagnostics.firstWhere((d) => d.code == 'RF0012');
      expect(rf0012.message, contains('RF0007'));
    });

    test('RF0012 message includes the source location of the suppressed diagnostic',
        () {
      const loc = SourceLocation(filePath: 'Y.cs', line: 20, column: 8);
      final diag = _diag(code: 'RF0003', source: 'Y.cs', location: loc);

      final result = assembler.assemble(
        _workerResult([diag, diag]),
        _loadResult([]),
      );

      final rf0012 =
          result.diagnostics.firstWhere((d) => d.code == 'RF0012');
      expect(rf0012.message, contains('20'));
      expect(rf0012.message, contains('8'));
    });

    test('diagnostics with different codes are not considered duplicates', () {
      const loc = SourceLocation(filePath: 'A.cs', line: 1, column: 1);
      final diag1 = _diag(code: 'RF0001', source: 'A.cs', location: loc);
      final diag2 = _diag(code: 'RF0002', source: 'A.cs', location: loc);

      final result = assembler.assemble(
        _workerResult([diag1, diag2]),
        _loadResult([]),
      );

      expect(result.diagnostics.where((d) => d.code == 'RF0012'), isEmpty);
      expect(result.diagnostics, hasLength(2));
    });

    test('diagnostics with different sources are not considered duplicates', () {
      const loc = SourceLocation(filePath: 'A.cs', line: 1, column: 1);
      final diag1 = _diag(code: 'RF0001', source: 'A.cs', location: loc);
      final diag2 = _diag(code: 'RF0001', source: 'B.cs', location: loc);

      final result = assembler.assemble(
        _workerResult([diag1, diag2]),
        _loadResult([]),
      );

      expect(result.diagnostics.where((d) => d.code == 'RF0012'), isEmpty);
      expect(result.diagnostics, hasLength(2));
    });

    test('diagnostics with different locations are not considered duplicates', () {
      const loc1 = SourceLocation(filePath: 'A.cs', line: 1, column: 1);
      const loc2 = SourceLocation(filePath: 'A.cs', line: 2, column: 1);
      final diag1 = _diag(code: 'RF0001', source: 'A.cs', location: loc1);
      final diag2 = _diag(code: 'RF0001', source: 'A.cs', location: loc2);

      final result = assembler.assemble(
        _workerResult([diag1, diag2]),
        _loadResult([]),
      );

      expect(result.diagnostics.where((d) => d.code == 'RF0012'), isEmpty);
      expect(result.diagnostics, hasLength(2));
    });

    test('duplicate across PL and worker diagnostics is suppressed', () {
      // A PL diagnostic and a worker diagnostic with the same key.
      const loc = SourceLocation(filePath: 'Z.cs', line: 1, column: 1);
      final plDiag = _diag(code: 'PL0001', source: 'Z.cs', location: loc);
      final workerDiag = _diag(code: 'PL0001', source: 'Z.cs', location: loc);

      final result = assembler.assemble(
        _workerResult([workerDiag]),
        _loadResult([plDiag]),
      );

      final pl0001s = result.diagnostics.where((d) => d.code == 'PL0001');
      final rf0012s = result.diagnostics.where((d) => d.code == 'RF0012');
      expect(pl0001s, hasLength(1));
      expect(rf0012s, hasLength(1));
    });

    test('no duplicates — no RF0012 emitted', () {
      final diag1 = _diag(code: 'RF0001', source: 'A.cs');
      final diag2 = _diag(code: 'RF0002', source: 'B.cs');

      final result = assembler.assemble(
        _workerResult([diag1, diag2]),
        _loadResult([]),
      );

      expect(result.diagnostics.where((d) => d.code == 'RF0012'), isEmpty);
    });

    test('RF0012 does not affect success when no Error diagnostics present', () {
      const loc = SourceLocation(filePath: 'X.cs', line: 1, column: 1);
      final diag = _diag(
        code: 'RF0001',
        severity: DiagnosticSeverity.warning,
        source: 'X.cs',
        location: loc,
      );

      final result = assembler.assemble(
        _workerResult([diag, diag]),
        _loadResult([]),
      );

      // RF0012 is a Warning, so success should still be true.
      expect(result.success, isTrue);
    });
  });
}
