import 'package:test/test.dart';
import 'package:cs2dart/src/config/models/models.dart';

void main() {
  group('DiagnosticSeverity', () {
    test('has error, warning, and info values', () {
      expect(DiagnosticSeverity.values, containsAll([
        DiagnosticSeverity.error,
        DiagnosticSeverity.warning,
        DiagnosticSeverity.info,
      ]));
    });
  });

  group('LinqStrategy', () {
    test('preserveFunctional has correct YAML value', () {
      expect(LinqStrategy.preserveFunctional.yamlValue, 'preserve_functional');
    });

    test('lowerToLoops has correct YAML value', () {
      expect(LinqStrategy.lowerToLoops.yamlValue, 'lower_to_loops');
    });

    test('fromYaml returns preserveFunctional for "preserve_functional"', () {
      expect(LinqStrategy.fromYaml('preserve_functional'),
          LinqStrategy.preserveFunctional);
    });

    test('fromYaml returns lowerToLoops for "lower_to_loops"', () {
      expect(LinqStrategy.fromYaml('lower_to_loops'), LinqStrategy.lowerToLoops);
    });

    test('fromYaml returns null for unrecognized value', () {
      expect(LinqStrategy.fromYaml('unknown'), isNull);
      expect(LinqStrategy.fromYaml(''), isNull);
    });

    test('round-trip: yamlValue -> fromYaml returns original', () {
      for (final strategy in LinqStrategy.values) {
        expect(LinqStrategy.fromYaml(strategy.yamlValue), strategy);
      }
    });
  });

  group('EventStrategy', () {
    test('stream has correct YAML value', () {
      expect(EventStrategy.stream.yamlValue, 'stream');
    });

    test('fromYaml returns stream for "stream"', () {
      expect(EventStrategy.fromYaml('stream'), EventStrategy.stream);
    });

    test('fromYaml returns null for unrecognized value', () {
      expect(EventStrategy.fromYaml('unknown'), isNull);
      expect(EventStrategy.fromYaml('callback'), isNull);
    });

    test('round-trip: yamlValue -> fromYaml returns original', () {
      for (final strategy in EventStrategy.values) {
        expect(EventStrategy.fromYaml(strategy.yamlValue), strategy);
      }
    });
  });

  group('CaseStyle', () {
    test('pascalCase has correct YAML value', () {
      expect(CaseStyle.pascalCase.yamlValue, 'PascalCase');
    });

    test('camelCase has correct YAML value', () {
      expect(CaseStyle.camelCase.yamlValue, 'camelCase');
    });

    test('snakeCase has correct YAML value', () {
      expect(CaseStyle.snakeCase.yamlValue, 'snake_case');
    });

    test('screamingSnakeCase has correct YAML value', () {
      expect(CaseStyle.screamingSnakeCase.yamlValue, 'SCREAMING_SNAKE_CASE');
    });

    test('fromYaml returns correct values', () {
      expect(CaseStyle.fromYaml('PascalCase'), CaseStyle.pascalCase);
      expect(CaseStyle.fromYaml('camelCase'), CaseStyle.camelCase);
      expect(CaseStyle.fromYaml('snake_case'), CaseStyle.snakeCase);
      expect(CaseStyle.fromYaml('SCREAMING_SNAKE_CASE'),
          CaseStyle.screamingSnakeCase);
    });

    test('fromYaml returns null for unrecognized value', () {
      expect(CaseStyle.fromYaml('unknown'), isNull);
      expect(CaseStyle.fromYaml('pascal_case'), isNull); // wrong format
    });

    test('round-trip: yamlValue -> fromYaml returns original', () {
      for (final style in CaseStyle.values) {
        expect(CaseStyle.fromYaml(style.yamlValue), style);
      }
    });
  });

  group('SourceLocation', () {
    test('stores filePath, line, and column', () {
      const loc = SourceLocation(filePath: 'config.yaml', line: 5, column: 3);
      expect(loc.filePath, 'config.yaml');
      expect(loc.line, 5);
      expect(loc.column, 3);
    });

    test('value equality: equal when all fields match', () {
      const a = SourceLocation(filePath: 'a.yaml', line: 1, column: 2);
      const b = SourceLocation(filePath: 'a.yaml', line: 1, column: 2);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('value equality: not equal when filePath differs', () {
      const a = SourceLocation(filePath: 'a.yaml', line: 1, column: 2);
      const b = SourceLocation(filePath: 'b.yaml', line: 1, column: 2);
      expect(a, isNot(equals(b)));
    });

    test('value equality: not equal when line differs', () {
      const a = SourceLocation(filePath: 'a.yaml', line: 1, column: 2);
      const b = SourceLocation(filePath: 'a.yaml', line: 2, column: 2);
      expect(a, isNot(equals(b)));
    });

    test('value equality: not equal when column differs', () {
      const a = SourceLocation(filePath: 'a.yaml', line: 1, column: 2);
      const b = SourceLocation(filePath: 'a.yaml', line: 1, column: 3);
      expect(a, isNot(equals(b)));
    });

    test('identical instances are equal', () {
      const loc = SourceLocation(filePath: 'x.yaml', line: 0, column: 0);
      expect(loc, equals(loc));
    });
  });

  group('ConfigDiagnostic', () {
    test('stores all fields', () {
      const loc = SourceLocation(filePath: 'cfg.yaml', line: 10, column: 1);
      const diag = ConfigDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CFG0001',
        message: 'File not found',
        location: loc,
      );
      expect(diag.severity, DiagnosticSeverity.error);
      expect(diag.code, 'CFG0001');
      expect(diag.message, 'File not found');
      expect(diag.location, loc);
    });

    test('location is optional (defaults to null)', () {
      const diag = ConfigDiagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'CFG0010',
        message: 'Unknown key',
      );
      expect(diag.location, isNull);
    });

    test('value equality: equal when all fields match', () {
      const loc = SourceLocation(filePath: 'f.yaml', line: 1, column: 1);
      const a = ConfigDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CFG0002',
        message: 'Syntax error',
        location: loc,
      );
      const b = ConfigDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CFG0002',
        message: 'Syntax error',
        location: loc,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('value equality: not equal when severity differs', () {
      const a = ConfigDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CFG0002',
        message: 'msg',
      );
      const b = ConfigDiagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'CFG0002',
        message: 'msg',
      );
      expect(a, isNot(equals(b)));
    });

    test('value equality: not equal when code differs', () {
      const a = ConfigDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CFG0001',
        message: 'msg',
      );
      const b = ConfigDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CFG0002',
        message: 'msg',
      );
      expect(a, isNot(equals(b)));
    });

    test('value equality: not equal when message differs', () {
      const a = ConfigDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CFG0001',
        message: 'msg A',
      );
      const b = ConfigDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CFG0001',
        message: 'msg B',
      );
      expect(a, isNot(equals(b)));
    });

    test('value equality: not equal when location differs', () {
      const a = ConfigDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CFG0001',
        message: 'msg',
        location: SourceLocation(filePath: 'a.yaml', line: 1, column: 1),
      );
      const b = ConfigDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CFG0001',
        message: 'msg',
        location: SourceLocation(filePath: 'b.yaml', line: 1, column: 1),
      );
      expect(a, isNot(equals(b)));
    });

    test('value equality: null location vs non-null location are not equal', () {
      const a = ConfigDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CFG0001',
        message: 'msg',
      );
      const b = ConfigDiagnostic(
        severity: DiagnosticSeverity.error,
        code: 'CFG0001',
        message: 'msg',
        location: SourceLocation(filePath: 'a.yaml', line: 1, column: 1),
      );
      expect(a, isNot(equals(b)));
    });
  });
}
