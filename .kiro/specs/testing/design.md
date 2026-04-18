# Testing Infrastructure — Design Document

## Overview

This document specifies the design of the testing infrastructure for the C# → Dart transpiler
pipeline. It covers the test framework, mocking strategy, property-based testing approach, shared
test utilities, fixture management, coverage tooling, and the conventions that every module test
suite must follow.

The testing infrastructure is not a pipeline stage; it is a cross-cutting concern that governs how
all other modules are validated. Every module spec's "Testing Strategy" section defers to this
document for framework choices, fake implementations, and PBT conventions.

---

## Architecture

### Test Framework Stack

| Layer | Library | Purpose |
|---|---|---|
| Test runner | [`package:test`](https://pub.dev/packages/test) `^1.24.0` | Unit, integration, and golden tests |
| Mocking | [`package:mockito`](https://pub.dev/packages/mockito) `^5.4.0` | Generated mocks for interface-based fakes |
| Code generation | [`package:build_runner`](https://pub.dev/packages/build_runner) `^2.4.0` | Drives `mockito` annotation processing |
| Coverage | [`package:coverage`](https://pub.dev/packages/coverage) `^1.7.0` | Line and branch coverage collection |

Property-based testing is implemented without an external PBT library. Each module provides its
own `forAll` helper (seeded `dart:math` `Random`) following the pattern established in
`test/config/config_properties_test.dart`. This keeps the dependency surface minimal while
satisfying all PBT requirements from the requirements document.

### Directory Layout

```
test/
├── config/
│   ├── generators/
│   │   └── config_generators.dart        # Arbitrary generators for ConfigObject
│   ├── models/
│   │   └── models_test.dart
│   ├── config_components_test.dart
│   ├── config_loader_test.dart
│   └── config_properties_test.dart
├── fixtures/
│   ├── csharp/                           # C# source fixtures (one per supported feature)
│   ├── ir/                               # Serialized IR JSON golden files
│   ├── dart/                             # Expected Dart output golden files
│   └── configs/                          # transpiler.yaml fixtures
├── orchestrator/
│   ├── fakes/
│   │   ├── fake_config_bootstrap.dart
│   │   ├── fake_config_service.dart
│   │   ├── fake_dart_generator.dart
│   │   ├── fake_directory_manager.dart
│   │   ├── fake_ir_builder.dart
│   │   ├── fake_project_loader.dart
│   │   ├── fake_roslyn_frontend.dart
│   │   └── fake_validator.dart
│   ├── diagnostic_renderer_test.dart
│   └── orchestrator_test.dart
├── project_loader/
│   ├── fakes/
│   │   ├── fake_compilation_builder.dart
│   │   ├── fake_input_parser.dart
│   │   ├── fake_nuget_handler.dart
│   │   └── fake_sdk_resolver.dart
│   ├── input_parser_test.dart
│   ├── integration_test.dart
│   └── project_loader_properties_test.dart
├── roslyn_frontend/
│   ├── fakes/
│   │   └── fake_interop_bridge.dart
│   ├── serialization/
│   │   ├── frontend_result_deserializer_test.dart
│   │   └── interop_request_serializer_test.dart
│   └── frontend_result_assembler_test.dart
├── ir_builder/                           # (to be created)
│   ├── fakes/
│   │   └── fake_frontend_result.dart
│   ├── generators/
│   │   └── ir_generators.dart
│   └── ir_builder_properties_test.dart
├── dart_generator/                       # (to be created)
│   ├── fakes/
│   │   └── fake_ir_build_result.dart
│   ├── generators/
│   │   └── dart_generator_generators.dart
│   └── dart_generator_properties_test.dart
├── namespace_mapper/                     # (to be created)
│   ├── generators/
│   │   └── namespace_generators.dart
│   └── namespace_mapper_properties_test.dart
├── struct_transpiler/                    # (to be created)
│   └── struct_transpiler_properties_test.dart
├── event_transpiler/                     # (to be created)
│   └── event_transpiler_properties_test.dart
├── nuget_handler/                        # (to be created)
│   ├── fakes/
│   │   └── fake_package_resolver.dart
│   ├── generators/
│   │   └── nuget_generators.dart
│   └── nuget_handler_properties_test.dart
└── shared/
    ├── fake_config_service.dart          # Canonical shared FakeConfigService
    ├── fake_file_system.dart             # In-memory IFileSystem fake
    ├── fake_http_client.dart             # Pre-recorded response IHttpClient fake
    ├── ir_builders.dart                  # IR tree builder helpers for every IR_Node type
    └── for_all.dart                      # Shared forAll PBT helper
```

---

## Components and Interfaces

### `forAll` Helper

The shared PBT helper lives in `test/shared/for_all.dart` and is imported by every property test
suite:

```dart
/// Runs [property] for [iterations] deterministic seeds.
///
/// Each iteration creates a fresh [Random] seeded with the iteration index,
/// generates a value via [generator], and passes it to [property].
///
/// The number of iterations defaults to 100 but can be overridden via the
/// [PBT_RUNS] environment variable.
void forAll<T>(
  T Function(Random) generator,
  void Function(T) property, {
  int? iterations,
}) {
  final runs = iterations ??
      int.tryParse(Platform.environment['PBT_RUNS'] ?? '') ??
      100;
  for (var i = 0; i < runs; i++) {
    final random = Random(i);
    final value = generator(random);
    property(value);
  }
}
```

The seed for each iteration is the iteration index, so failures are reproducible by re-running
with the same `PBT_RUNS` value. The seed is logged in the test output via the `reason` parameter
of `expect` calls.

### `FakeConfigService`

The canonical `FakeConfigService` lives in `test/shared/fake_config_service.dart`. Module-local
copies (e.g., `test/orchestrator/fakes/fake_config_service.dart`) delegate to this shared
implementation. It wraps a `ConfigObject` and implements `IConfigService` by forwarding all
accessors to the wrapped object:

```dart
/// A test double for [IConfigService] that returns configurable values.
///
/// Defaults to [ConfigObject.defaults] when no [config] is supplied.
final class FakeConfigService implements IConfigService {
  final ConfigObject _config;

  const FakeConfigService({ConfigObject config = ConfigObject.defaults})
      : _config = config;

  @override
  ConfigObject get config => _config;

  // All other IConfigService accessors delegate to _config.
  @override
  LinqStrategy get linqStrategy => _config.linqStrategy;
  // ... (remaining accessors omitted for brevity — see implementation)
}
```

### `FakeFileSystem`

An in-memory implementation of the `IFileSystem` abstraction used by modules that perform file
I/O. Lives in `test/shared/fake_file_system.dart`:

```dart
/// In-memory [IFileSystem] for use in unit tests.
///
/// Files are stored in a [Map<String, String>] keyed by absolute path.
/// Supports [readFile], [writeFile], [fileExists], [listDirectory], and
/// [deleteFile]. All operations are synchronous and never touch the real
/// file system.
final class FakeFileSystem implements IFileSystem {
  final Map<String, String> _files;

  FakeFileSystem({Map<String, String>? files})
      : _files = Map.of(files ?? {});

  @override
  bool fileExists(String path) => _files.containsKey(path);

  @override
  String readFile(String path) {
    if (!_files.containsKey(path)) {
      throw FileSystemException('File not found', path);
    }
    return _files[path]!;
  }

  @override
  void writeFile(String path, String content) => _files[path] = content;

  @override
  List<String> listDirectory(String path, {String? pattern}) =>
      _files.keys
          .where((k) => k.startsWith(path))
          .where((k) => pattern == null || RegExp(pattern).hasMatch(k))
          .toList()
        ..sort();

  @override
  void deleteFile(String path) => _files.remove(path);
}
```

### `FakeHttpClient`

A pre-recorded response fake for modules that perform network I/O (primarily `NuGet_Handler`).
Lives in `test/shared/fake_http_client.dart`:

```dart
/// Pre-recorded response [IHttpClient] for use in unit tests.
///
/// Responses are keyed by URL. Throws [FakeHttpException] for unregistered URLs
/// unless [allowUnregistered] is true, in which case it returns a 404 response.
final class FakeHttpClient implements IHttpClient {
  final Map<String, FakeHttpResponse> _responses;
  final bool allowUnregistered;

  FakeHttpClient({
    Map<String, FakeHttpResponse>? responses,
    this.allowUnregistered = false,
  }) : _responses = Map.of(responses ?? {});

  @override
  Future<HttpResponse> get(String url) async {
    if (_responses.containsKey(url)) {
      final fake = _responses[url]!;
      return HttpResponse(statusCode: fake.statusCode, body: fake.body);
    }
    if (allowUnregistered) {
      return HttpResponse(statusCode: 404, body: '');
    }
    throw FakeHttpException('No response registered for URL: $url');
  }
}

final class FakeHttpResponse {
  final int statusCode;
  final String body;
  const FakeHttpResponse({required this.statusCode, required this.body});
}
```

### Mockito-Generated Mocks

For interfaces where a hand-written fake would be verbose or where call-verification is needed,
`mockito` generated mocks are used. Mocks are generated via `build_runner` and stored alongside
the test files that use them.

Annotate the test file with `@GenerateMocks` and run `dart run build_runner build`:

```dart
// test/nuget_handler/nuget_handler_test.dart
import 'package:mockito/annotations.dart';
import 'package:cs2dart/src/project_loader/interfaces/i_nuget_handler.dart';
import 'package:cs2dart/src/project_loader/interfaces/i_sdk_resolver.dart';

@GenerateMocks([INuGetHandler, ISdkResolver])
void main() { /* ... */ }
```

This generates `nuget_handler_test.mocks.dart` containing `MockINuGetHandler` and
`MockISdkResolver`. Generated mock files are committed to the repository.

**When to use Mockito vs hand-written fakes:**

| Scenario | Approach |
|---|---|
| Simple stub returning fixed data | Hand-written fake (e.g., `FakeInputParser`) |
| Verifying call count or arguments | Mockito generated mock |
| Configurable return values per call | Mockito generated mock with `when(...).thenReturn(...)` |
| Shared across many test files | Hand-written fake in `test/shared/` or module `fakes/` |

---

## Test Categories and Conventions

### Unit Tests

Unit tests exercise a single class or function in isolation. All external dependencies are
replaced with fakes or mocks. File naming: `<component>_test.dart`.

```dart
// Example: testing a single method with a fake dependency
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';

import '../fakes/fake_config_service.dart';
import 'nuget_handler_test.mocks.dart';

void main() {
  group('NuGetHandler.resolve', () {
    late MockISdkResolver mockSdkResolver;

    setUp(() {
      mockSdkResolver = MockISdkResolver();
    });

    test('emits NR0001 when package not found', () async {
      when(mockSdkResolver.resolve(any, sdkPath: anyNamed('sdkPath')))
          .thenAnswer((_) async => SdkResolveResult(assemblyPaths: [], diagnostics: []));

      // ... test body
    });
  });
}
```

### Property-Based Tests

Property tests use the shared `forAll` helper and module-specific generators. File naming:
`<module>_properties_test.dart`.

Each property test is tagged with a comment identifying the feature and property number:

```dart
// Feature: testing, Property 1: forAll runs exactly PBT_RUNS iterations
test('forAll runs the configured number of iterations', () {
  var count = 0;
  forAll((_) => 0, (_) => count++, iterations: 50);
  expect(count, equals(50));
});
```

The minimum iteration count per property per CI run is **100**. The `PBT_RUNS` environment
variable overrides this for deeper local or nightly runs.

### Golden Tests

Golden tests compare SUT output against a checked-in reference file under `test/fixtures/dart/`.
A failing golden test prints a unified diff of the expected and actual output.

```dart
// Example golden test pattern
test('generates correct Dart for simple_console fixture', () async {
  final actual = await generator.generate(irFixture);
  final goldenPath = 'test/fixtures/dart/simple_console.dart';
  final expected = File(goldenPath).readAsStringSync();

  if (actual != expected) {
    final diff = _unifiedDiff(expected, actual, goldenPath);
    fail('Golden test failed. Run with --update-golden to regenerate.\n$diff');
  }
});
```

The `--update-golden` flag is implemented as a top-level boolean checked at test startup:

```dart
final _updateGolden = Platform.environment['UPDATE_GOLDEN'] == '1';
```

When `UPDATE_GOLDEN=1`, golden tests write the actual output to the reference file instead of
asserting equality.

### Integration Tests

Integration tests exercise two or more adjacent pipeline stages together. They are tagged
`@Tags(['integration'])` and excluded from the default fast-feedback run:

```dart
@Tags(['integration'])
library;

import 'package:test/test.dart';
// ...

void main() {
  group('Config_Service → Project_Loader integration', () {
    test('valid config is forwarded to LoadResult.config', () async {
      // Uses real ConfigService and real ProjectLoader with fake sub-components
    });
  });
}
```

Run integration tests explicitly with:

```
dart test --tags integration
```

### End-to-End Tests

End-to-end tests drive the full pipeline from a `.csproj` or `.sln` fixture to a complete
`Gen_Result`. They are tagged `@Tags(['e2e'])` and require a real .NET SDK:

```dart
@Tags(['e2e'])
library;

void main() {
  test('single .csproj with no NuGet dependencies produces valid Dart', () async {
    final result = await pipeline.run('test/fixtures/simple_console/SimpleConsole.csproj');
    expect(result.success, isTrue);
    for (final file in result.files) {
      final analyzeResult = await _dartAnalyze(file.content);
      expect(analyzeResult.errors, isEmpty,
          reason: 'dart analyze found errors in ${file.path}');
    }
  });
}
```

### Slow Tests

Tests that require longer than 5 seconds (e.g., full Roslyn compilation, real NuGet restore) are
tagged `@Tags(['slow'])`:

```dart
@Tags(['slow'])
test('loads real .csproj with NuGet packages', () async { /* ... */ });
```

The default test run excludes slow tests:

```
dart test --exclude-tags slow
```

CI runs the full suite (including slow tests) on pull requests targeting `main`.

---

## Mocking Strategy

### Constructor Injection

All production classes accept their dependencies via constructor parameters typed as interfaces.
This enables full replacement with fakes in tests without any framework magic:

```dart
// Production class
final class ProjectLoader implements IProjectLoader {
  final IInputParser _inputParser;
  final ISdkResolver _sdkResolver;
  final INuGetHandler _nugetHandler;
  final ICompilationBuilder _compilationBuilder;

  const ProjectLoader({
    required IInputParser inputParser,
    required ISdkResolver sdkResolver,
    required INuGetHandler nugetHandler,
    required ICompilationBuilder compilationBuilder,
  })  : _inputParser = inputParser,
        _sdkResolver = sdkResolver,
        _nugetHandler = nugetHandler,
        _compilationBuilder = compilationBuilder;
}

// Test
final loader = ProjectLoader(
  inputParser: FakeInputParser(),
  sdkResolver: FakeSdkResolver(),
  nugetHandler: FakeNuGetHandler(),
  compilationBuilder: FakeCompilationBuilder(),
);
```

### Fake Naming Convention

| Fake type | Naming | Location |
|---|---|---|
| Shared across modules | `Fake<Interface>` | `test/shared/` |
| Module-local | `Fake<Interface>` | `test/<module>/fakes/` |
| Mockito generated | `Mock<Interface>` | `test/<module>/<test_file>.mocks.dart` |

### Fake Configuration Principle

Fakes are configured with the minimum data needed for the test. A fake SHALL NOT be pre-loaded
with data unrelated to the property under test. This keeps tests focused and failure messages
informative.

---

## Property-Based Testing Design

### Generator Conventions

Each module that requires PBT provides a `generators/` subdirectory with a single
`<module>_generators.dart` file. Generators are pure functions taking a `Random` and returning
an arbitrary value of the target type:

```dart
// test/config/generators/config_generators.dart

/// Generates an arbitrary valid [ConfigObject].
ConfigObject validConfigObject(Random random) { /* ... */ }

/// Generates a valid YAML string for a [ConfigObject].
String validYamlContent(Random random) { /* ... */ }

/// Generates a random subset of recognized top-level YAML keys.
List<String> recognizedKeySubset(Random random) { /* ... */ }
```

Generators for IR nodes live in `test/ir_builder/generators/ir_generators.dart` and respect all
structural invariants defined in the `IR_Validator` (IR Requirement 14). Generators for C# source
live in `test/shared/csharp_generators.dart` and produce syntactically valid C# programs.

### Determinism Guarantee

Every generator is seeded with the iteration index, so the same `PBT_RUNS` value always produces
the same sequence of inputs. The seed is included in `expect` `reason` strings so that a failing
test output contains enough information to reproduce the failure:

```dart
for (var i = 0; i < runs; i++) {
  final random = Random(i);
  final value = generator(random);
  try {
    property(value);
  } catch (e) {
    fail('Property failed at seed $i with input: $value\n$e');
  }
}
```

### Shrinking

The project does not use an external PBT library with automatic shrinking. When a property fails,
the seed is logged and the developer can reproduce the failure by running with `PBT_SEED=<seed>`.
Manual shrinking is performed by constructing a minimal reproducer from the logged input.

---

## Coverage Configuration

### pubspec.yaml additions

```yaml
dev_dependencies:
  test: ^1.24.0
  mockito: ^5.4.0
  build_runner: ^2.4.0
  coverage: ^1.7.0
```

### Running with coverage

```bash
dart run coverage:test_with_coverage -- --exclude-tags slow
dart run coverage:format_coverage \
  --lcov \
  --in coverage/coverage.json \
  --out coverage/lcov.info \
  --report-on lib/
```

### Thresholds

Minimum thresholds are enforced in CI via a `coverage.yaml` at the repository root:

```yaml
# coverage.yaml
defaults:
  line: 80
  branch: 75

modules:
  config:
    line: 85
    branch: 80
  project_loader:
    line: 80
    branch: 75
  # Additional modules follow the same pattern.
  # A module MAY raise its threshold above the minimum.
```

A CI step reads `coverage.yaml` and fails the build if any module falls below its configured
threshold.

---

## Fixture Management

### Fixture Naming

Every fixture file is named descriptively after the C# feature it exercises:

```
test/fixtures/csharp/
├── async_method_with_cancellation_token.cs
├── class_with_generics.cs
├── enum_with_flags_attribute.cs
├── event_with_custom_delegate.cs
├── linq_query_syntax.cs
├── namespace_with_nested_types.cs
├── nullable_reference_types.cs
├── nuget_newtonsoft_json.csproj
├── pattern_matching_switch_expression.cs
├── record_type_with_deconstruct.cs
├── struct_with_value_equality.cs
└── ...
```

Each fixture file begins with a one-line comment describing the feature it exercises:

```csharp
// Exercises: async method with CancellationToken parameter and ConfigureAwait(false)
using System.Threading;
using System.Threading.Tasks;
// ...
```

### Golden File Pairing

Every C# fixture in `test/fixtures/csharp/` has a corresponding golden Dart file in
`test/fixtures/dart/` with the same base name and a `.dart` extension. The golden file is
generated by running the full pipeline on the fixture and reviewed by a developer before being
committed.

### IR Fixture Pairing

Every C# fixture also has a corresponding serialized IR JSON file in `test/fixtures/ir/`. This
enables IR round-trip tests and allows the `Dart_Generator` to be tested independently of the
`IR_Builder`.

---

## CI Integration

### Test Commands

| Command | What it runs |
|---|---|
| `dart test` | All unit and property tests (excludes `slow`, `integration`, `e2e`) |
| `dart test --tags integration` | Integration tests only |
| `dart test --tags e2e` | End-to-end tests only |
| `dart test --tags slow` | Slow tests only |
| `dart test --tags "integration,slow"` | Integration + slow |
| `dart run build_runner build` | Regenerates Mockito mocks |

### Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `PBT_RUNS` | `100` | Number of PBT iterations per property |
| `PBT_SEED` | _(iteration index)_ | Override seed for reproducing a specific failure |
| `UPDATE_GOLDEN` | `0` | Set to `1` to regenerate golden files |

### JUnit XML Report

The `package:test` JSON reporter is piped through a converter to produce JUnit-compatible XML for
CI dashboards:

```bash
dart test --reporter json | dart run test_reporter:junit > test-results.xml
```

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a
system — essentially, a formal statement about what the system should do. Properties serve as the
bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: `forAll` runs exactly `PBT_RUNS` iterations

*For any* generator and property function, `forAll` SHALL invoke the property function exactly
`PBT_RUNS` times (or the value of the `iterations` parameter when supplied).

**Validates: Requirement 2.3**

---

### Property 2: `forAll` seeds are deterministic

*For any* generator, running `forAll` twice with the same `iterations` value SHALL pass the same
sequence of generated values to the property function.

**Validates: Requirement 2.5, 10.2**

---

### Property 3: `FakeConfigService` returns value-equal config to the wrapped `ConfigObject`

*For any* `ConfigObject`, constructing a `FakeConfigService` with that object and calling
`config` SHALL return a value equal to the original `ConfigObject`.

**Validates: Requirement 12.1**

---

### Property 4: `FakeFileSystem` round-trip

*For any* file path and content string, writing the content via `FakeFileSystem.writeFile` and
then reading it back via `FakeFileSystem.readFile` SHALL return the original content unchanged.

**Validates: Requirement 12.2**

---

### Property 5: `FakeFileSystem.fileExists` is consistent with `writeFile` and `deleteFile`

*For any* file path, `fileExists` SHALL return `true` after `writeFile` and `false` after
`deleteFile` (or before any write).

**Validates: Requirement 12.2**

---

### Property 6: `FakeHttpClient` returns the registered response

*For any* URL and `FakeHttpResponse`, registering the response and calling `get(url)` SHALL
return an `HttpResponse` with the same `statusCode` and `body`.

**Validates: Requirement 12.3**

---

### Property 7: Golden test diff is non-empty when actual ≠ expected

*For any* pair of strings where `actual != expected`, the golden test diff helper SHALL produce a
non-empty string that contains both the expected and actual content.

**Validates: Requirement 11.1**

---

### Property 8: Diagnostic code pattern is enforced across all modules

*For any* `Diagnostic` emitted by any module, the `code` field SHALL match the pattern
`[A-Z]+[0-9]{4}` and the prefix SHALL be one of: `PL`, `IR`, `CG`, `NR`, `VA`, `CFG`, `RC`, `OR`.

**Validates: Requirement 5.4**

---

### Property 9: No two modules share a diagnostic code prefix

*For any* two diagnostics from different modules, their `code` prefixes SHALL be distinct (no
cross-module prefix collision).

**Validates: Requirement 5.4**

---

### Property 10: `FakeFileSystem.listDirectory` returns sorted paths

*For any* set of files written to a `FakeFileSystem`, `listDirectory` SHALL return paths in
ascending lexicographic order.

**Validates: Requirement 10.5**

---

## Testing Strategy

### Self-Testing

The testing infrastructure itself is tested in `test/shared/` with unit tests that verify the
behavior of `forAll`, `FakeConfigService`, `FakeFileSystem`, `FakeHttpClient`, and the golden
test diff helper. These tests run as part of the default `dart test` invocation.

### Mockito Mock Generation

After adding a new `@GenerateMocks` annotation, regenerate mocks with:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Generated mock files (`*.mocks.dart`) are committed to the repository so that CI does not require
a `build_runner` step before running tests.

### Adding a New Module Test Suite

When a new pipeline module is added:

1. Create `test/<module>/` with `fakes/` and `generators/` subdirectories.
2. Add a `<module>_properties_test.dart` covering all correctness properties from the module's
   design document.
3. Add a `<module>_test.dart` covering unit tests for all public methods.
4. Add at least one golden test pairing a C# fixture with an expected Dart output.
5. Add the module to `coverage.yaml` with the minimum thresholds.
6. If the module uses `mockito`, add `@GenerateMocks` and run `build_runner`.

### Parallel Test Execution

All tests are written to be parallelism-safe:

- No test uses shared mutable state or global singletons.
- File system tests use `Directory.systemTemp.createTempSync` with a unique prefix and clean up
  in `tearDown`.
- Mockito mocks are created fresh in `setUp` for each test group.
- `FakeFileSystem` and `FakeHttpClient` instances are created per-test, not shared.
