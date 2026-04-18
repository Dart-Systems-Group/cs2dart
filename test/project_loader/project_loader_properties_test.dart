// Property-based tests for ProjectLoader
// Tests Properties 1, 3, 8, 9, 10, 11, 12, 13 from the design document.
// Since propcheck is not available, these use parameterized/example-based
// tests that verify universal properties hold across multiple generated inputs.

import 'dart:io';

import 'package:cs2dart/src/config/config_service.dart';
import 'package:cs2dart/src/config/models/config_object.dart';
import 'package:cs2dart/src/project_loader/models/diagnostic.dart';
import 'package:cs2dart/src/project_loader/models/nuget_resolve_result.dart';
import 'package:cs2dart/src/project_loader/models/package_reference_entry.dart';
import 'package:cs2dart/src/project_loader/models/package_reference_spec.dart';
import 'package:cs2dart/src/project_loader/models/project_file_data.dart';
import 'package:cs2dart/src/project_loader/models/roslyn_interop.dart';
import 'package:cs2dart/src/project_loader/project_loader_impl.dart';
import 'package:test/test.dart';

import 'fakes/fake_compilation_builder.dart';
import 'fakes/fake_input_parser.dart';
import 'fakes/fake_nuget_handler.dart';
import 'fakes/fake_sdk_resolver.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [ProjectLoader] with optional fake sub-components.
ProjectLoader makeLoader({
  FakeInputParser? inputParser,
  FakeSdkResolver? sdkResolver,
  FakeNuGetHandler? nugetHandler,
  FakeCompilationBuilder? compilationBuilder,
}) {
  return ProjectLoader(
    inputParser: inputParser ?? FakeInputParser(),
    sdkResolver: sdkResolver ?? const FakeSdkResolver(),
    nugetHandler: nugetHandler ?? FakeNuGetHandler(),
    compilationBuilder: const FakeCompilationBuilder(),
  );
}

/// A minimal [IConfigService] backed by a [ConfigObject].
///
/// Delegates all accessors to [ConfigService] to avoid duplicating the
/// interface implementation.
ConfigService makeConfigService([ConfigObject config = ConfigObject.defaults]) {
  return ConfigService(config);
}

/// Creates a temporary `.csproj` file and registers it with [parser].
/// Returns the absolute path of the created file.
String registerTempCsproj(
  Directory dir,
  FakeInputParser parser,
  ProjectFileData data,
) {
  final file = File('${dir.path}/${data.absolutePath.split('/').last}');
  file.writeAsStringSync('<Project/>'); // content irrelevant — parser is faked
  parser.csprojFixtures[file.absolute.path] = ProjectFileData(
    absolutePath: file.absolute.path,
    assemblyName: data.assemblyName,
    targetFramework: data.targetFramework,
    outputType: data.outputType,
    langVersion: data.langVersion,
    nullableEnabled: data.nullableEnabled,
    sourceGlobs: data.sourceGlobs,
    projectReferencePaths: data.projectReferencePaths,
    packageReferences: data.packageReferences,
  );
  return file.absolute.path;
}

/// Generates a list of varied [ProjectFileData] fixtures for property testing.
List<ProjectFileData> generateProjectFixtures(String basePath) {
  return [
    ProjectFileData(
      absolutePath: '$basePath/Alpha.csproj',
      assemblyName: 'Alpha',
      targetFramework: 'net8.0',
    ),
    ProjectFileData(
      absolutePath: '$basePath/Beta.csproj',
      assemblyName: 'Beta',
      targetFramework: 'net7.0',
      outputType: 'Exe',
      langVersion: '11.0',
    ),
    ProjectFileData(
      absolutePath: '$basePath/Gamma.csproj',
      assemblyName: 'Gamma',
      targetFramework: 'net6.0',
      nullableEnabled: true,
    ),
    ProjectFileData(
      absolutePath: '$basePath/Delta.csproj',
      // assemblyName null → derived from file name
      targetFramework: 'net8.0',
      outputType: 'WinExe',
    ),
    ProjectFileData(
      absolutePath: '$basePath/Epsilon.csproj',
      assemblyName: 'Epsilon',
      targetFramework: 'net8.0',
      langVersion: 'Latest',
      nullableEnabled: true,
    ),
    ProjectFileData(
      absolutePath: '$basePath/Zeta.csproj',
      assemblyName: 'Zeta',
      targetFramework: 'net9.0',
    ),
    ProjectFileData(
      absolutePath: '$basePath/Eta.csproj',
      assemblyName: 'Eta',
      // targetFramework null → defaults to net8.0 with PL0012 warning
    ),
    ProjectFileData(
      absolutePath: '$basePath/Theta.csproj',
      assemblyName: 'Theta',
      targetFramework: 'net8.0',
      outputType: 'Library',
      langVersion: '12.0',
      nullableEnabled: false,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Property 1: Single-project load produces exactly one ProjectEntry
// Validates: Requirements 1.1
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pl_props_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('Property 1: Single-project load produces exactly one ProjectEntry', () {
    // Feature: cs-project-loader, Property 1
    test('holds for multiple varied .csproj fixtures', () async {
      final fixtures = generateProjectFixtures(tempDir.path);

      for (final fixture in fixtures) {
        final parser = FakeInputParser();
        final path = registerTempCsproj(tempDir, parser, fixture);
        final loader = makeLoader(inputParser: parser);
        final config = makeConfigService();

        final result = await loader.load(path, config);

        expect(
          result.projects,
          hasLength(1),
          reason: 'Expected exactly one ProjectEntry for ${fixture.assemblyName}',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Property 3: Invalid input produces empty Projects and Error diagnostic
  // Validates: Requirements 1.3, 1.4
  // ---------------------------------------------------------------------------

  group('Property 3: Invalid input produces empty Projects and Error diagnostic', () {
    // Feature: cs-project-loader, Property 3
    test('holds for non-existent file paths', () async {
      final nonExistentPaths = [
        '${tempDir.path}/does_not_exist.csproj',
        '${tempDir.path}/missing/nested/file.csproj',
        '/tmp/absolutely_not_here_12345.csproj',
        '${tempDir.path}/ghost.csproj',
        '${tempDir.path}/phantom.csproj',
      ];

      final loader = makeLoader();
      final config = makeConfigService();

      for (final path in nonExistentPaths) {
        final result = await loader.load(path, config);

        expect(result.projects, isEmpty,
            reason: 'Expected empty projects for non-existent path: $path');
        expect(result.success, isFalse,
            reason: 'Expected success=false for non-existent path: $path');
        expect(
          result.diagnostics.any((d) => d.severity == DiagnosticSeverity.error),
          isTrue,
          reason: 'Expected at least one Error diagnostic for non-existent path: $path',
        );
      }
    });

    test('holds for files with unsupported extensions', () async {
      final unsupportedExtensions = ['.txt', '.xml', '.json', '.yaml', '.cs'];

      final loader = makeLoader();
      final config = makeConfigService();

      for (final ext in unsupportedExtensions) {
        final file = File('${tempDir.path}/project$ext');
        file.writeAsStringSync('content');
        final path = file.absolute.path;

        final result = await loader.load(path, config);

        expect(result.projects, isEmpty,
            reason: 'Expected empty projects for unsupported extension: $ext');
        expect(result.success, isFalse,
            reason: 'Expected success=false for unsupported extension: $ext');
        expect(
          result.diagnostics.any((d) => d.severity == DiagnosticSeverity.error),
          isTrue,
          reason: 'Expected at least one Error diagnostic for unsupported extension: $ext',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Property 8: Success iff no Error-severity diagnostic
  // Validates: Requirements 7.3
  // ---------------------------------------------------------------------------

  group('Property 8: Success iff no Error-severity diagnostic', () {
    // Feature: cs-project-loader, Property 8
    test('holds for successful loads (no errors)', () async {
      final fixtures = generateProjectFixtures(tempDir.path);

      for (final fixture in fixtures) {
        final parser = FakeInputParser();
        final path = registerTempCsproj(tempDir, parser, fixture);
        final loader = makeLoader(inputParser: parser);
        final config = makeConfigService();

        final result = await loader.load(path, config);

        final hasError =
            result.diagnostics.any((d) => d.severity == DiagnosticSeverity.error);
        expect(
          result.success,
          equals(!hasError),
          reason: 'success must be true iff no Error diagnostic for ${fixture.assemblyName}',
        );
      }
    });

    test('holds for failed loads (error diagnostics present)', () async {
      final loader = makeLoader();
      final config = makeConfigService();

      // Non-existent file → PL0001 Error → success must be false
      final result = await loader.load('${tempDir.path}/no_such.csproj', config);

      final hasError =
          result.diagnostics.any((d) => d.severity == DiagnosticSeverity.error);
      expect(result.success, equals(!hasError));
      expect(result.success, isFalse);
    });

    test('holds when NuGet handler emits an error diagnostic', () async {
      final parser = FakeInputParser();
      final fixture = ProjectFileData(
        absolutePath: '${tempDir.path}/WithNugetError.csproj',
        assemblyName: 'WithNugetError',
        targetFramework: 'net8.0',
      );
      final path = registerTempCsproj(tempDir, parser, fixture);

      final nugetWithError = FakeNuGetHandler(
        result: NuGetResolveResult(
          assemblyPaths: const [],
          packageReferences: const [],
          diagnostics: [
            const Diagnostic(
              severity: DiagnosticSeverity.error,
              code: 'NR0001',
              message: 'Package not found',
            ),
          ],
        ),
      );

      final loader = makeLoader(inputParser: parser, nugetHandler: nugetWithError);
      final config = makeConfigService();

      final result = await loader.load(path, config);

      final hasError =
          result.diagnostics.any((d) => d.severity == DiagnosticSeverity.error);
      expect(result.success, equals(!hasError));
    });
  });

  // ---------------------------------------------------------------------------
  // Property 9: All diagnostics conform to the pipeline-wide schema
  // Validates: Requirements 7.1
  // ---------------------------------------------------------------------------

  group('Property 9: All diagnostics conform to the pipeline-wide schema', () {
    // Feature: cs-project-loader, Property 9
    final codePattern = RegExp(r'^[A-Z]+[0-9]{4}$');

    test('holds for successful loads', () async {
      final fixtures = generateProjectFixtures(tempDir.path);

      for (final fixture in fixtures) {
        final parser = FakeInputParser();
        final path = registerTempCsproj(tempDir, parser, fixture);
        final loader = makeLoader(inputParser: parser);
        final config = makeConfigService();

        final result = await loader.load(path, config);

        for (final d in result.diagnostics) {
          expect(d.severity, isNotNull,
              reason: 'Diagnostic severity must be non-null');
          expect(d.code, isNotNull,
              reason: 'Diagnostic code must be non-null');
          expect(d.message, isNotNull,
              reason: 'Diagnostic message must be non-null');
          expect(codePattern.hasMatch(d.code), isTrue,
              reason: 'Diagnostic code "${d.code}" must match [A-Z]+[0-9]{4}');
        }
      }
    });

    test('holds for error results (non-existent file)', () async {
      final loader = makeLoader();
      final config = makeConfigService();

      final result = await loader.load('${tempDir.path}/missing.csproj', config);

      for (final d in result.diagnostics) {
        expect(d.severity, isNotNull);
        expect(d.code, isNotNull);
        expect(d.message, isNotNull);
        expect(codePattern.hasMatch(d.code), isTrue,
            reason: 'Diagnostic code "${d.code}" must match [A-Z]+[0-9]{4}');
      }
    });

    test('holds for error results (unsupported extension)', () async {
      final file = File('${tempDir.path}/project.txt');
      file.writeAsStringSync('x');
      final loader = makeLoader();
      final config = makeConfigService();

      final result = await loader.load(file.absolute.path, config);

      for (final d in result.diagnostics) {
        expect(d.severity, isNotNull);
        expect(d.code, isNotNull);
        expect(d.message, isNotNull);
        expect(codePattern.hasMatch(d.code), isTrue,
            reason: 'Diagnostic code "${d.code}" must match [A-Z]+[0-9]{4}');
      }
    });

    test('holds when NuGet diagnostics are included', () async {
      final parser = FakeInputParser();
      final fixture = ProjectFileData(
        absolutePath: '${tempDir.path}/NugetSchema.csproj',
        assemblyName: 'NugetSchema',
        targetFramework: 'net8.0',
      );
      final path = registerTempCsproj(tempDir, parser, fixture);

      final nugetWithDiag = FakeNuGetHandler(
        result: NuGetResolveResult(
          assemblyPaths: const [],
          packageReferences: const [],
          diagnostics: [
            const Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'NR0042',
              message: 'Some NuGet warning',
            ),
          ],
        ),
      );

      final loader = makeLoader(inputParser: parser, nugetHandler: nugetWithDiag);
      final config = makeConfigService();

      final result = await loader.load(path, config);

      for (final d in result.diagnostics) {
        expect(codePattern.hasMatch(d.code), isTrue,
            reason: 'Diagnostic code "${d.code}" must match [A-Z]+[0-9]{4}');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Property 10: PL diagnostic codes are in range PL0001–PL9999
  // Validates: Requirements 7.4
  // ---------------------------------------------------------------------------

  group('Property 10: PL diagnostic codes are in range PL0001–PL9999', () {
    // Feature: cs-project-loader, Property 10
    final plCodePattern = RegExp(r'^PL(\d{4})$');

    void verifyPlCodes(List<Diagnostic> diagnostics) {
      for (final d in diagnostics) {
        final match = plCodePattern.firstMatch(d.code);
        if (match != null) {
          final numeric = int.parse(match.group(1)!);
          expect(numeric, greaterThanOrEqualTo(1),
              reason: 'PL code "${d.code}" numeric suffix must be >= 1');
          expect(numeric, lessThanOrEqualTo(9999),
              reason: 'PL code "${d.code}" numeric suffix must be <= 9999');
        }
      }
    }

    test('holds for non-existent file (PL0001)', () async {
      final loader = makeLoader();
      final config = makeConfigService();

      final result = await loader.load('${tempDir.path}/nope.csproj', config);
      verifyPlCodes(result.diagnostics);
    });

    test('holds for unsupported extension (PL0002)', () async {
      final file = File('${tempDir.path}/bad.json');
      file.writeAsStringSync('{}');
      final loader = makeLoader();
      final config = makeConfigService();

      final result = await loader.load(file.absolute.path, config);
      verifyPlCodes(result.diagnostics);
    });

    test('holds for successful loads with PL0012 warning (missing target framework)', () async {
      final parser = FakeInputParser();
      final fixture = ProjectFileData(
        absolutePath: '${tempDir.path}/NoFramework.csproj',
        assemblyName: 'NoFramework',
        // targetFramework null → PL0012 warning
      );
      final path = registerTempCsproj(tempDir, parser, fixture);
      final loader = makeLoader(inputParser: parser);
      final config = makeConfigService();

      final result = await loader.load(path, config);
      verifyPlCodes(result.diagnostics);

      // Verify PL0012 is present
      expect(
        result.diagnostics.any((d) => d.code == 'PL0012'),
        isTrue,
        reason: 'Expected PL0012 warning when targetFramework is null',
      );
    });

    test('holds for multiple varied fixtures', () async {
      final fixtures = generateProjectFixtures(tempDir.path);

      for (final fixture in fixtures) {
        final parser = FakeInputParser();
        final path = registerTempCsproj(tempDir, parser, fixture);
        final loader = makeLoader(inputParser: parser);
        final config = makeConfigService();

        final result = await loader.load(path, config);
        verifyPlCodes(result.diagnostics);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Property 11: Determinism — identical inputs produce identical outputs
  // Validates: Requirements 8.1, 8.4
  // ---------------------------------------------------------------------------

  group('Property 11: Determinism — identical inputs produce identical outputs', () {
    // Feature: cs-project-loader, Property 11
    test('holds for successful loads across multiple fixtures', () async {
      final fixtures = generateProjectFixtures(tempDir.path);

      for (final fixture in fixtures) {
        final parser = FakeInputParser();
        final path = registerTempCsproj(tempDir, parser, fixture);
        final loader = makeLoader(inputParser: parser);
        final config = makeConfigService();

        final result1 = await loader.load(path, config);
        final result2 = await loader.load(path, config);

        expect(result1.success, equals(result2.success),
            reason: 'success must be identical on repeated calls for ${fixture.assemblyName}');
        expect(result1.diagnostics.length, equals(result2.diagnostics.length),
            reason: 'diagnostics.length must be identical on repeated calls');
        expect(
          result1.projects.map((p) => p.projectName).toSet(),
          equals(result2.projects.map((p) => p.projectName).toSet()),
          reason: 'set of projectName values must be identical on repeated calls',
        );
      }
    });

    test('holds for error results (non-existent file)', () async {
      final loader = makeLoader();
      final config = makeConfigService();
      final path = '${tempDir.path}/determinism_missing.csproj';

      final result1 = await loader.load(path, config);
      final result2 = await loader.load(path, config);

      expect(result1.success, equals(result2.success));
      expect(result1.diagnostics.length, equals(result2.diagnostics.length));
      expect(
        result1.projects.map((p) => p.projectName).toSet(),
        equals(result2.projects.map((p) => p.projectName).toSet()),
      );
    });

    test('holds for error results (unsupported extension)', () async {
      final file = File('${tempDir.path}/det_bad.xml');
      file.writeAsStringSync('<x/>');
      final loader = makeLoader();
      final config = makeConfigService();

      final result1 = await loader.load(file.absolute.path, config);
      final result2 = await loader.load(file.absolute.path, config);

      expect(result1.success, equals(result2.success));
      expect(result1.diagnostics.length, equals(result2.diagnostics.length));
    });
  });

  // ---------------------------------------------------------------------------
  // Property 12: LoadResult.config is value-equal to IConfigService.config
  // Validates: Requirements 9.6
  // ---------------------------------------------------------------------------

  group('Property 12: LoadResult.config is value-equal to IConfigService.config', () {
    // Feature: cs-project-loader, Property 12
    test('holds for default ConfigObject', () async {
      final fixtures = generateProjectFixtures(tempDir.path);

      for (final fixture in fixtures) {
        final parser = FakeInputParser();
        final path = registerTempCsproj(tempDir, parser, fixture);
        final loader = makeLoader(inputParser: parser);
        final config = makeConfigService();

        final result = await loader.load(path, config);

        expect(result.config, equals(config.config),
            reason: 'LoadResult.config must equal IConfigService.config');
      }
    });

    test('holds for custom ConfigObject with sdkPath', () async {
      const customConfig = ConfigObject(sdkPath: '/custom/sdk/path');
      final parser = FakeInputParser();
      final fixture = ProjectFileData(
        absolutePath: '${tempDir.path}/CustomConfig.csproj',
        assemblyName: 'CustomConfig',
        targetFramework: 'net8.0',
      );
      final path = registerTempCsproj(tempDir, parser, fixture);
      final loader = makeLoader(inputParser: parser);
      final config = makeConfigService(customConfig);

      final result = await loader.load(path, config);

      expect(result.config, equals(customConfig));
    });

    test('holds for error results (config is still stored)', () async {
      const customConfig = ConfigObject(barrelFiles: true);
      final loader = makeLoader();
      final config = makeConfigService(customConfig);

      final result = await loader.load('${tempDir.path}/no_file.csproj', config);

      expect(result.config, equals(customConfig));
    });

    test('holds for multiple different ConfigObject instances', () async {
      final configs = [
        const ConfigObject(),
        const ConfigObject(barrelFiles: true),
        const ConfigObject(rootNamespace: 'MyApp'),
        const ConfigObject(sdkPath: '/opt/dotnet'),
        const ConfigObject(autoResolveConflicts: true),
      ];

      for (final configObj in configs) {
        final parser = FakeInputParser();
        final fixture = ProjectFileData(
          absolutePath: '${tempDir.path}/Cfg_${configs.indexOf(configObj)}.csproj',
          assemblyName: 'CfgProject',
          targetFramework: 'net8.0',
        );
        final path = registerTempCsproj(tempDir, parser, fixture);
        final loader = makeLoader(inputParser: parser);
        final config = makeConfigService(configObj);

        final result = await loader.load(path, config);

        expect(result.config, equals(configObj),
            reason: 'LoadResult.config must equal the provided ConfigObject');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Property 13: PackageReferences entries have Tier and DartMapping populated
  // Validates: Requirements 3.1
  // ---------------------------------------------------------------------------

  group('Property 13: PackageReferences entries have Tier and DartMapping populated', () {
    // Feature: cs-project-loader, Property 13
    test('holds: tier 1 has non-null dartMapping, tier 2/3 have null dartMapping', () async {
      final packageSets = [
        // Tier 1 only
        [
          PackageReferenceEntry(
            packageName: 'Newtonsoft.Json',
            version: '13.0.3',
            tier: 1,
            dartMapping: const DartMapping(
              dartPackageName: 'json_serializable',
              dartImportPath: 'package:json_serializable/json_serializable.dart',
            ),
          ),
        ],
        // Tier 2 only
        [
          const PackageReferenceEntry(
            packageName: 'SomeLib',
            version: '1.0.0',
            tier: 2,
          ),
        ],
        // Tier 3 only
        [
          const PackageReferenceEntry(
            packageName: 'UnknownLib',
            version: '2.0.0',
            tier: 3,
          ),
        ],
        // Mixed tiers
        [
          PackageReferenceEntry(
            packageName: 'MappedPkg',
            version: '1.0.0',
            tier: 1,
            dartMapping: const DartMapping(
              dartPackageName: 'mapped_pkg',
              dartImportPath: 'package:mapped_pkg/mapped_pkg.dart',
            ),
          ),
          const PackageReferenceEntry(
            packageName: 'TranspiledPkg',
            version: '2.0.0',
            tier: 2,
          ),
          const PackageReferenceEntry(
            packageName: 'StubbedPkg',
            version: '3.0.0',
            tier: 3,
          ),
        ],
        // Multiple tier 1 packages
        [
          PackageReferenceEntry(
            packageName: 'PkgA',
            version: '1.0.0',
            tier: 1,
            dartMapping: const DartMapping(
              dartPackageName: 'pkg_a',
              dartImportPath: 'package:pkg_a/pkg_a.dart',
            ),
          ),
          PackageReferenceEntry(
            packageName: 'PkgB',
            version: '2.0.0',
            tier: 1,
            dartMapping: const DartMapping(
              dartPackageName: 'pkg_b',
              dartImportPath: 'package:pkg_b/pkg_b.dart',
            ),
          ),
        ],
      ];

      for (final packages in packageSets) {
        final parser = FakeInputParser();
        final fixture = ProjectFileData(
          absolutePath: '${tempDir.path}/PkgTest_${packageSets.indexOf(packages)}.csproj',
          assemblyName: 'PkgTest',
          targetFramework: 'net8.0',
          packageReferences: packages
              .map((p) => PackageReferenceSpec(
                    packageName: p.packageName,
                    version: p.version,
                  ))
              .toList(),
        );
        final path = registerTempCsproj(tempDir, parser, fixture);

        final nugetHandler = FakeNuGetHandler(
          result: NuGetResolveResult(
            assemblyPaths: const [],
            packageReferences: packages,
            diagnostics: const [],
          ),
        );

        final loader = makeLoader(inputParser: parser, nugetHandler: nugetHandler);
        final config = makeConfigService();

        final result = await loader.load(path, config);

        expect(result.projects, hasLength(1));
        final entry = result.projects.first;

        for (final pkg in entry.packageReferences) {
          expect(
            [1, 2, 3].contains(pkg.tier),
            isTrue,
            reason: 'tier must be 1, 2, or 3 for package ${pkg.packageName}',
          );

          if (pkg.tier == 1) {
            expect(
              pkg.dartMapping,
              isNotNull,
              reason: 'dartMapping must be non-null for Tier 1 package ${pkg.packageName}',
            );
          } else {
            expect(
              pkg.dartMapping,
              isNull,
              reason: 'dartMapping must be null for Tier ${pkg.tier} package ${pkg.packageName}',
            );
          }
        }
      }
    });
  });
}
