# Implementation Plan: Pipeline Orchestrator

## Overview

Implement the top-level `Orchestrator` class and its supporting components in Dart, wiring all
six pipeline stages together, enforcing the early-exit policy, managing output directory layout,
and exposing both a programmatic API and a `cs2dart` CLI entry point.

## Tasks

- [ ] 1. Define core data models and interfaces
  - Create `lib/src/orchestrator/models/transpiler_options.dart` with the immutable
    `TranspilerOptions` value class (fields: `inputPath`, `outputDirectory`, `configPath`,
    `verbose`, `skipFormat`, `skipAnalyze` with documented defaults)
  - Create `lib/src/orchestrator/models/transpiler_result.dart` with the `TranspilerResult`
    class (`success`, `packages`, `diagnostics`) if not already defined by the Result Collector
    spec; otherwise re-export it
  - Create `lib/src/orchestrator/interfaces/i_project_loader.dart`,
    `i_roslyn_frontend.dart`, `i_ir_builder.dart`, `i_dart_generator.dart`, `i_validator.dart`
    with the abstract interface definitions matching the design's stage interface signatures
  - Create `lib/src/orchestrator/interfaces/i_config_bootstrap.dart` with the
    `IConfigBootstrap` interface
  - _Requirements: 1.1, 1.2, 1.3, 3.1_

- [ ] 2. Implement `OverrideConfigService` and `ConfigBootstrap`
  - [ ] 2.1 Implement `OverrideConfigService` in
    `lib/src/orchestrator/override_config_service.dart`
    - Decorator around `IConfigService` that merges `_overrides` into `experimentalFeatures`
      while delegating all other getters to the wrapped instance
    - _Requirements: 2.4, 2.5, 2.7_

  - [ ]* 2.2 Write property test for `OverrideConfigService` — Property 9: SkipFormat/SkipAnalyze Propagation
    - **Property 9: SkipFormat / SkipAnalyze Propagation**
    - **Validates: Requirements 2.4, 2.5, 12.7, 12.8**

  - [ ] 2.3 Implement `ConfigBootstrap` in `lib/src/orchestrator/config_bootstrap.dart`
    - Thin wrapper around `bootstrapPipeline()` from `pipeline_bootstrap.dart` implementing
      `IConfigBootstrap`
    - _Requirements: 2.1, 2.2, 2.3_

  - [ ]* 2.4 Write unit tests for `ConfigBootstrap` and `OverrideConfigService`
    - Test that `OverrideConfigService` correctly merges overrides with base features
    - Test that `ConfigBootstrap` delegates to `bootstrapPipeline()` correctly
    - _Requirements: 2.1, 2.4, 2.5_

- [ ] 3. Implement `OutputPathAssigner`
  - [ ] 3.1 Implement `OutputPathAssigner` in
    `lib/src/orchestrator/output_path_assigner.dart`
    - Implement `static String toSnakeCase(String projectName)` following the six-step
      algorithm in the design (insert `_` before uppercase transitions, replace `.`/`-`/spaces,
      lowercase, collapse, strip)
    - Implement `GenResult assign(GenResult genResult, String outputDirectory)` that resolves
      absolute paths and applies collision disambiguation (`_2`, `_3`, … suffixes)
    - Emit `OR0006` `Warning` diagnostics for each collision group
    - _Requirements: 6.1, 6.4, 6.6_

  - [ ]* 3.2 Write property test for `toSnakeCase` — Property 10: Output Path Snake_Case Mapping
    - **Property 10: Output Path Snake_Case Mapping**
    - **Validates: Requirements 6.1, 10.4**

  - [ ]* 3.3 Write property test for collision disambiguation — Property 11: Collision Disambiguation Uniqueness
    - **Property 11: Collision Disambiguation Uniqueness**
    - **Validates: Requirements 6.4**

  - [ ]* 3.4 Write unit tests for `OutputPathAssigner`
    - Test `toSnakeCase` for representative patterns (`MyProject.Core`, `XMLParser`, etc.)
    - Test collision disambiguation produces `_2`, `_3` suffixes in correct order
    - Test absolute path resolution for relative `outputDirectory`
    - _Requirements: 6.1, 6.4, 6.6_

- [ ] 4. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. Implement `DiagnosticRenderer`
  - [ ] 5.1 Implement `DiagnosticRenderer` in
    `lib/src/orchestrator/diagnostic_renderer.dart`
    - Implement `static String format(Diagnostic d)` producing
      `<severity> <CODE>: <MESSAGE> [<SOURCE>:<LINE>:<COLUMN>]` with bracket omission rules
    - Implement `static void renderAll(TranspilerResult result, {required bool verbose})`
      following the stdout/stderr routing and summary line rules from the design
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8_

  - [ ]* 5.2 Write property test for `DiagnosticRenderer.format` — Property 12: Diagnostic Format Completeness
    - **Property 12: Diagnostic Format Completeness**
    - **Validates: Requirements 8.1–8.3**

  - [ ]* 5.3 Write unit tests for `DiagnosticRenderer`
    - Test `format` for each severity with and without `source`/`location`
    - Test `renderAll` summary line for success and failure cases
    - Test silent clean-run behavior (no output when `verbose=false`, `success=true`, no warnings)
    - _Requirements: 8.1, 8.2, 8.3, 8.6, 8.7, 8.8_

- [ ] 6. Implement `DirectoryManager`
  - Create `lib/src/orchestrator/directory_manager.dart` with a `DirectoryManager` class
  - Implement `Future<bool> ensureExists(String path)` that creates the directory (including
    intermediates) and returns `false` on failure
  - _Requirements: 6.2, 6.3_

- [ ] 7. Implement the `Orchestrator`
  - [ ] 7.1 Create `lib/src/orchestrator/orchestrator.dart` with the `Orchestrator` class
    - Constructor accepts all injected dependencies (`IProjectLoader`, `IRoslynFrontend`,
      `IIrBuilder`, `IDartGenerator`, `IValidator`, `IConfigBootstrap`, `OutputPathAssigner`,
      `DirectoryManager`)
    - _Requirements: 1.1, 1.3_

  - [ ] 7.2 Implement options validation in `transpile()`
    - Return early with `OR0002` when `inputPath` is empty
    - Return early with `OR0003` when `outputDirectory` is empty
    - No stage is invoked for invalid options
    - _Requirements: 1.5, 1.6_

  - [ ] 7.3 Implement config bootstrapping and override application in `transpile()`
    - Call `IConfigBootstrap.load()` first
    - Apply `OverrideConfigService` when `skipFormat` or `skipAnalyze` is true via
      `_applyOverrides()`
    - Early-exit with CFG diagnostics + `OR0005` when config has errors
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

  - [ ] 7.4 Implement stage wiring and early-exit logic in `transpile()`
    - Invoke stages in fixed order: `ProjectLoader` → `RoslynFrontend` → `IrBuilder` →
      `DartGenerator`
    - Apply early-exit check after each stage (`success=false AND empty collection`)
    - Emit `OR0005` Info diagnostic on each early exit identifying the triggering stage
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 4.1–4.11_

  - [ ] 7.5 Implement output path assignment and directory creation in `transpile()`
    - Call `OutputPathAssigner.assign()` after `DartGenerator`
    - Call `DirectoryManager.ensureExists()` and emit `OR0004` + early-exit on failure
    - Pass the updated `GenResult` to `Validator`
    - _Requirements: 3.7, 6.1, 6.2, 6.3, 6.5, 6.6_

  - [ ] 7.6 Implement exception wrapping for all stage calls
    - Wrap each stage invocation in `try/catch`
    - Emit `OR0001` Error diagnostic with stage name and exception message on any unhandled throw
    - Perform early-exit; never re-throw
    - _Requirements: 5.6, 11.1, 11.2, 11.3, 11.4, 11.5_

  - [ ]* 7.7 Write property test for determinism — Property 1: Determinism
    - **Property 1: Determinism**
    - **Validates: Requirements 10.5, 12.1**

  - [ ]* 7.8 Write property test for success consistency — Property 2: Success Consistency
    - **Property 2: Success Consistency**
    - **Validates: Requirements 12.2**

  - [ ]* 7.9 Write property test for failure consistency — Property 3: Failure Consistency
    - **Property 3: Failure Consistency**
    - **Validates: Requirements 12.3**

  - [ ]* 7.10 Write property test for invalid options — Property 4: Invalid Options Early Return
    - **Property 4: Invalid Options Early Return**
    - **Validates: Requirements 1.5, 1.6**

  - [ ]* 7.11 Write property test for early-exit invariant — Property 5: Early-Exit Invariant
    - **Property 5: Early-Exit Invariant**
    - **Validates: Requirements 4.1–4.11, 12.4**

  - [ ]* 7.12 Write property test for exception wrapping — Property 6: Exception Wrapping
    - **Property 6: Exception Wrapping**
    - **Validates: Requirements 5.6, 11.1–11.5**

  - [ ]* 7.13 Write property test for config-failure isolation — Property 7: Config-Failure Isolation
    - **Property 7: Config-Failure Isolation**
    - **Validates: Requirements 2.6, 12.9**

  - [ ]* 7.14 Write property test for no duplicate OR codes — Property 8: No Duplicate OR Codes
    - **Property 8: No Duplicate OR Codes**
    - **Validates: Requirements 5.5, 12.10**

  - [ ]* 7.15 Write property test for shared config instance — Property 13: Shared IConfigService Instance
    - **Property 13: Shared IConfigService Instance**
    - **Validates: Requirements 2.7**

- [ ] 8. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 9. Create stage fakes for testing
  - Create `test/orchestrator/fakes/fake_project_loader.dart`,
    `fake_roslyn_frontend.dart`, `fake_ir_builder.dart`, `fake_dart_generator.dart`,
    `fake_validator.dart`, `fake_config_bootstrap.dart`
  - Each fake records whether it was called and returns a pre-configured result
  - _Requirements: 1.3_

- [ ] 10. Write `Orchestrator` unit tests
  - [ ] 10.1 Write unit tests for `Orchestrator` in `test/orchestrator/orchestrator_test.dart`
    - Test `TranspilerOptions` field defaults
    - Test stage invocation order using call-recording fakes
    - Test `ConfigBootstrap` is called before any stage
    - Test each early-exit condition (one test per stage trigger)
    - Test `OR0001` emission and no re-throw on stage exception
    - Test `OR0002`/`OR0003` emission for empty `inputPath`/`outputDirectory`
    - Test `OR0004` emission when directory creation fails
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.1, 4.1–4.11, 5.6, 11.1–11.5_

  - [ ]* 10.2 Write integration test for full pipeline smoke test
    - All stages replaced by minimal fakes returning valid non-empty results
    - Verify `success=true` and `packages.length == projects.length`
    - Verify output directory is created when it does not exist
    - Verify `ConfigPath` override bypasses directory search
    - _Requirements: 2.2, 2.3, 6.2, 10.1–10.5_

- [ ] 11. Implement `OrchestratorFactory` and create `lib/src/orchestrator/orchestrator.dart` barrel export
  - Implement `OrchestratorFactory.create()` in
    `lib/src/orchestrator/orchestrator_factory.dart` wiring all production stage instances
  - Create `lib/src/orchestrator/orchestrator_exports.dart` (or update `lib/cs2dart.dart`) to
    export `Orchestrator`, `TranspilerOptions`, `TranspilerResult`
  - _Requirements: 1.1, 1.3_

- [ ] 12. Implement `CliRunner` and `bin/cs2dart.dart`
  - [ ] 12.1 Add the `args` package to `pubspec.yaml` if not already present
    - _Requirements: 7.1_

  - [ ] 12.2 Implement `CliRunner` in `lib/src/orchestrator/cli_runner.dart`
    - Build `ArgParser` with all flags/options from the design
    - Implement `Future<int> run(List<String> args)` following the parsing flow:
      handle `ArgParserException`, `--help`, missing positional, missing `--output`,
      construct `TranspilerOptions`, call `orchestrator.transpile()`, call
      `DiagnosticRenderer.renderAll()`, return exit code
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8_

  - [ ] 12.3 Create `bin/cs2dart.dart` entry point
    - Instantiate `OrchestratorFactory.create()`, wrap in `CliRunner`, call `run(args)`,
      pass result to `exit()`
    - _Requirements: 7.1_

  - [ ]* 12.4 Write unit tests for `CliRunner` in `test/orchestrator/cli_runner_test.dart`
    - Test `--help` / `-h` prints usage and exits `0`
    - Test missing positional argument exits `1`
    - Test missing `--output` exits `1`
    - Test unrecognized flag exits `1`
    - Test exit code `0` on `success=true`, `1` on `success=false`
    - _Requirements: 7.2, 7.3, 7.4, 7.6, 7.7, 7.8_

- [ ] 13. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties (Properties 1–13 from the design)
- Unit tests validate specific examples and edge cases
- The `args` package must be added to `pubspec.yaml` before implementing `CliRunner`
- Stage interfaces (`IRoslynFrontend`, `IIrBuilder`, `IDartGenerator`, `IValidator`) are stubs
  until those specs are implemented; the fakes in task 9 are sufficient for Orchestrator testing
