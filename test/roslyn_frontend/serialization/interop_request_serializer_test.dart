import 'package:test/test.dart';
import 'package:cs2dart/src/project_loader/models/roslyn_interop.dart';
import 'package:cs2dart/src/roslyn_frontend/models/interop_request.dart';
import 'package:cs2dart/src/roslyn_frontend/serialization/interop_request_serializer.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _serializer = InteropRequestSerializer();

/// Builds a minimal [InteropRequest] with one project and a basic config.
InteropRequest _minimalRequest() {
  return InteropRequest(
    projects: [
      ProjectEntryRequest(
        projectName: 'MyApp',
        projectFilePath: '/path/to/MyApp.csproj',
        outputKind: OutputKind.exe,
        targetFramework: 'net8.0',
        langVersion: '12.0',
        nullableEnabled: true,
        packageReferences: [
          PackageReferenceEntry(
            packageName: 'Newtonsoft.Json',
            version: '13.0.1',
            tier: 1,
            dartMapping: DartMapping(
              dartPackageName: 'json_serializable',
              dartImportPath: 'package:json_serializable/json_serializable.dart',
            ),
          ),
        ],
        sourceFilePaths: ['/path/to/Program.cs'],
      ),
    ],
    config: FrontendConfig(
      linqStrategy: 'preserve_functional',
      nullabilityEnabled: true,
      experimentalFeatures: {'someFeature': true, 'otherFeature': false},
    ),
  );
}

/// Builds a request with all [OutputKind] values for round-trip coverage.
List<InteropRequest> _requestsForAllOutputKinds() {
  return OutputKind.values.map((kind) {
    return InteropRequest(
      projects: [
        ProjectEntryRequest(
          projectName: 'Proj',
          projectFilePath: '/Proj.csproj',
          outputKind: kind,
          targetFramework: 'net8.0',
          langVersion: '12.0',
          nullableEnabled: false,
          packageReferences: [],
          sourceFilePaths: [],
        ),
      ],
      config: FrontendConfig(
        linqStrategy: 'preserve_functional',
        nullabilityEnabled: false,
        experimentalFeatures: {},
      ),
    );
  }).toList();
}

// ---------------------------------------------------------------------------
// Equality helpers (InteropRequest has no == override, so compare manually)
// ---------------------------------------------------------------------------

void _expectEqualRequests(InteropRequest a, InteropRequest b) {
  expect(a.projects.length, equals(b.projects.length),
      reason: 'projects length');
  for (var i = 0; i < a.projects.length; i++) {
    _expectEqualProjectEntries(a.projects[i], b.projects[i]);
  }
  _expectEqualConfigs(a.config, b.config);
}

void _expectEqualProjectEntries(ProjectEntryRequest a, ProjectEntryRequest b) {
  expect(a.projectName, equals(b.projectName));
  expect(a.projectFilePath, equals(b.projectFilePath));
  expect(a.outputKind, equals(b.outputKind));
  expect(a.targetFramework, equals(b.targetFramework));
  expect(a.langVersion, equals(b.langVersion));
  expect(a.nullableEnabled, equals(b.nullableEnabled));
  expect(a.sourceFilePaths, equals(b.sourceFilePaths));
  expect(a.packageReferences.length, equals(b.packageReferences.length));
  for (var i = 0; i < a.packageReferences.length; i++) {
    _expectEqualPackageRefs(a.packageReferences[i], b.packageReferences[i]);
  }
}

void _expectEqualPackageRefs(PackageReferenceEntry a, PackageReferenceEntry b) {
  expect(a.packageName, equals(b.packageName));
  expect(a.version, equals(b.version));
  expect(a.tier, equals(b.tier));
  if (a.dartMapping == null) {
    expect(b.dartMapping, isNull);
  } else {
    expect(b.dartMapping, isNotNull);
    expect(a.dartMapping!.dartPackageName, equals(b.dartMapping!.dartPackageName));
    expect(a.dartMapping!.dartImportPath, equals(b.dartMapping!.dartImportPath));
  }
}

void _expectEqualConfigs(FrontendConfig a, FrontendConfig b) {
  expect(a.linqStrategy, equals(b.linqStrategy));
  expect(a.nullabilityEnabled, equals(b.nullabilityEnabled));
  expect(a.experimentalFeatures, equals(b.experimentalFeatures));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Round-trip: toJson → fromJson
  // -------------------------------------------------------------------------
  group('toJson → fromJson round-trip', () {
    test('minimal request round-trips correctly', () {
      final original = _minimalRequest();
      final json = _serializer.toJson(original);
      final restored = _serializer.fromJson(json);
      _expectEqualRequests(original, restored);
    });

    test('empty projects list round-trips correctly', () {
      final original = InteropRequest(
        projects: [],
        config: FrontendConfig(
          linqStrategy: 'lower_to_loops',
          nullabilityEnabled: false,
          experimentalFeatures: {},
        ),
      );
      final json = _serializer.toJson(original);
      final restored = _serializer.fromJson(json);
      _expectEqualRequests(original, restored);
    });

    test('multiple projects round-trip correctly', () {
      final original = InteropRequest(
        projects: [
          ProjectEntryRequest(
            projectName: 'App',
            projectFilePath: '/App.csproj',
            outputKind: OutputKind.exe,
            targetFramework: 'net8.0',
            langVersion: '12.0',
            nullableEnabled: true,
            packageReferences: [],
            sourceFilePaths: ['/App/Program.cs'],
          ),
          ProjectEntryRequest(
            projectName: 'Lib',
            projectFilePath: '/Lib.csproj',
            outputKind: OutputKind.library,
            targetFramework: 'net8.0',
            langVersion: '11.0',
            nullableEnabled: false,
            packageReferences: [],
            sourceFilePaths: ['/Lib/Class1.cs', '/Lib/Class2.cs'],
          ),
        ],
        config: FrontendConfig(
          linqStrategy: 'preserve_functional',
          nullabilityEnabled: true,
          experimentalFeatures: {},
        ),
      );
      final json = _serializer.toJson(original);
      final restored = _serializer.fromJson(json);
      _expectEqualRequests(original, restored);
    });

    test('package reference without dartMapping round-trips correctly', () {
      final original = InteropRequest(
        projects: [
          ProjectEntryRequest(
            projectName: 'App',
            projectFilePath: '/App.csproj',
            outputKind: OutputKind.library,
            targetFramework: 'net8.0',
            langVersion: '12.0',
            nullableEnabled: false,
            packageReferences: [
              PackageReferenceEntry(
                packageName: 'SomeLib',
                version: '2.0.0',
                tier: 3,
                dartMapping: null,
              ),
            ],
            sourceFilePaths: [],
          ),
        ],
        config: FrontendConfig(
          linqStrategy: 'preserve_functional',
          nullabilityEnabled: false,
          experimentalFeatures: {},
        ),
      );
      final json = _serializer.toJson(original);
      final restored = _serializer.fromJson(json);
      _expectEqualRequests(original, restored);
    });

    test('all OutputKind values round-trip correctly', () {
      for (final request in _requestsForAllOutputKinds()) {
        final json = _serializer.toJson(request);
        final restored = _serializer.fromJson(json);
        _expectEqualRequests(request, restored);
      }
    });

    test('empty experimentalFeatures round-trips correctly', () {
      final original = InteropRequest(
        projects: [],
        config: FrontendConfig(
          linqStrategy: 'preserve_functional',
          nullabilityEnabled: true,
          experimentalFeatures: {},
        ),
      );
      final json = _serializer.toJson(original);
      final restored = _serializer.fromJson(json);
      expect(restored.config.experimentalFeatures, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // FrontendConfig serialization
  // -------------------------------------------------------------------------
  group('FrontendConfig serialization', () {
    test('linqStrategy is serialized correctly', () {
      final config = FrontendConfig(
        linqStrategy: 'lower_to_loops',
        nullabilityEnabled: false,
        experimentalFeatures: {},
      );
      final request = InteropRequest(projects: [], config: config);
      final json = _serializer.toJson(request);
      final configJson = json['config'] as Map<String, dynamic>;

      expect(configJson['linqStrategy'], equals('lower_to_loops'));
    });

    test('nullabilityEnabled = true is serialized correctly', () {
      final config = FrontendConfig(
        linqStrategy: 'preserve_functional',
        nullabilityEnabled: true,
        experimentalFeatures: {},
      );
      final request = InteropRequest(projects: [], config: config);
      final json = _serializer.toJson(request);
      final configJson = json['config'] as Map<String, dynamic>;

      expect(configJson['nullabilityEnabled'], isTrue);
    });

    test('nullabilityEnabled = false is serialized correctly', () {
      final config = FrontendConfig(
        linqStrategy: 'preserve_functional',
        nullabilityEnabled: false,
        experimentalFeatures: {},
      );
      final request = InteropRequest(projects: [], config: config);
      final json = _serializer.toJson(request);
      final configJson = json['config'] as Map<String, dynamic>;

      expect(configJson['nullabilityEnabled'], isFalse);
    });

    test('experimentalFeatures map is serialized correctly', () {
      final config = FrontendConfig(
        linqStrategy: 'preserve_functional',
        nullabilityEnabled: false,
        experimentalFeatures: {'featureA': true, 'featureB': false},
      );
      final request = InteropRequest(projects: [], config: config);
      final json = _serializer.toJson(request);
      final configJson = json['config'] as Map<String, dynamic>;
      final features =
          configJson['experimentalFeatures'] as Map<String, dynamic>;

      expect(features['featureA'], isTrue);
      expect(features['featureB'], isFalse);
    });

    test('experimentalFeatures uses camelCase key', () {
      final config = FrontendConfig(
        linqStrategy: 'preserve_functional',
        nullabilityEnabled: false,
        experimentalFeatures: {},
      );
      final request = InteropRequest(projects: [], config: config);
      final json = _serializer.toJson(request);
      final configJson = json['config'] as Map<String, dynamic>;

      expect(configJson.containsKey('experimentalFeatures'), isTrue);
    });

    test('config uses camelCase keys', () {
      final config = FrontendConfig(
        linqStrategy: 'preserve_functional',
        nullabilityEnabled: true,
        experimentalFeatures: {},
      );
      final request = InteropRequest(projects: [], config: config);
      final json = _serializer.toJson(request);
      final configJson = json['config'] as Map<String, dynamic>;

      expect(configJson.containsKey('linqStrategy'), isTrue);
      expect(configJson.containsKey('nullabilityEnabled'), isTrue);
      expect(configJson.containsKey('experimentalFeatures'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // OutputKind serialization
  // -------------------------------------------------------------------------
  group('OutputKind serialization', () {
    test('exe serializes to "exe"', () {
      final json = _serializer.toJson(InteropRequest(
        projects: [
          ProjectEntryRequest(
            projectName: 'P',
            projectFilePath: '/P.csproj',
            outputKind: OutputKind.exe,
            targetFramework: 'net8.0',
            langVersion: '12.0',
            nullableEnabled: false,
            packageReferences: [],
            sourceFilePaths: [],
          ),
        ],
        config: FrontendConfig(
          linqStrategy: 'preserve_functional',
          nullabilityEnabled: false,
          experimentalFeatures: {},
        ),
      ));
      final projectJson =
          (json['projects'] as List<dynamic>)[0] as Map<String, dynamic>;
      expect(projectJson['outputKind'], equals('exe'));
    });

    test('library serializes to "library"', () {
      final json = _serializer.toJson(InteropRequest(
        projects: [
          ProjectEntryRequest(
            projectName: 'P',
            projectFilePath: '/P.csproj',
            outputKind: OutputKind.library,
            targetFramework: 'net8.0',
            langVersion: '12.0',
            nullableEnabled: false,
            packageReferences: [],
            sourceFilePaths: [],
          ),
        ],
        config: FrontendConfig(
          linqStrategy: 'preserve_functional',
          nullabilityEnabled: false,
          experimentalFeatures: {},
        ),
      ));
      final projectJson =
          (json['projects'] as List<dynamic>)[0] as Map<String, dynamic>;
      expect(projectJson['outputKind'], equals('library'));
    });

    test('winExe serializes to "winExe"', () {
      final json = _serializer.toJson(InteropRequest(
        projects: [
          ProjectEntryRequest(
            projectName: 'P',
            projectFilePath: '/P.csproj',
            outputKind: OutputKind.winExe,
            targetFramework: 'net8.0',
            langVersion: '12.0',
            nullableEnabled: false,
            packageReferences: [],
            sourceFilePaths: [],
          ),
        ],
        config: FrontendConfig(
          linqStrategy: 'preserve_functional',
          nullabilityEnabled: false,
          experimentalFeatures: {},
        ),
      ));
      final projectJson =
          (json['projects'] as List<dynamic>)[0] as Map<String, dynamic>;
      expect(projectJson['outputKind'], equals('winExe'));
    });
  });

  // -------------------------------------------------------------------------
  // ProjectEntryRequest field serialization
  // -------------------------------------------------------------------------
  group('ProjectEntryRequest serialization', () {
    test('all fields use camelCase keys', () {
      final json = _serializer.toJson(_minimalRequest());
      final projectJson =
          (json['projects'] as List<dynamic>)[0] as Map<String, dynamic>;

      expect(projectJson.containsKey('projectName'), isTrue);
      expect(projectJson.containsKey('projectFilePath'), isTrue);
      expect(projectJson.containsKey('outputKind'), isTrue);
      expect(projectJson.containsKey('targetFramework'), isTrue);
      expect(projectJson.containsKey('langVersion'), isTrue);
      expect(projectJson.containsKey('nullableEnabled'), isTrue);
      expect(projectJson.containsKey('packageReferences'), isTrue);
      expect(projectJson.containsKey('sourceFilePaths'), isTrue);
    });

    test('sourceFilePaths list is serialized correctly', () {
      final json = _serializer.toJson(_minimalRequest());
      final projectJson =
          (json['projects'] as List<dynamic>)[0] as Map<String, dynamic>;
      final paths = projectJson['sourceFilePaths'] as List<dynamic>;

      expect(paths, equals(['/path/to/Program.cs']));
    });
  });

  // -------------------------------------------------------------------------
  // PackageReferenceEntry serialization
  // -------------------------------------------------------------------------
  group('PackageReferenceEntry serialization', () {
    test('dartMapping is included when present', () {
      final json = _serializer.toJson(_minimalRequest());
      final projectJson =
          (json['projects'] as List<dynamic>)[0] as Map<String, dynamic>;
      final pkgJson =
          (projectJson['packageReferences'] as List<dynamic>)[0]
              as Map<String, dynamic>;

      expect(pkgJson.containsKey('dartMapping'), isTrue);
      final dm = pkgJson['dartMapping'] as Map<String, dynamic>;
      expect(dm['dartPackageName'], equals('json_serializable'));
      expect(dm['dartImportPath'],
          equals('package:json_serializable/json_serializable.dart'));
    });

    test('dartMapping key is absent when null', () {
      final request = InteropRequest(
        projects: [
          ProjectEntryRequest(
            projectName: 'P',
            projectFilePath: '/P.csproj',
            outputKind: OutputKind.library,
            targetFramework: 'net8.0',
            langVersion: '12.0',
            nullableEnabled: false,
            packageReferences: [
              PackageReferenceEntry(
                packageName: 'SomeLib',
                version: '1.0.0',
                tier: 3,
                dartMapping: null,
              ),
            ],
            sourceFilePaths: [],
          ),
        ],
        config: FrontendConfig(
          linqStrategy: 'preserve_functional',
          nullabilityEnabled: false,
          experimentalFeatures: {},
        ),
      );
      final json = _serializer.toJson(request);
      final projectJson =
          (json['projects'] as List<dynamic>)[0] as Map<String, dynamic>;
      final pkgJson =
          (projectJson['packageReferences'] as List<dynamic>)[0]
              as Map<String, dynamic>;

      expect(pkgJson.containsKey('dartMapping'), isFalse);
    });
  });
}
