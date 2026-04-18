# Testing Requirements — C# → Dart Transpiler

## Introduction

This document specifies the testing requirements that apply across all features and modules of the
C# → Dart transpiler pipeline. It defines the testing strategy, test categories, property-based
testing (PBT) approach, coverage expectations, and correctness properties that every module must
satisfy. Individual module specs define module-specific correctness properties; this document
establishes the shared testing contract that governs how those properties are validated.

---

## Glossary

- **SUT**: System Under Test — the module or component being tested in a given test.
- **PBT**: Property-Based Testing — a testing technique where a property (invariant) is asserted to
  hold for all inputs drawn from a generator, rather than for a fixed set of hand-written examples.
- **Property**: A formal, executable invariant that the SUT must satisfy for all valid inputs.
- **Generator**: A function that produces arbitrary, randomized inputs of a given type for use in PBT.
- **Shrinking**: The PBT process of reducing a failing input to the smallest counterexample that
  still triggers the failure.
- **Golden Test**: A test that compares SUT output against a stored, human-reviewed reference output.
- **Round-Trip Test**: A test that verifies that serializing then deserializing (or transforming then
  inverting) a value produces a result equivalent to the original.
- **Unit Test**: A test that exercises a single function, method, or class in isolation.
- **Integration Test**: A test that exercises two or more pipeline stages together.
- **End-to-End Test**: A test that drives the full pipeline from a `.csproj` / `.sln` input to a
  complete Dart package output.
- **Diagnostic**: A structured error, warning, or info record emitted by a pipeline module.
- **Counterexample**: A specific input that falsifies a property, produced by a PBT framework when a
  property fails.
- **Seed**: A fixed integer value used to initialize a PBT random number generator, enabling
  deterministic replay of a failing test run.

---

## Requirements

### Requirement 1: Test Categories and Scope

**User Story:** As a transpiler maintainer, I want a well-defined set of test categories applied
consistently across all modules, so that every module is validated at the right level of granularity
and the test suite is navigable.

#### Acceptance Criteria

1. EVERY pipeline module (Config_Service, Project_Loader, IR_Builder, Dart_Generator,
   Namespace_Mapper, Struct_Transpiler, Event_Transpiler, NuGet_Handler) SHALL have a dedicated test
   suite containing at minimum: unit tests, property-based tests, and golden tests.
2. Unit tests SHALL exercise each public method or function of a module in isolation, using fakes or
   stubs for all external dependencies (file system, network, Roslyn APIs, `IConfigService`).
3. Integration tests SHALL exercise adjacent pipeline stage pairs: (Config_Service →
   Project_Loader), (Project_Loader → IR_Builder), (IR_Builder → Dart_Generator), and
   (NuGet_Handler → IR_Builder → Dart_Generator).
4. End-to-end tests SHALL drive the full pipeline from a `.csproj` or `.sln` fixture to a complete
   `Gen_Result`, asserting that `Gen_Result.Success` is `true` and that every `Gen_File.Content`
   passes `dart analyze` with zero errors.
5. Golden tests SHALL be maintained for every supported C# language feature, storing the expected
   Dart output as a checked-in reference file and failing when the SUT output diverges.
6. EVERY test suite SHALL be runnable in CI without network access; all external dependencies
   (NuGet feeds, Dart pub, .NET SDK) SHALL be pre-cached or stubbed.

---

### Requirement 2: Property-Based Testing Strategy

**User Story:** As a transpiler test engineer, I want a consistent PBT strategy applied to every
module, so that correctness properties are validated across a wide range of inputs rather than only
the cases a developer thought to write by hand.

#### Acceptance Criteria

1. EVERY module SHALL have at least one PBT suite that exercises the correctness properties defined
   in that module's requirements document.
2. PBT generators SHALL produce structurally valid inputs (e.g., well-formed IR trees, valid
   `transpiler.yaml` content, syntactically correct C# source) unless the property under test
   specifically concerns invalid-input handling.
3. EVERY PBT suite SHALL run a minimum of 100 distinct generated inputs per property per CI run;
   this count SHALL be configurable via an environment variable `PBT_RUNS` to allow deeper runs
   locally or in nightly builds.
4. WHEN a PBT property fails, the framework SHALL shrink the counterexample to the smallest failing
   input and report it alongside the seed value needed to reproduce the failure deterministically.
5. EVERY PBT failure SHALL be reproducible by re-running the test suite with the reported seed
   value; the seed SHALL be logged in the test output even for passing runs.
6. PBT generators for IR nodes SHALL respect all structural invariants defined in the IR_Validator
   (IR Requirement 14) so that generated inputs represent valid IR trees.
7. PBT generators for C# source SHALL use a grammar-based generator that produces syntactically
   valid C# programs; the generator SHALL be seeded and deterministic.

---

### Requirement 3: Determinism Properties

**User Story:** As a CI/CD pipeline operator, I want every module to be tested for deterministic
output, so that build caches, golden tests, and incremental builds remain stable.

#### Acceptance Criteria

1. EVERY module SHALL have a PBT property asserting that running the module twice on the same input
   produces identical output (determinism property).
2. The determinism property SHALL be tested with at least 50 distinct generated inputs per CI run.
3. WHEN a determinism property fails, the test output SHALL include a diff of the two outputs to
   identify the non-deterministic field.
4. Determinism tests SHALL explicitly verify that output does not contain timestamps, process IDs,
   random UUIDs, or other environment-dependent values.
5. The determinism property SHALL be tested across the following modules: Config_Service,
   Project_Loader, IR_Builder (IR Requirement 12), Dart_Generator (Dart_Generator Requirement 11),
   Namespace_Mapper (Namespace Requirement 7.5), Struct_Transpiler (Struct Requirement 12.2),
   Event_Transpiler (Event Requirement 10.2), and NuGet_Handler (NuGet Requirement 12.2).

---

### Requirement 4: Round-Trip Properties

**User Story:** As a transpiler developer, I want round-trip properties tested for every
serialization boundary in the pipeline, so that data is not silently corrupted when crossing
module boundaries.

#### Acceptance Criteria

1. THE IR serialization round-trip property (IR Requirement 16.3) SHALL be tested with a PBT suite
   that generates arbitrary valid IR trees, serializes them via the IR_Serializer, parses the
   output, and asserts structural equality with the original.
2. THE Config_Service round-trip property (Config Requirement 2.6) SHALL be tested with a PBT suite
   that generates arbitrary valid `transpiler.yaml` content, parses it, serializes the resulting
   Config_Object back to YAML, re-parses it, and asserts value-equality of the two Config_Objects.
3. EVERY round-trip test SHALL assert that the round-tripped value is value-equal to the original,
   not merely structurally similar.
4. Round-trip tests SHALL cover at minimum: IR trees containing every IR_Node type, Config_Objects
   with every Config_Section populated, and `pubspec.yaml` files produced by the NuGet_Handler.

---

### Requirement 5: Diagnostic Contract Testing

**User Story:** As a developer using the transpiler, I want every module's diagnostic output to be
tested, so that errors and warnings are always structured, stable, and actionable.

#### Acceptance Criteria

1. EVERY module SHALL have unit tests that assert the exact diagnostic code, severity, and message
   pattern for every documented error condition.
2. EVERY module SHALL have a PBT property asserting that no two diagnostics in a single run share
   the same source location and diagnostic code (no-duplicate-diagnostics property).
3. EVERY module SHALL have tests asserting that the `Success` flag on its result object is `true` if
   and only if the diagnostics list contains no `Error`-severity entry.
4. Diagnostic code ranges SHALL be tested to ensure no two modules emit diagnostics with the same
   prefix: `PL` (Project_Loader), `IR` (IR_Builder), `CG` (Dart_Generator), `NR` (NuGet_Handler),
   `VA` (Validation), `CFG` (Config_Service), `RC` (Result_Collector), `OR` (Pipeline_Orchestrator).
5. EVERY module SHALL have a test asserting that diagnostics are aggregated into the result object
   and NOT written to standard output or thrown as exceptions.

---

### Requirement 6: Coverage Requirements

**User Story:** As a transpiler maintainer, I want minimum code coverage thresholds enforced in CI,
so that untested code paths are surfaced before they reach production.

#### Acceptance Criteria

1. EVERY module SHALL achieve a minimum of 80% line coverage as measured by the project's coverage
   tool; this threshold SHALL be enforced as a CI gate.
2. EVERY module SHALL achieve a minimum of 75% branch coverage; this threshold SHALL be enforced as
   a CI gate.
3. Coverage reports SHALL be generated per-module and aggregated into a pipeline-wide report after
   every CI run.
4. Coverage thresholds SHALL be configurable per-module via a `coverage.yaml` file at the repository
   root; a module MAY raise its threshold above the minimum but SHALL NOT lower it below the minimum.
5. WHEN a pull request reduces coverage below the threshold for any module, CI SHALL fail and report
   the specific uncovered lines.
6. Coverage measurement SHALL include PBT-generated test paths; PBT runs SHALL be counted toward
   coverage metrics.

---

### Requirement 7: Test Fixture Management

**User Story:** As a test engineer, I want a shared library of C# and IR fixtures, so that tests
across modules use consistent, well-understood inputs rather than duplicating fixture code.

#### Acceptance Criteria

1. THE test suite SHALL maintain a `fixtures/` directory at the repository root containing:
   - `csharp/` — C# source files and `.csproj` files covering every supported language feature
   - `ir/` — serialized IR trees (JSON files produced by the IR_Serializer) for every fixture C# file
   - `dart/` — expected Dart output (golden files) for every fixture C# file
   - `configs/` — `transpiler.yaml` files covering every Config_Section and edge case
2. EVERY fixture SHALL be named descriptively (e.g., `async_method_with_cancellation_token.cs`) and
   accompanied by a one-line comment at the top of the file describing what feature it exercises.
3. WHEN a new C# language feature is added to the supported feature set, a corresponding fixture
   SHALL be added to `fixtures/csharp/` and its golden Dart output SHALL be added to `fixtures/dart/`
   before the feature is considered complete.
4. Fixtures SHALL be version-controlled and reviewed as part of the pull request that introduces or
   changes the feature they cover.
5. THE fixture library SHALL include at minimum one fixture for each of the following categories:
   classes, structs, interfaces, enums, generics, async/await, LINQ, events, delegates, namespaces,
   nullable reference types, exception handling, pattern matching, and NuGet package references.

---

### Requirement 8: Integration and End-to-End Test Contracts

**User Story:** As a pipeline integrator, I want integration and end-to-end tests to validate the
full data flow between stages, so that stage boundary contracts are not broken by independent module
changes.

#### Acceptance Criteria

1. EVERY integration test between adjacent stages SHALL assert that the output of the upstream stage
   is accepted without error by the downstream stage when the input is valid.
2. Integration tests SHALL cover the following stage pairs with at least 5 distinct fixture inputs
   each: (Config_Service → Project_Loader), (Project_Loader → IR_Builder),
   (IR_Builder → Dart_Generator), (NuGet_Handler → IR_Builder).
3. End-to-end tests SHALL cover at minimum the following scenarios:
   - A single `.csproj` with no NuGet dependencies
   - A `.sln` with two projects where one references the other
   - A `.csproj` with at least one Tier_1 NuGet dependency
   - A `.csproj` with at least one Tier_3 NuGet dependency (stub generation)
   - A `.csproj` with nullable reference types enabled
   - A `.csproj` with async methods and LINQ
4. EVERY end-to-end test SHALL assert that the generated Dart package passes `dart analyze` with
   zero errors.
5. WHEN an end-to-end test fails, the test output SHALL include the full `Diagnostics` list from
   `Gen_Result` to aid debugging.

---

### Requirement 9: Module-Specific Correctness Properties

**User Story:** As a test engineer, I want each module's correctness properties to be formally
enumerated and linked to their PBT implementations, so that the test suite provides evidence of
correctness for every documented invariant.

#### Acceptance Criteria

1. THE Config_Service test suite SHALL include PBT properties for: type safety (Config Requirement
   11.1), determinism (Config Requirement 11.2), default value correctness (Config Requirement 11.3),
   diagnostic determinism (Config Requirement 11.4), and clean config (Config Requirement 11.5).
2. THE Project_Loader test suite SHALL include PBT properties for: determinism under config
   (Project_Loader Requirement 9.5), diagnostic aggregation (Project_Loader Requirement 7), and
   `Success` flag correctness (Project_Loader Requirement 7.3).
3. THE IR_Builder test suite SHALL include PBT properties for: declaration count preservation
   (IR Requirement 16.1), determinism (IR Requirement 16.2), round-trip (IR Requirement 16.3),
   well-formedness (IR Requirement 16.4), return statement preservation (IR Requirement 16.5),
   type fidelity (IR Requirement 16.6), constant fidelity (IR Requirement 16.7), and partial
   merge attribute count preservation (IR Requirement 16.8).
4. THE Dart_Generator test suite SHALL include PBT properties for: determinism (Dart_Generator
   Requirement 14.1), file count preservation (Dart_Generator Requirement 14.2), declaration count
   preservation (Dart_Generator Requirement 14.3), async fidelity (Dart_Generator Requirement 14.4),
   nullability fidelity (Dart_Generator Requirement 14.5), and syntactic validity (Dart_Generator
   Requirement 14.6).
5. THE Namespace_Mapper test suite SHALL include PBT properties for: valid path output
   (Namespace Requirement 7.1), idempotence (Namespace Requirement 7.2), injectivity
   (Namespace Requirement 7.3), segment count preservation (Namespace Requirement 7.4),
   determinism (Namespace Requirement 7.5), case-insensitive equivalence (Namespace Requirement 7.6),
   and import deduplication (Namespace Requirement 7.7).
6. THE Struct_Transpiler test suite SHALL include PBT properties for: value equality round-trip
   (Struct Requirement 9.5) and determinism (Struct Requirement 12.2).
7. THE Event_Transpiler test suite SHALL include PBT properties for: well-formedness
   (Event Requirement 12.1), determinism (Event Requirement 12.2), one-to-one mapping
   (Event Requirement 12.3), subscription symmetry (Event Requirement 12.4), payload type fidelity
   (Event Requirement 12.5), and name uniqueness (Event Requirement 12.6).
8. THE NuGet_Handler test suite SHALL include PBT properties for: direct reference preservation
   (NuGet Requirement 12.1), determinism (NuGet Requirement 12.2), Tier_1 coverage
   (NuGet Requirement 12.3), Tier_3 stub completeness (NuGet Requirement 12.4), and no phantom
   dependencies (NuGet Requirement 12.6).

---

### Requirement 10: Test Infrastructure and Tooling

**User Story:** As a developer contributing to the transpiler, I want a consistent, well-documented
test infrastructure, so that writing and running tests is straightforward and the CI environment
mirrors the local development environment.

#### Acceptance Criteria

1. THE test suite SHALL use a single, project-wide test runner configured in the repository root;
   running `dotnet test` (or the language-equivalent command) from the root SHALL execute all unit,
   integration, and PBT tests.
2. THE PBT framework SHALL be configured with a default seed of `0` for CI runs to ensure
   reproducibility; developers MAY override the seed via the `PBT_SEED` environment variable.
3. THE test suite SHALL produce a JUnit-compatible XML report (or equivalent) for consumption by CI
   dashboards; the report SHALL include test name, duration, pass/fail status, and failure message.
4. EVERY test SHALL complete within 5 seconds in isolation; tests that require longer (e.g., full
   Roslyn compilation) SHALL be tagged `[Slow]` and excluded from the default fast-feedback test run.
5. THE test suite SHALL support parallel test execution; no test SHALL rely on shared mutable state,
   global singletons, or file system paths that conflict with other concurrently running tests.
6. THE CI pipeline SHALL run the full test suite (including slow tests) on every pull request
   targeting the main branch, and SHALL run only the fast test suite on every commit to feature
   branches.

---

### Requirement 11: Regression and Snapshot Testing

**User Story:** As a transpiler maintainer, I want regression tests that lock in the output for
known-good inputs, so that unintended changes to generated Dart code are caught immediately.

#### Acceptance Criteria

1. EVERY golden test SHALL store its reference output in a file under `fixtures/dart/` and SHALL
   fail with a clear diff when the SUT output diverges from the reference.
2. WHEN a golden test fails due to an intentional change (e.g., a formatting improvement), the
   developer SHALL update the reference file and include the diff in the pull request description.
3. THE golden test runner SHALL support an `--update-golden` flag that regenerates all reference
   files from the current SUT output, making it easy to batch-update after intentional changes.
4. Golden tests SHALL cover at minimum one fixture per supported C# language feature as enumerated
   in the top-level transpiler specification (Section 4).
5. WHEN a new C# feature is added to the supported set, a golden test SHALL be added in the same
   pull request; CI SHALL fail if a supported feature has no corresponding golden test.

---

### Requirement 12: Test Isolation and Fakes

**User Story:** As a test engineer, I want every module to be testable in isolation using fakes and
stubs, so that tests are fast, deterministic, and not dependent on external services.

#### Acceptance Criteria

1. EVERY module that depends on `IConfigService` SHALL be testable with a fake `IConfigService`
   implementation that returns configurable values; the fake SHALL be provided in the shared test
   utilities library.
2. EVERY module that performs file I/O SHALL accept an `IFileSystem` abstraction (or equivalent)
   that can be replaced with an in-memory fake in tests; no module SHALL call file system APIs
   directly in production code paths.
3. EVERY module that performs network I/O (e.g., NuGet_Handler querying feeds) SHALL accept an
   `IHttpClient` abstraction that can be replaced with a fake returning pre-recorded responses.
4. THE shared test utilities library SHALL provide: `FakeConfigService`, `FakeFileSystem`,
   `FakeHttpClient`, IR tree builders for every IR_Node type, and C# source generators for PBT.
5. WHEN a module test uses a fake, the fake SHALL be configured to return the minimum data needed
   for the test; tests SHALL NOT configure fakes with data unrelated to the property under test.

---

### Requirement 13: Performance Baselines

**User Story:** As a transpiler user, I want performance regression tests to catch slowdowns before
they reach production, so that the transpiler remains usable on large codebases.

#### Acceptance Criteria

1. THE test suite SHALL include a performance baseline test for each pipeline stage that measures
   wall-clock time for a standard fixture set (defined as the fixtures in `fixtures/csharp/`).
2. Performance baselines SHALL be recorded in a `perf_baselines.json` file at the repository root
   and updated when intentional performance improvements are made.
3. CI SHALL fail if any stage's measured time exceeds its baseline by more than 20% on three
   consecutive runs, triggering a performance regression alert.
4. Performance tests SHALL be tagged `[Perf]` and excluded from the default fast-feedback test run;
   they SHALL run nightly and on release branches.
5. THE performance test for the full end-to-end pipeline SHALL use a fixture set of at least 500
   lines of C# source to provide a meaningful signal.
