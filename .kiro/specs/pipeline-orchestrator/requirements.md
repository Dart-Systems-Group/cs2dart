# Pipeline Orchestrator — Requirements Document

## Introduction

The Pipeline Orchestrator is the top-level coordination layer of the cs2dart transpiler. It is the
missing glue that wires all pipeline stages together in sequence, manages configuration
bootstrapping, enforces the early-exit policy, aggregates diagnostics across all stages, and
exposes both a programmatic API and a CLI entry point (`cs2dart`).

No individual pipeline stage knows about any other stage. The Orchestrator is the only component
that holds references to all stages and is responsible for invoking them in the correct order,
passing each stage's output as the next stage's input, and assembling the final `TranspilerResult`.

The Orchestrator also owns the `cs2dart` command-line interface: argument parsing, output directory
mapping, exit-code determination, and human-readable diagnostic formatting to stdout/stderr.

---

## Glossary

- **Orchestrator**: The component described by this specification; the top-level coordinator of the
  cs2dart transpiler pipeline.
- **TranspilerOptions**: A plain-data record that captures all runtime options for a single
  programmatic invocation of the Orchestrator. Fields: `InputPath` (string), `OutputDirectory`
  (string), `ConfigPath` (nullable string), `Verbose` (bool), `SkipFormat` (bool),
  `SkipAnalyze` (bool). Equivalent to the parsed CLI arguments.
- **TranspilerResult**: The final output of the entire pipeline, assembled by the Validator.
  Contains `Packages` (list of `Output_Package`), `Diagnostics` (complete ordered list from all
  stages), and `Success` (true when no `Error`-severity diagnostic is present). Full schema
  defined in the top-level transpiler specification.
- **Pipeline_Stage**: Any of the six ordered components invoked by the Orchestrator:
  `Config_Service`, `Project_Loader`, `Roslyn_Frontend`, `IR_Builder`, `Dart_Generator`,
  `Validator`. The NuGet dependency handler (`NR`-prefix) is integrated within the
  `Project_Loader` / `IR_Builder` boundary and is not a separate top-level invocation.
- **Early_Exit**: The condition under which the Orchestrator halts the pipeline before all stages
  have run, returning a partial `TranspilerResult` with `Success = false` and all diagnostics
  collected so far.
- **Short_Circuit_Threshold**: The severity level and stage combination that triggers an
  `Early_Exit`. Defined per-stage in Requirement 4.
- **OR_Diagnostic**: A `Diagnostic` record emitted by the Orchestrator itself using the reserved
  `OR` prefix (`OR0001`–`OR9999`). Used for orchestration-level errors (e.g., invalid CLI
  arguments, stage invocation failures, output directory errors).
- **Diagnostic**: A pipeline-wide structured record. `Severity` (`Error`, `Warning`, `Info`),
  `Code` (string), `Message` (string), optional `Source` (file path), optional `Location`
  (`{ Line, Column }`). Full schema defined in the top-level transpiler specification.
- **Config_Service**: The `IConfigService` implementation that parses and exposes `transpiler.yaml`.
  Full schema defined in the Transpiler Configuration specification.
- **Load_Result**: Output of `Project_Loader`. Full schema defined in the Project_Loader
  specification.
- **Frontend_Result**: Output of `Roslyn_Frontend`. Full schema defined in the Roslyn Frontend
  specification.
- **IR_Build_Result**: Output of `IR_Builder`. Full schema defined in the IR_Builder specification.
- **Gen_Result**: Output of `Dart_Generator`. Full schema defined in the Dart_Generator
  specification.
- **IConfigService**: The configuration interface. Full schema defined in the Transpiler
  Configuration specification.
- **NuGet_Handler**: The NuGet dependency resolution sub-component (`NR`-prefix diagnostics).
  Invoked by the `Project_Loader` during package reference resolution; its diagnostics flow into
  `Load_Result.Diagnostics` and are propagated through all subsequent stages.

---

## Requirements

### Requirement 1: Programmatic API

**User Story:** As a library consumer, I want to invoke the transpiler programmatically without
going through the CLI, so that I can embed cs2dart in build tools, IDE extensions, and test
harnesses.

#### Acceptance Criteria

1. THE Orchestrator SHALL expose a single public entry point:
   `TranspilerResult Transpile(string inputPath, TranspilerOptions options)` (or
   language-equivalent), with no mutable global state.
2. THE `TranspilerOptions` record SHALL carry: `InputPath` (string, path to `.csproj` or `.sln`),
   `OutputDirectory` (string, root directory for all generated Dart packages), `ConfigPath`
   (nullable string, explicit path to `transpiler.yaml`), `Verbose` (bool, default `false`),
   `SkipFormat` (bool, default `false`), `SkipAnalyze` (bool, default `false`).
3. THE Orchestrator SHALL be constructable via dependency injection, accepting factory or instance
   arguments for each Pipeline_Stage so that individual stages can be replaced with fakes in tests.
4. THE Orchestrator SHALL NOT use global or static mutable state; two concurrent calls to
   `Transpile` with different `TranspilerOptions` SHALL NOT interfere with each other.
5. WHEN `TranspilerOptions.InputPath` is null or empty, THE Orchestrator SHALL return a
   `TranspilerResult` with `Success = false` and an `OR`-prefixed `Error` diagnostic identifying
   the missing input path, without invoking any Pipeline_Stage.
6. WHEN `TranspilerOptions.OutputDirectory` is null or empty, THE Orchestrator SHALL return a
   `TranspilerResult` with `Success = false` and an `OR`-prefixed `Error` diagnostic identifying
   the missing output directory, without invoking any Pipeline_Stage.

---

### Requirement 2: Configuration Bootstrapping

**User Story:** As a pipeline integrator, I want the Orchestrator to initialize the Config_Service
before any other stage runs, so that all stages receive a fully-populated `IConfigService` instance
and no stage performs its own config file I/O.

#### Acceptance Criteria

1. THE Orchestrator SHALL initialize the `Config_Service` as the first action of every `Transpile`
   invocation, before constructing or invoking any other Pipeline_Stage.
2. WHEN `TranspilerOptions.ConfigPath` is non-null, THE Orchestrator SHALL pass that path to the
   `Config_Service` as the explicit config file path, bypassing directory search.
3. WHEN `TranspilerOptions.ConfigPath` is null, THE Orchestrator SHALL allow the `Config_Service`
   to perform its standard directory search starting from the directory containing
   `TranspilerOptions.InputPath`.
4. WHEN `TranspilerOptions.SkipFormat` is `true`, THE Orchestrator SHALL set the
   `validation.skip_format` experimental feature flag in the `IConfigService` instance passed to
   the Validator, overriding any value in `transpiler.yaml`.
5. WHEN `TranspilerOptions.SkipAnalyze` is `true`, THE Orchestrator SHALL set the
   `validation.skip_analyze` experimental feature flag in the `IConfigService` instance passed to
   the Validator, overriding any value in `transpiler.yaml`.
6. WHEN the `Config_Service` returns any `CFG`-prefixed `Error` diagnostic, THE Orchestrator SHALL
   perform an Early_Exit immediately, returning a `TranspilerResult` with `Success = false` and
   all `CFG` diagnostics included, without invoking any further Pipeline_Stage.
7. THE Orchestrator SHALL pass the same `IConfigService` instance to every Pipeline_Stage that
   accepts one; it SHALL NOT construct separate `IConfigService` instances per stage.

---

### Requirement 3: Pipeline Stage Wiring

**User Story:** As a pipeline integrator, I want the Orchestrator to invoke each stage in the
correct order and pass each stage's output directly as the next stage's input, so that the data
flow contract between stages is enforced in one place.

#### Acceptance Criteria

1. THE Orchestrator SHALL invoke Pipeline_Stages in the following fixed order:
   1. `Config_Service` initialization (produces `IConfigService`)
   2. `Project_Loader.Load(inputPath, IConfigService)` (produces `Load_Result`)
   3. `Roslyn_Frontend.Process(Load_Result)` (produces `Frontend_Result`)
   4. `IR_Builder.Build(Frontend_Result)` (produces `IR_Build_Result`)
   5. `Dart_Generator.Generate(IR_Build_Result)` (produces `Gen_Result`)
   6. `Validator.Validate(Gen_Result)` (produces `TranspilerResult`)
2. THE Orchestrator SHALL pass the `Load_Result` produced by `Project_Loader` directly to
   `Roslyn_Frontend.Process` without modification.
3. THE Orchestrator SHALL pass the `Frontend_Result` produced by `Roslyn_Frontend` directly to
   `IR_Builder.Build` without modification.
4. THE Orchestrator SHALL pass the `IR_Build_Result` produced by `IR_Builder` directly to
   `Dart_Generator.Generate` without modification.
5. THE Orchestrator SHALL pass the `Gen_Result` produced by `Dart_Generator` directly to
   `Validator.Validate` without modification.
6. THE Orchestrator SHALL NOT inspect, filter, or modify the diagnostic lists carried within any
   stage result before passing it to the next stage; diagnostic aggregation is the responsibility
   of each downstream stage as defined in their respective specifications.
7. THE Orchestrator SHALL apply the output directory mapping defined in Requirement 6 to the
   `Gen_Result` before passing it to the Validator, so that each `Dart_Package.OutputPath` is set
   to the correct subdirectory under `TranspilerOptions.OutputDirectory`.

---

### Requirement 4: Early-Exit and Short-Circuit Policy

**User Story:** As a transpiler user, I want the pipeline to stop early when a fatal upstream error
makes further processing meaningless, so that I receive fast feedback and avoid misleading
downstream diagnostics.

#### Acceptance Criteria

1. WHEN the `Config_Service` emits any `CFG`-prefixed `Error` diagnostic, THE Orchestrator SHALL
   perform an Early_Exit after configuration bootstrapping, before invoking `Project_Loader`.
2. WHEN `Load_Result.Success` is `false` AND `Load_Result.Projects` is empty (i.e., no project
   could be loaded at all), THE Orchestrator SHALL perform an Early_Exit after `Project_Loader`,
   returning a `TranspilerResult` with `Success = false` and all diagnostics collected so far.
3. WHEN `Load_Result.Success` is `false` AND `Load_Result.Projects` is non-empty (i.e., some
   projects loaded despite errors), THE Orchestrator SHALL NOT perform an Early_Exit; it SHALL
   continue to `Roslyn_Frontend`, allowing per-project error handling defined in the
   `Roslyn_Frontend` specification.
4. WHEN `Frontend_Result.Success` is `false` AND `Frontend_Result.Units` is empty, THE
   Orchestrator SHALL perform an Early_Exit after `Roslyn_Frontend`.
5. WHEN `Frontend_Result.Success` is `false` AND `Frontend_Result.Units` is non-empty, THE
   Orchestrator SHALL NOT perform an Early_Exit; it SHALL continue to `IR_Builder`.
6. WHEN `IR_Build_Result.Success` is `false` AND `IR_Build_Result.Units` is empty, THE
   Orchestrator SHALL perform an Early_Exit after `IR_Builder`.
7. WHEN `IR_Build_Result.Success` is `false` AND `IR_Build_Result.Units` is non-empty, THE
   Orchestrator SHALL NOT perform an Early_Exit; it SHALL continue to `Dart_Generator`.
8. WHEN `Gen_Result.Success` is `false` AND `Gen_Result.Packages` is empty, THE Orchestrator
   SHALL perform an Early_Exit after `Dart_Generator`.
9. WHEN `Gen_Result.Success` is `false` AND `Gen_Result.Packages` is non-empty, THE Orchestrator
   SHALL NOT perform an Early_Exit; it SHALL continue to `Validator`.
10. FOR ALL Early_Exit conditions, THE Orchestrator SHALL construct and return a `TranspilerResult`
    with: `Success = false`, `Packages = []`, and `Diagnostics` containing all diagnostics
    collected from every stage that ran, in stage order (CFG → PL → RF → IR → CG → NR → VA).
11. THE Orchestrator SHALL emit an `OR`-prefixed `Info` diagnostic identifying which stage
    triggered the Early_Exit and the reason (empty result set).

---

### Requirement 5: Diagnostic Aggregation

**User Story:** As a transpiler user, I want the final `TranspilerResult.Diagnostics` to contain
every diagnostic from every stage in a predictable order, so that I can programmatically inspect
the complete run history from a single object.

#### Acceptance Criteria

1. THE Orchestrator SHALL rely on each downstream stage to propagate upstream diagnostics; it SHALL
   NOT independently re-aggregate diagnostics from intermediate results, since each stage's output
   already carries the cumulative diagnostic list from all prior stages.
2. THE final `TranspilerResult.Diagnostics` (assembled by the Validator) SHALL contain diagnostics
   ordered by stage: CFG → PL → NR → RF → IR → CG → VA, and within each stage by source file
   path then line number.
3. WHEN an Early_Exit occurs, THE Orchestrator SHALL collect diagnostics from the last completed
   stage's result (which already contains all prior-stage diagnostics by the propagation contract)
   and include any `OR`-prefixed diagnostics it has emitted.
4. THE Orchestrator SHALL emit `OR`-prefixed diagnostics for orchestration-level errors (invalid
   arguments, output directory creation failures, unhandled stage exceptions) and include them in
   the returned `TranspilerResult.Diagnostics`.
5. THE Orchestrator SHALL NOT emit duplicate `OR` diagnostics for the same condition within a
   single `Transpile` invocation.
6. WHEN a Pipeline_Stage throws an unhandled exception, THE Orchestrator SHALL catch it, emit an
   `OR`-prefixed `Error` diagnostic with the exception message and stage name, perform an
   Early_Exit, and SHALL NOT propagate the exception to the caller.

---

### Requirement 6: Output Directory Management

**User Story:** As a developer consuming transpiler output, I want each generated Dart package
written to a predictable subdirectory under the `--output` directory, so that multi-project
solutions produce a clean, navigable output tree.

#### Acceptance Criteria

1. THE Orchestrator SHALL set each `Dart_Package.OutputPath` to
   `<TranspilerOptions.OutputDirectory>/<snake_case(ProjectName)>` before passing `Gen_Result` to
   the Validator, where `snake_case(ProjectName)` applies the same transformation used by the
   `Dart_Generator` to derive the Dart package name.
2. WHEN `TranspilerOptions.OutputDirectory` does not exist, THE Orchestrator SHALL create it
   (including any intermediate directories) before invoking the Validator.
3. WHEN creating the output directory fails (e.g., permission denied), THE Orchestrator SHALL emit
   an `OR`-prefixed `Error` diagnostic and perform an Early_Exit before invoking the Validator.
4. WHEN two projects in a solution produce the same `snake_case(ProjectName)` (a naming collision),
   THE Orchestrator SHALL disambiguate by appending a numeric suffix (`_2`, `_3`, etc.) to the
   conflicting package output directories and emit an `OR`-prefixed `Warning` diagnostic
   identifying the collision.
5. THE Orchestrator SHALL NOT delete or overwrite files in `TranspilerOptions.OutputDirectory`
   that were not produced by the current run; it SHALL only write files for packages produced in
   the current invocation.
6. THE Orchestrator SHALL pass the resolved absolute path of each `Dart_Package.OutputPath` to the
   Validator; relative paths SHALL be resolved against the current working directory before
   assignment.

---

### Requirement 7: CLI Entry Point

**User Story:** As a developer, I want a `cs2dart` command-line tool that accepts standard
arguments and flags, so that I can invoke the transpiler from a terminal or CI script without
writing code.

#### Acceptance Criteria

1. THE Orchestrator SHALL expose a `cs2dart` CLI entry point that accepts the following arguments
   and flags:
   - Positional argument (required): path to a `.csproj` or `.sln` file
   - `--output <dir>` (required): output directory for generated Dart packages
   - `--config <path>` (optional): explicit path to `transpiler.yaml`
   - `--verbose` / `-v` (optional flag): emit `Info`-severity diagnostics to stdout in addition
     to `Error` and `Warning` diagnostics; default: only `Error` and `Warning` are emitted
   - `--no-format` (optional flag): skip `dart format`; maps to `TranspilerOptions.SkipFormat`
   - `--no-analyze` (optional flag): skip `dart analyze`; maps to `TranspilerOptions.SkipAnalyze`
2. WHEN the positional argument is absent, THE CLI SHALL print a usage message to stderr and exit
   with a non-zero exit code without invoking the Orchestrator.
3. WHEN `--output` is absent, THE CLI SHALL print a usage message to stderr and exit with a
   non-zero exit code without invoking the Orchestrator.
4. WHEN an unrecognized flag is provided, THE CLI SHALL print an error message identifying the
   unknown flag to stderr and exit with a non-zero exit code without invoking the Orchestrator.
5. THE CLI SHALL translate the parsed arguments into a `TranspilerOptions` record and invoke
   `Orchestrator.Transpile(inputPath, options)`.
6. THE CLI SHALL exit with code `0` when `TranspilerResult.Success` is `true`.
7. THE CLI SHALL exit with a non-zero exit code when `TranspilerResult.Success` is `false` or when
   any `Error`-severity diagnostic is present in `TranspilerResult.Diagnostics`.
8. THE CLI SHALL print a `--help` / `-h` summary to stdout and exit with code `0` when the help
   flag is provided.

---

### Requirement 8: CLI Diagnostic Output Format

**User Story:** As a developer running `cs2dart` in a terminal or CI log, I want diagnostics
printed in a consistent, human-readable format that identifies severity, code, location, and
message, so that I can quickly locate and fix issues.

#### Acceptance Criteria

1. THE CLI SHALL print each `Error`-severity diagnostic to stderr in the following format:
   `error <CODE>: <MESSAGE> [<SOURCE>:<LINE>:<COLUMN>]`, omitting the location bracket when
   `Source` or `Location` is absent.
2. THE CLI SHALL print each `Warning`-severity diagnostic to stderr in the following format:
   `warning <CODE>: <MESSAGE> [<SOURCE>:<LINE>:<COLUMN>]`, omitting the location bracket when
   `Source` or `Location` is absent.
3. WHEN `--verbose` / `-v` is active, THE CLI SHALL print each `Info`-severity diagnostic to
   stdout in the following format: `info <CODE>: <MESSAGE> [<SOURCE>:<LINE>:<COLUMN>]`, omitting
   the location bracket when `Source` or `Location` is absent.
4. WHEN `--verbose` / `-v` is NOT active, THE CLI SHALL NOT print `Info`-severity diagnostics.
5. THE CLI SHALL print diagnostics in the same stage order as `TranspilerResult.Diagnostics`
   (CFG → PL → NR → RF → IR → CG → VA → OR).
6. WHEN `TranspilerResult.Success` is `true`, THE CLI SHALL print a summary line to stdout:
   `Transpilation succeeded. <N> package(s) written to <OutputDirectory>.`
7. WHEN `TranspilerResult.Success` is `false`, THE CLI SHALL print a summary line to stderr:
   `Transpilation failed with <E> error(s) and <W> warning(s).`
8. THE CLI SHALL NOT print any diagnostic or summary output to stdout when `--verbose` is not
   active and `TranspilerResult.Success` is `true` and there are no `Warning`-severity diagnostics,
   so that the tool is silent on clean runs (suitable for scripting).

---

### Requirement 9: NuGet Dependency Handler Integration

**User Story:** As a pipeline integrator, I want the NuGet dependency handler's role in the
pipeline clearly defined, so that its diagnostics are correctly attributed and its invocation point
is unambiguous.

#### Acceptance Criteria

1. THE Orchestrator SHALL treat the NuGet_Handler as an internal sub-component of the
   `Project_Loader` stage; the Orchestrator SHALL NOT invoke the NuGet_Handler directly.
2. THE NuGet_Handler SHALL be invoked by the `Project_Loader` during NuGet package reference
   resolution (as specified in the Project_Loader specification, Requirement 3).
3. ALL `NR`-prefixed diagnostics emitted by the NuGet_Handler SHALL flow into
   `Load_Result.Diagnostics` and be propagated through all subsequent stages unchanged, appearing
   in `TranspilerResult.Diagnostics` between the `PL`-prefixed and `RF`-prefixed diagnostics.
4. THE Orchestrator SHALL include `NR`-prefixed diagnostics in the Early_Exit diagnostic list when
   an Early_Exit occurs after `Project_Loader`.
5. WHEN the NuGet_Handler emits an `NR`-prefixed `Error` diagnostic, it SHALL be treated as a
   `Project_Loader`-level error for the purposes of the Early_Exit policy defined in Requirement 4.

---

### Requirement 10: Determinism

**User Story:** As a CI/CD pipeline operator, I want the Orchestrator to produce identical
`TranspilerResult` output for identical inputs on every run, so that build caches, golden-file
tests, and reproducible builds remain stable.

#### Acceptance Criteria

1. THE Orchestrator SHALL produce an identical `TranspilerResult` for identical `inputPath` and
   `TranspilerOptions` inputs regardless of execution environment, OS, process ID, or wall-clock
   time.
2. THE Orchestrator SHALL invoke each Pipeline_Stage in the fixed order defined in Requirement 3.1;
   it SHALL NOT reorder or parallelize stage invocations.
3. THE Orchestrator SHALL NOT embed timestamps, process IDs, random values, or other
   environment-dependent data in any field of `TranspilerResult` or in any `OR`-prefixed
   diagnostic.
4. THE Orchestrator SHALL NOT introduce any non-determinism in the output directory mapping
   defined in Requirement 6; the same `ProjectName` SHALL always map to the same output
   subdirectory name.
5. FOR ALL valid `inputPath` and `TranspilerOptions` inputs, invoking `Transpile` twice SHALL
   produce `TranspilerResult` values where `Success`, `Diagnostics`, and the set of
   `Output_Package.ProjectName` values are identical (determinism property).

---

### Requirement 11: Error Reporting for Unhandled Stage Failures

**User Story:** As a transpiler operator, I want the Orchestrator to catch and report unhandled
exceptions from any pipeline stage rather than crashing, so that the caller always receives a
structured `TranspilerResult` even in unexpected failure scenarios.

#### Acceptance Criteria

1. THE Orchestrator SHALL wrap each Pipeline_Stage invocation in an exception handler that catches
   all unhandled exceptions thrown by the stage.
2. WHEN a Pipeline_Stage throws an unhandled exception, THE Orchestrator SHALL emit an
   `OR`-prefixed `Error` diagnostic with: `Code = OR0001`, `Message` containing the stage name
   and the exception message, and no `Source` or `Location`.
3. WHEN a Pipeline_Stage throws an unhandled exception, THE Orchestrator SHALL perform an
   Early_Exit, returning a `TranspilerResult` with `Success = false` and all diagnostics collected
   up to and including the `OR0001` diagnostic.
4. THE Orchestrator SHALL NOT re-throw the caught exception; the caller SHALL always receive a
   `TranspilerResult`, never an exception propagated from a Pipeline_Stage.
5. WHEN the `Config_Service` initialization itself throws an unhandled exception, THE Orchestrator
   SHALL emit an `OR`-prefixed `Error` diagnostic and return a `TranspilerResult` with
   `Success = false` and `Packages = []`.

---

### Requirement 12: Correctness Properties for Testing

**User Story:** As a transpiler test engineer, I want well-defined correctness properties for the
Orchestrator, so that I can write property-based tests that catch regressions across a wide range
of inputs and stage configurations.

#### Acceptance Criteria

1. FOR ALL valid `inputPath` and `TranspilerOptions` inputs, invoking `Transpile` twice SHALL
   produce `TranspilerResult` values where `Success` and the count of `Diagnostics` are identical
   (determinism property).
2. FOR ALL `TranspilerResult` values where `Success = true`, `TranspilerResult.Diagnostics` SHALL
   contain no `Error`-severity entry (success consistency property).
3. FOR ALL `TranspilerResult` values where `Success = false`, `TranspilerResult.Diagnostics` SHALL
   contain at least one `Error`-severity entry (failure consistency property).
4. FOR ALL Early_Exit conditions, the returned `TranspilerResult.Packages` SHALL be empty
   (early-exit package invariant).
5. FOR ALL `TranspilerResult` values produced by a full pipeline run (no Early_Exit),
   `TranspilerResult.Packages` SHALL contain exactly one `Output_Package` per project in
   `Load_Result.Projects` that had no `Error`-severity diagnostics (package count property).
6. FOR ALL `OR`-prefixed diagnostic codes emitted, the code SHALL fall within the range
   `OR0001`–`OR9999` and SHALL NOT duplicate any code used by another pipeline stage (prefix
   exclusivity property).
7. FOR ALL `TranspilerOptions` inputs where `SkipFormat = true`, the returned `TranspilerResult`
   SHALL contain no `VA`-prefixed diagnostic with a message indicating `dart format` was invoked
   (skip-format propagation property).
8. FOR ALL `TranspilerOptions` inputs where `SkipAnalyze = true`, the returned `TranspilerResult`
   SHALL contain no `VA`-prefixed diagnostic with a message indicating `dart analyze` was invoked
   (skip-analyze propagation property).
9. FOR ALL inputs where `Config_Service` returns only `CFG`-prefixed `Error` diagnostics, the
   returned `TranspilerResult.Diagnostics` SHALL contain only `CFG`-prefixed and `OR`-prefixed
   entries (config-failure isolation property).
10. FOR ALL `TranspilerResult` values, every `OR`-prefixed diagnostic code SHALL appear at most
    once per `Transpile` invocation (no-duplicate-OR-diagnostics property).

