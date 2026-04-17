# Pipeline Orchestrator — Design Document

## Overview

The Pipeline Orchestrator is the top-level coordinator of the cs2dart transpiler. It is the only
component that holds references to all six pipeline stages and is responsible for invoking them in
the correct order, threading each stage's output into the next stage's input, enforcing the
early-exit policy, managing output directory layout, and assembling the final `TranspilerResult`.

The Orchestrator exposes two surfaces:

1. **Programmatic API** — `TranspilerResult transpile(TranspilerOptions options)`, a pure
   function-like method with no global state, suitable for embedding in build tools and test
   harnesses.
2. **CLI entry point** — the `cs2dart` binary, which parses command-line arguments, delegates to
   the programmatic API, renders diagnostics to stdout/stderr, and exits with an appropriate code.

The existing `pipeline_bootstrap.dart` already handles config file discovery and `ConfigLoader`
invocation. The Orchestrator wraps and extends that bootstrap into a full pipeline execution
context.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  bin/cs2dart.dart  (CLI entry point)                            │
│  CliRunner.run(List<String> args)                               │
│    │  args package parsing                                      │
│    │  TranspilerOptions construction                            │
│    │  DiagnosticRenderer.renderAll(result)                      │
│    └─► Orchestrator.transpile(options)                          │
└─────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  lib/src/orchestrator/orchestrator.dart                         │
│  Orchestrator                                                   │
│    1. bootstrapPipeline()  → IConfigService                     │
│    2. ProjectLoader.load() → LoadResult                         │
│    3. RoslynFrontend.process() → FrontendResult                 │
│    4. IrBuilder.build()    → IrBuildResult                      │
│    5. DartGenerator.generate() → GenResult                      │
│    6. OutputPathAssigner.assign()  (mutates GenResult copies)   │
│    7. Validator.validate() → TranspilerResult                   │
└─────────────────────────────────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
   IProjectLoader  IRoslynFrontend   IIrBuilder  …  (injected interfaces)
```

All stage interfaces are injected at construction time, making the Orchestrator fully testable
with fakes.

---

## Components and Interfaces

### TranspilerOptions

A plain immutable value object carrying all runtime parameters for one pipeline invocation.

```dart
/// All runtime parameters for a single transpiler invocation.
final class TranspilerOptions {
  /// Path to the .csproj or .sln file to transpile.
  final String inputPath;

  /// Root directory under which per-package subdirectories are created.
  final String outputDirectory;

  /// Explicit path to transpiler.yaml; null triggers directory search.
  final String? configPath;

  /// When true, emit Info-severity diagnostics to stdout.
  final bool verbose;

  /// When true, skip `dart format` (sets validation.skip_format flag).
  final bool skipFormat;

  /// When true, skip `dart analyze` (sets validation.skip_analyze flag).
  final bool skipAnalyze;

  const TranspilerOptions({
    required this.inputPath,
    required this.outputDirectory,
    this.configPath,
    this.verbose = false,
    this.skipFormat = false,
    this.skipAnalyze = false,
  });
}
```

### TranspilerResult

Defined by the Result Collector specification. Reproduced here for reference:

```dart
/// The assembled output of a complete (or early-exited) pipeline run.
final class TranspilerResult {
  final bool success;
  final List<OutputPackage> packages;
  final List<Diagnostic> diagnostics;
}
```

`success` is `true` iff no `Error`-severity diagnostic is present.

### Diagnostic (pipeline-wide)

A unified diagnostic record used across all stages. The Orchestrator emits `OR`-prefixed codes.

```dart
final class Diagnostic {
  final DiagnosticSeverity severity;  // error | warning | info
  final String code;                  // e.g. "OR0001"
  final String message;
  final String? source;               // file path, nullable
  final SourceLocation? location;     // { line, column }, nullable
}
```

### Stage Interfaces

Each pipeline stage is represented by an abstract interface. The Orchestrator depends only on
these interfaces, never on concrete implementations.

```dart
abstract interface class IProjectLoader {
  Future<LoadResult> load(String inputPath, IConfigService config);
}

abstract interface class IRoslynFrontend {
  Future<FrontendResult> process(LoadResult loadResult);
}

abstract interface class IIrBuilder {
  Future<IrBuildResult> build(FrontendResult frontendResult);
}

abstract interface class IDartGenerator {
  Future<GenResult> generate(IrBuildResult irBuildResult);
}

abstract interface class IValidator {
  Future<TranspilerResult> validate(GenResult genResult);
}
```

### Orchestrator

```dart
final class Orchestrator {
  final IProjectLoader _projectLoader;
  final IRoslynFrontend _roslynFrontend;
  final IIrBuilder _irBuilder;
  final IDartGenerator _dartGenerator;
  final IValidator _validator;
  final ConfigBootstrap _configBootstrap;   // wraps bootstrapPipeline()
  final OutputPathAssigner _pathAssigner;   // snake_case mapping + collision handling
  final DirectoryManager _directoryManager; // output dir creation

  const Orchestrator({
    required IProjectLoader projectLoader,
    required IRoslynFrontend roslynFrontend,
    required IIrBuilder irBuilder,
    required IDartGenerator dartGenerator,
    required IValidator validator,
    ConfigBootstrap? configBootstrap,
    OutputPathAssigner? pathAssigner,
    DirectoryManager? directoryManager,
  });

  Future<TranspilerResult> transpile(TranspilerOptions options);
}
```

`ConfigBootstrap`, `OutputPathAssigner`, and `DirectoryManager` are also injected (with
production defaults) so they can be replaced in tests.

### ConfigBootstrap

Thin wrapper around `bootstrapPipeline()` from `pipeline_bootstrap.dart`. Extracted as an
injectable collaborator so tests can supply a fake config without touching the file system.

```dart
abstract interface class IConfigBootstrap {
  Future<(ConfigLoadResult, PipelineContainer?)> load({
    required String entryPath,
    String? explicitConfigPath,
  });
}
```

### OverrideConfigService

A decorator around `IConfigService` that overrides specific `experimentalFeatures` entries while
delegating all other accessors to the wrapped instance. Used to apply `SkipFormat`/`SkipAnalyze`
without mutating the original `ConfigService`.

```dart
final class OverrideConfigService implements IConfigService {
  final IConfigService _inner;
  final Map<String, bool> _overrides;

  const OverrideConfigService(this._inner, this._overrides);

  @override
  Map<String, bool> get experimentalFeatures => {
    ..._inner.experimentalFeatures,
    ..._overrides,
  };

  // All other getters delegate to _inner unchanged.
}
```

### OutputPathAssigner

Pure function component responsible for computing `OutputPath` for each `DartPackage` in a
`GenResult`. Handles snake_case conversion and collision disambiguation.

```dart
final class OutputPathAssigner {
  /// Assigns absolute OutputPath values to all packages in [genResult].
  ///
  /// Returns a new GenResult with updated packages; does not mutate the input.
  GenResult assign(GenResult genResult, String outputDirectory);

  /// Converts a C# project name to a Dart-idiomatic snake_case package name.
  ///
  /// Applies the same transformation used by DartGenerator:
  ///   "MyProject.Core" → "my_project_core"
  static String toSnakeCase(String projectName);
}
```

Collision disambiguation algorithm:
1. Build a map from `snakeCase(name)` → list of packages with that name.
2. For any key with more than one package, assign the first package the base name, subsequent
   packages `_2`, `_3`, etc., in the order they appear in `GenResult.packages`.
3. Emit one `OR`-prefixed `Warning` diagnostic per collision group.

### DiagnosticRenderer

Pure function component that formats a `Diagnostic` to a human-readable string for CLI output.

```dart
final class DiagnosticRenderer {
  /// Formats a single diagnostic to the CLI output format.
  ///
  /// Format: `<severity> <CODE>: <MESSAGE> [<SOURCE>:<LINE>:<COLUMN>]`
  /// The location bracket is omitted when source or location is absent.
  static String format(Diagnostic diagnostic);

  /// Renders all diagnostics from [result] to stdout/stderr according to
  /// [verbose] setting, then prints the summary line.
  static void renderAll(TranspilerResult result, {required bool verbose});
}
```

### CliRunner

Owns argument parsing and bridges the CLI to the Orchestrator.

```dart
final class CliRunner {
  final Orchestrator _orchestrator;

  Future<int> run(List<String> args);
}
```

---

## Data Models

### Stage Result Types (stubs — defined in their respective specs)

| Type | Key fields | Empty-collection field |
|---|---|---|
| `LoadResult` | `projects`, `diagnostics`, `success` | `projects.isEmpty` |
| `FrontendResult` | `units`, `diagnostics`, `success` | `units.isEmpty` |
| `IrBuildResult` | `units`, `diagnostics`, `success` | `units.isEmpty` |
| `GenResult` | `packages`, `diagnostics`, `success` | `packages.isEmpty` |
| `TranspilerResult` | `packages`, `diagnostics`, `success` | — |

### OR Diagnostic Codes

| Code | Severity | Condition |
|---|---|---|
| `OR0001` | Error | Unhandled exception thrown by a pipeline stage |
| `OR0002` | Error | `InputPath` is null or empty |
| `OR0003` | Error | `OutputDirectory` is null or empty |
| `OR0004` | Error | Output directory creation failed |
| `OR0005` | Info | Early-exit triggered (stage name and reason in message) |
| `OR0006` | Warning | Package name collision; disambiguation applied |

---

## Stage Wiring and Data Flow

```
TranspilerOptions
      │
      ├─ validate options ──────────────────────────────► OR0002/OR0003 + early return
      │
      ▼
ConfigBootstrap.load(inputPath, configPath)
      │
      ├─ CFG errors? ───────────────────────────────────► early exit (CFG diags + OR0005)
      │
      ▼
applyOverrides(configService, skipFormat, skipAnalyze)
      │  → OverrideConfigService wrapping base service
      ▼
ProjectLoader.load(inputPath, configService)
      │
      ├─ success=false AND projects.isEmpty? ──────────► early exit (PL diags + OR0005)
      │
      ▼
RoslynFrontend.process(loadResult)
      │
      ├─ success=false AND units.isEmpty? ─────────────► early exit (RF diags + OR0005)
      │
      ▼
IrBuilder.build(frontendResult)
      │
      ├─ success=false AND units.isEmpty? ─────────────► early exit (IR diags + OR0005)
      │
      ▼
DartGenerator.generate(irBuildResult)
      │
      ├─ success=false AND packages.isEmpty? ──────────► early exit (CG diags + OR0005)
      │
      ▼
OutputPathAssigner.assign(genResult, outputDirectory)
      │  → sets DartPackage.outputPath for each package
      │  → emits OR0006 warnings for collisions
      ▼
DirectoryManager.ensureExists(outputDirectory)
      │
      ├─ creation failed? ──────────────────────────────► OR0004 + early exit
      │
      ▼
Validator.validate(genResultWithPaths)
      │  (Validator internally calls ResultCollector)
      ▼
TranspilerResult
```

Each stage invocation is wrapped in a `try/catch`. Any unhandled exception produces `OR0001` and
triggers an early exit. The exception is never re-thrown.

---

## Early-Exit Logic

The early-exit check is uniform across all stages:

```dart
TranspilerResult _earlyExit({
  required List<Diagnostic> collectedDiagnostics,
  required String stageName,
}) {
  final orDiag = Diagnostic(
    severity: DiagnosticSeverity.info,
    code: 'OR0005',
    message: 'Early exit after $stageName: stage returned empty result set.',
  );
  return TranspilerResult(
    success: false,
    packages: const [],
    diagnostics: [...collectedDiagnostics, orDiag],
  );
}
```

The trigger condition per stage:

| Stage | Trigger |
|---|---|
| Config_Service | `configLoadResult.hasErrors` (any CFG Error) |
| Project_Loader | `!loadResult.success && loadResult.projects.isEmpty` |
| Roslyn_Frontend | `!frontendResult.success && frontendResult.units.isEmpty` |
| IR_Builder | `!irBuildResult.success && irBuildResult.units.isEmpty` |
| Dart_Generator | `!genResult.success && genResult.packages.isEmpty` |

When `success=false` but the collection is non-empty, the pipeline continues to the next stage.

---

## Output Directory Management

### Snake_Case Conversion

The `toSnakeCase` function mirrors the transformation used by `DartGenerator`:

1. Insert `_` before each uppercase letter that follows a lowercase letter or digit
   (e.g., `MyProject` → `My_Project`).
2. Insert `_` before each uppercase letter that is followed by a lowercase letter and preceded by
   an uppercase letter (handles acronyms: `XMLParser` → `XML_Parser`).
3. Replace `.`, `-`, and spaces with `_`.
4. Lowercase the entire string.
5. Collapse consecutive `_` into a single `_`.
6. Strip leading/trailing `_`.

Examples: `MyProject.Core` → `my_project_core`, `XMLParser` → `xml_parser`.

### Collision Disambiguation

```
Input projects: ["Foo.Bar", "Foo_Bar", "Baz"]
snake_case:     ["foo_bar", "foo_bar", "baz"]

Assigned paths:
  Foo.Bar  → <outDir>/foo_bar      (first occurrence, no suffix)
  Foo_Bar  → <outDir>/foo_bar_2    (second occurrence, _2 suffix)
  Baz      → <outDir>/baz          (no collision)

Emitted: OR0006 Warning for the "foo_bar" collision group.
```

The suffix counter starts at `2` and increments for each additional collision. The order of
packages in `GenResult.packages` determines which package gets the base name.

### Path Resolution

All `OutputPath` values are resolved to absolute paths before being assigned. Relative paths in
`TranspilerOptions.outputDirectory` are resolved against `Directory.current.path`.

---

## Exception Handling Wrapper

Every stage call follows this pattern:

```dart
T _invokeStage<T>(String stageName, T Function() invoke) {
  try {
    return invoke();
  } catch (e, stackTrace) {
    throw _StageException(stageName, e, stackTrace);
  }
}
```

`_StageException` is caught at the top of `transpile()`, which then:

1. Emits `OR0001` with `message: 'Unhandled exception in $stageName: ${e.toString()}'`.
2. Calls `_earlyExit` with all diagnostics collected so far plus the `OR0001` entry.
3. Returns the `TranspilerResult` — never re-throws.

---

## Dependency Injection Design

The Orchestrator uses constructor injection throughout. A `OrchestratorFactory` provides the
production wiring:

```dart
final class OrchestratorFactory {
  static Orchestrator create() => Orchestrator(
    projectLoader: ProjectLoader(),
    roslynFrontend: RoslynFrontend(),
    irBuilder: IrBuilder(),
    dartGenerator: DartGenerator(),
    validator: Validator(),
  );
}
```

For tests, each stage is replaced with a `FakeStage` that returns a pre-configured result:

```dart
// Example test setup
final orchestrator = Orchestrator(
  projectLoader: FakeProjectLoader(result: emptyLoadResult),
  roslynFrontend: FakeRoslynFrontend(),
  irBuilder: FakeIrBuilder(),
  dartGenerator: FakeDartGenerator(),
  validator: FakeValidator(),
);
```

The `OverrideConfigService` is constructed inside `transpile()` when `skipFormat` or `skipAnalyze`
is `true`; otherwise the raw `IConfigService` from `ConfigBootstrap` is used directly.

---

## CLI Argument Parsing

The CLI uses Dart's `args` package (to be added to `pubspec.yaml`).

```dart
ArgParser _buildParser() => ArgParser()
  ..addOption('output', abbr: 'o', mandatory: true, help: 'Output directory')
  ..addOption('config', help: 'Explicit path to transpiler.yaml')
  ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Emit Info diagnostics')
  ..addFlag('no-format', negatable: false, help: 'Skip dart format')
  ..addFlag('no-analyze', negatable: false, help: 'Skip dart analyze')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage');
```

Parsing flow in `CliRunner.run()`:

1. Parse `args` with the `ArgParser`. On `ArgParserException`, print error + usage to stderr,
   return exit code `1`.
2. If `--help` / `-h`, print usage to stdout, return `0`.
3. If positional argument (input path) is absent, print usage to stderr, return `1`.
4. If `--output` is absent (caught by `mandatory: true`), print usage to stderr, return `1`.
5. Construct `TranspilerOptions` from parsed values.
6. Await `orchestrator.transpile(options)`.
7. Call `DiagnosticRenderer.renderAll(result, verbose: options.verbose)`.
8. Return `result.success ? 0 : 1`.

---

## Diagnostic Rendering for CLI Output

`DiagnosticRenderer.format(Diagnostic d)` produces:

```
<severity> <CODE>: <MESSAGE> [<SOURCE>:<LINE>:<COLUMN>]
```

- `<severity>` is `error`, `warning`, or `info` (lowercase).
- The `[<SOURCE>:<LINE>:<COLUMN>]` bracket is omitted when `source` is null.
- When `source` is present but `location` is null, the bracket is `[<SOURCE>]`.

`DiagnosticRenderer.renderAll(result, verbose)`:

1. Iterate `result.diagnostics` in order.
2. Print `Error` and `Warning` diagnostics to `stderr`.
3. Print `Info` diagnostics to `stdout` only when `verbose` is `true`.
4. After all diagnostics, print the summary line:
   - Success: `stdout` → `Transpilation succeeded. <N> package(s) written to <dir>.`
   - Failure: `stderr` → `Transpilation failed with <E> error(s) and <W> warning(s).`
5. When `verbose=false`, `success=true`, and no `Warning` diagnostics exist, no output is
   produced at all (silent clean run).

---

## SkipFormat / SkipAnalyze Override

`IConfigService.experimentalFeatures` is a `Map<String, bool>`. The Validator reads:
- `experimentalFeatures['validation.skip_format']` to decide whether to run `dart format`.
- `experimentalFeatures['validation.skip_analyze']` to decide whether to run `dart analyze`.

When `TranspilerOptions.skipFormat` or `skipAnalyze` is `true`, the Orchestrator wraps the
`IConfigService` in an `OverrideConfigService` before passing it to the Validator:

```dart
IConfigService _applyOverrides(IConfigService base, TranspilerOptions opts) {
  final overrides = <String, bool>{};
  if (opts.skipFormat) overrides['validation.skip_format'] = true;
  if (opts.skipAnalyze) overrides['validation.skip_analyze'] = true;
  if (overrides.isEmpty) return base;
  return OverrideConfigService(base, overrides);
}
```

The override is applied once, before any stage is invoked. All stages receive the same
(possibly-overridden) `IConfigService` instance.

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a
system — essentially, a formal statement about what the system should do. Properties serve as the
bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Determinism

*For any* `TranspilerOptions` and any set of deterministic mock stages, invoking `transpile()`
twice with the same options SHALL produce `TranspilerResult` values where `success` and the count
of `diagnostics` are identical.

**Validates: Requirements 10.5, 12.1**

---

### Property 2: Success Consistency

*For any* `TranspilerResult` where `success == true`, the `diagnostics` list SHALL contain no
entry with `severity == DiagnosticSeverity.error`.

**Validates: Requirements 12.2**

---

### Property 3: Failure Consistency

*For any* `TranspilerResult` where `success == false`, the `diagnostics` list SHALL contain at
least one entry with `severity == DiagnosticSeverity.error`.

**Validates: Requirements 12.3**

---

### Property 4: Invalid Options Early Return

*For any* `TranspilerOptions` where `inputPath` is empty or `outputDirectory` is empty, invoking
`transpile()` SHALL return a `TranspilerResult` with `success == false`, an `OR`-prefixed `Error`
diagnostic, and `packages == []`, without invoking any pipeline stage.

**Validates: Requirements 1.5, 1.6**

---

### Property 5: Early-Exit Invariant

*For any* pipeline run where any stage returns `success == false` AND an empty collection
(projects / units / packages), the returned `TranspilerResult` SHALL have `packages == []`,
`success == false`, and at least one `OR0005` `Info` diagnostic identifying the triggering stage.

**Validates: Requirements 4.1–4.11, 12.4**

---

### Property 6: Exception Wrapping

*For any* pipeline stage that throws any exception, `transpile()` SHALL return a
`TranspilerResult` with `success == false` and a diagnostic with `code == 'OR0001'`, and SHALL
NOT propagate the exception to the caller.

**Validates: Requirements 5.6, 11.1–11.5**

---

### Property 7: Config-Failure Isolation

*For any* config load that returns only `CFG`-prefixed `Error` diagnostics, the returned
`TranspilerResult.diagnostics` SHALL contain only entries whose `code` starts with `'CFG'` or
`'OR'`.

**Validates: Requirements 2.6, 12.9**

---

### Property 8: No Duplicate OR Codes

*For any* `TranspilerResult` produced by a single `transpile()` invocation, no `OR`-prefixed
diagnostic `code` value SHALL appear more than once in `diagnostics`.

**Validates: Requirements 5.5, 12.10**

---

### Property 9: SkipFormat / SkipAnalyze Propagation

*For any* `TranspilerOptions` where `skipFormat == true` (or `skipAnalyze == true`), the
`IConfigService` instance received by the Validator SHALL have
`experimentalFeatures['validation.skip_format'] == true` (or `'validation.skip_analyze' == true`),
regardless of what the underlying `transpiler.yaml` specifies.

**Validates: Requirements 2.4, 2.5, 12.7, 12.8**

---

### Property 10: Output Path Snake_Case Mapping

*For any* `DartPackage` with any `projectName`, after `OutputPathAssigner.assign()`, the package's
`outputPath` SHALL equal `path.join(outputDirectory, toSnakeCase(projectName))` (before collision
disambiguation).

**Validates: Requirements 6.1, 10.4**

---

### Property 11: Collision Disambiguation Uniqueness

*For any* list of `DartPackage` values (regardless of how many share the same `snakeCase` name),
after `OutputPathAssigner.assign()`, all `outputPath` values SHALL be distinct.

**Validates: Requirements 6.4**

---

### Property 12: Diagnostic Format Completeness

*For any* `Diagnostic` with any combination of `severity`, `code`, `message`, `source`, and
`location`, `DiagnosticRenderer.format()` SHALL return a string that contains the severity label,
the code, and the message; and SHALL contain the `[source:line:column]` bracket if and only if
`source` is non-null.

**Validates: Requirements 8.1–8.3**

---

### Property 13: Shared IConfigService Instance

*For any* successful pipeline run, every stage that accepts an `IConfigService` SHALL receive the
identical instance (by reference equality) — either the raw `ConfigService` or the single
`OverrideConfigService` wrapping it.

**Validates: Requirements 2.7**

---

## Error Handling

| Condition | OR Code | Severity | Behaviour |
|---|---|---|---|
| `inputPath` null/empty | OR0002 | Error | Return immediately, no stages invoked |
| `outputDirectory` null/empty | OR0003 | Error | Return immediately, no stages invoked |
| Config load has CFG errors | — | — | Early exit with CFG diagnostics + OR0005 |
| Stage returns empty collection | OR0005 | Info | Early exit with accumulated diagnostics |
| Output directory creation fails | OR0004 | Error | Early exit before Validator |
| Package name collision | OR0006 | Warning | Disambiguate, continue pipeline |
| Stage throws unhandled exception | OR0001 | Error | Catch, early exit, never re-throw |

All error paths return a `TranspilerResult` — the Orchestrator never throws.

---

## Testing Strategy

### Unit Tests (example-based)

- Verify `TranspilerOptions` field defaults.
- Verify `Orchestrator` constructor accepts all injected dependencies.
- Verify stage invocation order using call-recording fakes.
- Verify `ConfigBootstrap` is called before any stage.
- Verify `OverrideConfigService` correctly merges overrides with base features.
- Verify `toSnakeCase` for a representative set of project name patterns.
- Verify `DiagnosticRenderer.format` for each severity with and without location.
- Verify CLI `--help` output and exit code `0`.
- Verify CLI missing positional argument exits with code `1`.
- Verify CLI missing `--output` exits with code `1`.
- Verify CLI unrecognized flag exits with code `1`.
- Verify CLI exit code `0` on success, `1` on failure.

### Property-Based Tests

Property-based tests use the [`test`](https://pub.dev/packages/test) package together with a
property-based testing library (recommended: [`fast_check`](https://pub.dev/packages/fast_check)
or a custom generator harness built on `dart:math` `Random`). Each property test runs a minimum
of **100 iterations**.

Each test is tagged with a comment in the format:
`// Feature: pipeline-orchestrator, Property <N>: <property_text>`

| Property | Generator inputs | What is verified |
|---|---|---|
| P1 Determinism | Random `TranspilerOptions` + deterministic mock stages | Two calls → identical `success` and `diagnostics.length` |
| P2 Success consistency | Any `TranspilerResult` with `success=true` | No Error diagnostics present |
| P3 Failure consistency | Any `TranspilerResult` with `success=false` | At least one Error diagnostic present |
| P4 Invalid options | Empty/whitespace `inputPath` or `outputDirectory` | `success=false`, OR error, no stage invoked |
| P5 Early-exit invariant | Stage fakes returning `success=false` + empty collection | `packages=[]`, `success=false`, OR0005 present |
| P6 Exception wrapping | Stage fakes that throw arbitrary exceptions | `success=false`, OR0001 present, no exception propagated |
| P7 Config-failure isolation | Config fakes returning CFG errors | Only CFG/OR codes in diagnostics |
| P8 No duplicate OR codes | Any pipeline run producing OR diagnostics | Each OR code appears at most once |
| P9 SkipFormat/SkipAnalyze | Random `TranspilerOptions` with `skipFormat`/`skipAnalyze=true` | Validator receives correct experimental flags |
| P10 Snake_case mapping | Random project name strings | `outputPath == join(outDir, toSnakeCase(name))` |
| P11 Collision uniqueness | Random lists of project names (including duplicates) | All assigned `outputPath` values are distinct |
| P12 Diagnostic format | Random `Diagnostic` instances | Rendered string contains severity, code, message; bracket iff source present |
| P13 Shared config instance | Any successful pipeline run with mocks | All stages receive identical `IConfigService` reference |

### Integration Tests

- Full pipeline smoke test with all real stages replaced by minimal fakes that return valid
  (non-empty) results: verify `success=true` and `packages.length == projects.length`.
- Output directory creation: verify the directory is created when it does not exist.
- Config file discovery: verify `ConfigPath` override bypasses directory search.
