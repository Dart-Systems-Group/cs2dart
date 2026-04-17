import 'dart:io';

import 'package:test/test.dart';
import 'package:cs2dart/src/config/config_loader.dart';
import 'package:cs2dart/src/config/models/models.dart';

void main() {
  group('ConfigLoader', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('config_loader_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // -------------------------------------------------------------------------
    // Explicit --config path that does not exist → CFG0001 + service is null
    // -------------------------------------------------------------------------
    test('explicit --config path that does not exist emits CFG0001 and service is null',
        () async {
      final missingPath = '${tempDir.path}/nonexistent.yaml';
      final result = await ConfigLoader.load(
        entryPath: '${tempDir.path}/project.csproj',
        explicitConfigPath: missingPath,
      );

      expect(result.service, isNull);
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.first.code, 'CFG0001');
      expect(result.diagnostics.first.severity, DiagnosticSeverity.error);
    });

    // -------------------------------------------------------------------------
    // No transpiler.yaml found → default ConfigObject + CFG0020 Info
    // -------------------------------------------------------------------------
    test('no transpiler.yaml found returns default ConfigObject and CFG0020 Info',
        () async {
      // tempDir has no transpiler.yaml; use a file inside it as entry point
      final entryFile = File('${tempDir.path}/project.csproj')..createSync();

      final result = await ConfigLoader.load(entryPath: entryFile.path);

      expect(result.config, equals(ConfigObject.defaults));
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.first.code, 'CFG0020');
      expect(result.diagnostics.first.severity, DiagnosticSeverity.info);
      // service is non-null because CFG0020 is Info, not Error
      expect(result.service, isNotNull);
    });

    // -------------------------------------------------------------------------
    // transpiler.yaml found in parent directory is loaded correctly
    // -------------------------------------------------------------------------
    test('transpiler.yaml found in parent directory is loaded correctly', () async {
      // Write a valid transpiler.yaml in tempDir (the parent)
      final configFile = File('${tempDir.path}/transpiler.yaml');
      configFile.writeAsStringSync('linq_strategy: lower_to_loops\n');

      // Entry point is a file inside a subdirectory
      final subDir = Directory('${tempDir.path}/sub')..createSync();
      final entryFile = File('${subDir.path}/project.csproj')..createSync();

      final result = await ConfigLoader.load(entryPath: entryFile.path);

      expect(result.diagnostics.where((d) => d.severity == DiagnosticSeverity.error),
          isEmpty);
      expect(result.config, isNotNull);
      expect(result.config!.linqStrategy, LinqStrategy.lowerToLoops);
      expect(result.service, isNotNull);
    });

    // -------------------------------------------------------------------------
    // service is null when any Error diagnostic is present
    // -------------------------------------------------------------------------
    test('ConfigLoadResult.service is null when any Error diagnostic is present',
        () async {
      // Write a transpiler.yaml with an invalid enum value → CFG0004 Error
      final configFile = File('${tempDir.path}/transpiler.yaml');
      configFile.writeAsStringSync('linq_strategy: totally_invalid_value\n');

      final entryFile = File('${tempDir.path}/project.csproj')..createSync();

      final result = await ConfigLoader.load(entryPath: entryFile.path);

      expect(result.hasErrors, isTrue);
      expect(result.service, isNull);
    });

    // -------------------------------------------------------------------------
    // service is non-null when only Warning/Info diagnostics present
    // -------------------------------------------------------------------------
    test('ConfigLoadResult.service is non-null when only Warning/Info diagnostics present',
        () async {
      // Write a transpiler.yaml with an unrecognized key → CFG0010 Warning only
      final configFile = File('${tempDir.path}/transpiler.yaml');
      configFile.writeAsStringSync('unknown_key: some_value\n');

      final entryFile = File('${tempDir.path}/project.csproj')..createSync();

      final result = await ConfigLoader.load(entryPath: entryFile.path);

      expect(result.hasErrors, isFalse);
      expect(result.diagnostics.any((d) => d.severity == DiagnosticSeverity.warning),
          isTrue);
      expect(result.service, isNotNull);
    });

    // -------------------------------------------------------------------------
    // result.config equals the ConfigObject returned by IConfigService.config
    // -------------------------------------------------------------------------
    test('result.config equals the ConfigObject returned by IConfigService.config',
        () async {
      final configFile = File('${tempDir.path}/transpiler.yaml');
      configFile.writeAsStringSync('barrel_files: true\n');

      final entryFile = File('${tempDir.path}/project.csproj')..createSync();

      final result = await ConfigLoader.load(entryPath: entryFile.path);

      expect(result.service, isNotNull);
      expect(result.config, equals(result.service!.config));
    });
  });
}
