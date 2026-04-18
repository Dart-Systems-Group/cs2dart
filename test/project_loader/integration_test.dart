@Tags(['integration'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:cs2dart/src/project_loader/compilation_builder.dart';
import 'package:cs2dart/src/project_loader/input_parser.dart';
import 'package:cs2dart/src/project_loader/nuget_handler.dart';
import 'package:cs2dart/src/project_loader/project_loader_impl.dart';
import 'package:cs2dart/src/project_loader/sdk_resolver.dart';
import 'package:cs2dart/src/config/config_service.dart';
import 'package:cs2dart/src/config/models/config_object.dart';
import 'package:cs2dart/src/project_loader/models/output_kind.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ProjectLoader makeRealLoader() {
  return const ProjectLoader(
    inputParser: InputParser(),
    sdkResolver: SdkResolver(),
    nugetHandler: NuGetHandler(),
    compilationBuilder: CompilationBuilder(),
  );
}

ConfigService makeConfigService([ConfigObject config = ConfigObject.defaults]) {
  return ConfigService(config);
}

String fixturePath(String relative) {
  return '${Directory.current.path}/test/fixtures/$relative';
}

// ---------------------------------------------------------------------------
// Integration tests
// ---------------------------------------------------------------------------

void main() {
  // Test 11.1: Simple console project
  test('simple console project: single ProjectEntry with correct metadata', () async {
    final loader = makeRealLoader();
    final config = makeConfigService();
    final path = fixturePath('simple_console/SimpleConsole.csproj');

    final result = await loader.load(path, config);

    // Should produce exactly one ProjectEntry
    expect(result.projects, hasLength(1));
    final entry = result.projects.first;

    // Verify metadata
    expect(entry.projectName, equals('SimpleConsole'));
    expect(entry.targetFramework, equals('net8.0'));
    expect(entry.outputKind, equals(OutputKind.exe));
    expect(entry.langVersion, equals('12.0'));
    expect(entry.nullableEnabled, isTrue);

    // Verify source files were found
    expect(entry.compilation.syntaxTreePaths, isNotEmpty);
    expect(
      entry.compilation.syntaxTreePaths.any((p) => p.endsWith('Program.cs')),
      isTrue,
    );
  });

  // Test 11.2: Multi-project solution
  test('multi-project solution: one entry per project in topological order', () async {
    final loader = makeRealLoader();
    final config = makeConfigService();
    final path = fixturePath('multi_project_solution/MultiProject.sln');

    final result = await loader.load(path, config);

    // Should produce 3 ProjectEntries
    expect(result.projects, hasLength(3));

    // Verify topological order: Core first, then Services, then App
    final names = result.projects.map((p) => p.projectName).toList();
    final coreIdx = names.indexOf('Core');
    final servicesIdx = names.indexOf('Services');
    final appIdx = names.indexOf('App');

    expect(coreIdx, lessThan(servicesIdx), reason: 'Core must come before Services');
    expect(servicesIdx, lessThan(appIdx), reason: 'Services must come before App');

    // Verify DependencyGraph is populated
    expect(result.dependencyGraph.nodes, hasLength(3));
  });

  // Test 11.3: NuGet packages — resilient to missing NuGet cache
  test('nuget packages: PackageReferenceEntry tier and dartMapping populated', () async {
    final loader = makeRealLoader();
    final config = makeConfigService();
    final path = fixturePath('nuget_packages/NugetPackages.csproj');

    final result = await loader.load(path, config);

    expect(result.projects, hasLength(1));
    final entry = result.projects.first;

    // Both packages should be present in packageReferences regardless of cache state.
    final newtonsoftJson = entry.packageReferences.firstWhere(
      (p) => p.packageName == 'Newtonsoft.Json',
      orElse: () => throw StateError('Newtonsoft.Json not found in packageReferences'),
    );
    final serilog = entry.packageReferences.firstWhere(
      (p) => p.packageName == 'Serilog',
      orElse: () => throw StateError('Serilog not found in packageReferences'),
    );

    // Newtonsoft.Json is Tier 1 in the registry.
    // If the assembly is found in cache: tier == 1 with non-null dartMapping.
    // If the assembly is missing from cache: downgraded to tier == 3 with null dartMapping.
    expect(newtonsoftJson.tier, anyOf(equals(1), equals(3)));
    if (newtonsoftJson.tier == 1) {
      expect(newtonsoftJson.dartMapping, isNotNull);
    } else {
      expect(newtonsoftJson.dartMapping, isNull);
    }

    // Serilog is not in the registry → always Tier 3 with null dartMapping.
    expect(serilog.tier, equals(3));
    expect(serilog.dartMapping, isNull);
  });

  // Test 11.4: Nullable enabled project
  test('nullable enabled project: nullableEnabled is true', () async {
    final loader = makeRealLoader();
    final config = makeConfigService();
    final path = fixturePath('nullable_enabled/NullableEnabled.csproj');

    final result = await loader.load(path, config);

    expect(result.projects, hasLength(1));
    final entry = result.projects.first;

    expect(entry.nullableEnabled, isTrue);
    expect(entry.compilation.options.nullableEnabled, isTrue);
  });
}
