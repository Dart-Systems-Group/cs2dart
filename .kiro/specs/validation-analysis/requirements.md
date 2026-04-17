# Validation & Analysis — Requirements Document

## Introduction

The Validation & Analysis stage is the final stage of the cs2dart transpiler pipeline. It runs
after the Dart_Generator has written all generated files to disk and is responsible for two
distinct, unconditional operations:

1. **Formatting** — running `dart format` over every generated Dart source file to produce
   consistently styled output that matches Dart community conventions.
2. **Analysis** — running `dart analyze` and `dart pub get` over each generated Dart package as
   correctness assertions. Failures are not repaired; they are captured as `VA`-prefixed
   diagnostics and surfaced in the final `TranspilerResult`.

The stage also assembles the `TranspilerResult` — the single authoritative output of the entire
pipeline — by aggregating diagnostics from every upstream stage alongside its own findings.

### Design rationale

Because the entire C# project is loaded into memory and processed together (the IR_Builder
processes all `Project_Entry` items in topological order and the Dart_Generator has full
cross-file symbol information from the IR), cross-file type errors in the generated Dart output
should not occur if the upstream stages are correct. If `dart analyze` does report errors, that
is a signal of a bug in an upstream pipeline stage, not a condition the VA stage attempts to
repair. The VA stage observes, formats, and reports — it never patches or retries.

---

## Glossary

- **Validator**: The component described by this specification.
- **TranspilerResult**: The final output of the entire cs2dart pipeline. Contains `Packages`
  (list of `Output_Package`), `Diagnostics` (the complete aggregated diagnostic list from all
  pipeline stages), and `Success` (true when no `Error`-severity diagnostic is present across
  the entire pipeline run).
- **Output_Package**: The on-disk representation of one generated Dart package after formatting.
  Contains `ProjectName`, `OutputPath` (root directory on disk), `Files` (list of
  `Output_File`), and `PubspecYaml` (the written `pubspec.yaml` content).
- **Output_File**: A single formatted Dart source file on disk. Contains `AbsolutePath`,
  `RelativePath` (relative to the package root), and `FormattedContent` (the content after
  `dart format` has been applied).
- **Gen_Result**: The output of the Dart_Generator consumed by the Validator. Full schema defined
  in the Dart_Generator specification.
- **dart format**: The official Dart source code formatter (`dart format`), invoked as a
  subprocess or via its programmatic API. Always produces well-formed output for syntactically
  valid input.
- **dart analyze**: The official Dart static analyser (`dart analyze`), invoked as a subprocess.
  Reports type errors, missing imports, undefined identifiers, and style lint violations.
- **dart pub get**: The Dart package manager dependency resolution command, invoked as a
  subprocess. Verifies that all `pubspec.yaml` dependencies can be resolved from pub.dev or
  configured sources.
- **VA_Diagnostic**: A `Diagnostic` record emitted by the Validator using the reserved `VA`
  prefix (`VA0001`–`VA9999`). Wraps findings from `dart analyze` and `dart pub get` in the
  pipeline-wide diagnostic schema.
- **Diagnostic**: A pipeline-wide structured record. `Severity` (`Error`, `Warning`, `Info`),
  `Code` (string), `Message` (string), optional `Source` (file path), optional `Location`
  (`{ Line, Column }`). Full schema defined in the top-level transpiler specification.
- **IConfigService**: The configuration interface consumed by the Validator. Full schema defined
  in the Transpiler Configuration specification.

---

## Requirements

### Requirement 1: Pipeline Integration Contract

**User Story:** As a pipeline integrator, I want a well-defined input and output contract for the
Validator, so that the Dart_Generator and the final TranspilerResult can evolve independently.

#### Acceptance Criteria

1. THE Validator SHALL accept a `Gen_Result` and an `IFileSystem` instance as its inputs; it SHALL
   NOT re-invoke the Dart_Generator or any upstream stage.
2. THE Validator SHALL expose a single public entry point:
   `TranspilerResult Validate(Gen_Result genResult)` (or language-equivalent), with no mutable
   global state.
3. THE Validator SHALL process every `Dart_Package` in `Gen_Result.Packages` regardless of whether
   `Gen_Result.Success` is `true` or `false`; it SHALL NOT skip packages due to upstream errors.
4. THE Validator SHALL set `TranspilerResult.Success = true` if and only if
   `TranspilerResult.Diagnostics` contains no entry with `Severity = Error` across all upstream
   and VA diagnostics.
5. THE Validator SHALL propagate all diagnostics from `Gen_Result.Diagnostics` (which already
   contains the aggregated `CFG`, `PL`, `NR`, `RF`, `IR`, and `CG` diagnostics from upstream stages)
   into `TranspilerResult.Diagnostics` unchanged, so that `TranspilerResult` is the single
   authoritative diagnostic list for the entire pipeline run.
6. THE Validator SHALL complete the formatting pass before starting the analysis pass; all files
   written to disk SHALL be in their final formatted state before `dart analyze` is invoked.

---

### Requirement 2: File Writing

**User Story:** As a developer consuming transpiler output, I want generated files written to disk
before formatting and analysis run, so that the on-disk output is always the formatted, analyzed
version.

#### Acceptance Criteria

1. THE Validator SHALL write every `Gen_File.Content` from each `Dart_Package` to disk at the path
   derived from `Dart_Package.OutputPath` and `Gen_File.RelativePath` before invoking `dart format`.
2. THE Validator SHALL write `Dart_Package.PubspecYaml` to `<OutputPath>/pubspec.yaml` for each
   package before invoking `dart pub get`.
3. THE Validator SHALL create any intermediate directories required by the output path structure;
   it SHALL NOT fail if a directory already exists.
4. WHEN a file at the target path already exists, THE Validator SHALL overwrite it without error.
5. THE Validator SHALL use the `IFileSystem` abstraction for all file I/O so that the write step
   can be exercised in tests without touching the real file system.
6. WHEN a file write fails (e.g., permission denied, disk full), THE Validator SHALL emit a
   `VA`-prefixed `Error` diagnostic identifying the failed path and SHALL continue writing
   remaining files; it SHALL NOT abort the entire run.

---

### Requirement 3: Dart Formatting

**User Story:** As a developer consuming transpiler output, I want all generated Dart files
formatted according to `dart format` conventions, so that the output is immediately readable and
consistent without requiring a manual formatting step.

#### Acceptance Criteria

1. THE Validator SHALL invoke `dart format` on every `.dart` file written to disk under each
   `Dart_Package.OutputPath`, including files under `lib/`, `bin/`, and `test/`.
2. THE Validator SHALL invoke `dart format` with the `--fix` flag disabled; formatting SHALL apply
   style rules only, not semantic fixes.
3. WHEN `dart format` modifies a file, THE Validator SHALL update the corresponding
   `Output_File.FormattedContent` field with the post-format content so that
   `TranspilerResult.Packages` reflects the actual on-disk state.
4. THE Validator SHALL invoke `dart format` once per package (passing the package root directory)
   rather than once per file, to allow the formatter to apply consistent line-length decisions
   across the package.
5. WHEN `dart format` exits with a non-zero status for a file (indicating a syntax error that
   prevents formatting), THE Validator SHALL emit a `VA`-prefixed `Error` diagnostic identifying
   the file and the formatter error message, and SHALL continue formatting remaining files.
6. THE Validator SHALL NOT emit a diagnostic when `dart format` modifies a file; reformatting is
   expected and is not an error condition.
7. WHEN `IConfigService.experimentalFeatures` contains `validation.skip_format = true`, THE
   Validator SHALL skip the formatting pass and write files to disk without invoking `dart format`.

---

### Requirement 4: Dart Analysis

**User Story:** As a transpiler user, I want `dart analyze` run against every generated package so
that type errors, missing imports, and undefined identifiers in the generated code are surfaced as
actionable diagnostics rather than discovered later by the developer.

#### Acceptance Criteria

1. THE Validator SHALL invoke `dart analyze` on each `Output_Package.OutputPath` after the
   formatting pass has completed for that package.
2. THE Validator SHALL invoke `dart analyze --fatal-infos` so that all severity levels (errors,
   warnings, and infos) are captured; the exit code SHALL be used only to determine whether any
   findings were reported, not to set `TranspilerResult.Success` directly.
3. FOR EACH diagnostic reported by `dart analyze`, THE Validator SHALL emit a corresponding
   `VA`-prefixed `Diagnostic` with:
   - `Severity` mapped from the `dart analyze` severity (`error` → `Error`, `warning` → `Warning`,
     `info` → `Info`)
   - `Code` set to `VA` followed by a stable four-digit code derived from the `dart analyze`
     diagnostic code (e.g., Dart's `undefined_identifier` → `VA1001`)
   - `Message` set to the `dart analyze` message text verbatim
   - `Source` set to the absolute path of the offending generated file
   - `Location` set to the line and column reported by `dart analyze`
4. THE Validator SHALL NOT emit a `VA` `Error` diagnostic solely because `dart analyze` exits
   non-zero; it SHALL only emit diagnostics for individual findings reported in the analysis
   output.
5. WHEN `dart analyze` reports zero findings for a package, THE Validator SHALL emit a single
   `VA`-prefixed `Info` diagnostic confirming that the package passed analysis with zero findings.
6. WHEN `dart analyze` cannot be located on the host machine, THE Validator SHALL emit a
   `VA`-prefixed `Warning` diagnostic noting that analysis was skipped due to missing Dart SDK,
   and SHALL continue to the next step without failing the run.
7. WHEN `IConfigService.experimentalFeatures` contains `validation.skip_analyze = true`, THE
   Validator SHALL skip the analysis pass entirely and emit a `VA`-prefixed `Info` diagnostic
   noting the skip.

---

### Requirement 5: Dependency Resolution Verification

**User Story:** As a developer consuming transpiler output, I want `dart pub get` run against each
generated package so that missing or incompatible pub dependencies are caught before the developer
tries to build the package.

#### Acceptance Criteria

1. THE Validator SHALL invoke `dart pub get` in each `Output_Package.OutputPath` after the
   formatting pass has completed for that package.
2. WHEN `dart pub get` succeeds for a package, THE Validator SHALL emit a `VA`-prefixed `Info`
   diagnostic confirming successful dependency resolution for that package.
3. WHEN `dart pub get` fails for a package, THE Validator SHALL emit a `VA`-prefixed `Warning`
   diagnostic (not `Error`) identifying the package name and the pub error message; dependency
   resolution failure SHALL NOT set `TranspilerResult.Success = false` because the failure may
   be due to network unavailability rather than a transpiler bug.
4. THE Validator SHALL invoke `dart pub get --offline` when `IConfigService.experimentalFeatures`
   contains `validation.pub_offline = true`, to support air-gapped CI environments.
5. WHEN `dart pub get` cannot be located on the host machine, THE Validator SHALL emit a
   `VA`-prefixed `Info` diagnostic noting that dependency verification was skipped, and SHALL
   continue without failing the run.
6. WHEN `IConfigService.experimentalFeatures` contains `validation.skip_pub_get = true`, THE
   Validator SHALL skip the `dart pub get` step entirely.

---

### Requirement 6: TranspilerResult Assembly

**User Story:** As a developer or CI system consuming the transpiler, I want a single
`TranspilerResult` object that summarises the entire pipeline run, so that I can programmatically
inspect success, enumerate generated files, and read all diagnostics from one place.

#### Acceptance Criteria

1. THE Validator SHALL produce exactly one `TranspilerResult` per pipeline invocation, containing:
   - `Packages` — the list of `Output_Package` records, one per generated Dart package, in the
     same order as `Gen_Result.Packages`
   - `Diagnostics` — the complete ordered list of all diagnostics from all pipeline stages,
     ordered by stage (CFG → PL → NR → RF → IR → CG → VA) and within each stage by source file path
     and line number
   - `Success` — `true` if and only if `Diagnostics` contains no `Error`-severity entry
2. EACH `Output_Package` in `TranspilerResult.Packages` SHALL contain: `ProjectName`,
   `OutputPath`, `Files` (list of `Output_File` with `AbsolutePath`, `RelativePath`, and
   `FormattedContent`), and `PubspecYaml`.
3. THE Validator SHALL NOT omit any diagnostic from any upstream stage; every `Diagnostic` present
   in `Gen_Result.Diagnostics` SHALL appear in `TranspilerResult.Diagnostics`.
4. THE Validator SHALL NOT emit duplicate `VA` diagnostics for the same source file path,
   line/column, and diagnostic code within a single run.
5. WHEN `TranspilerResult.Success` is `false`, at least one `Diagnostic` in
   `TranspilerResult.Diagnostics` SHALL have `Severity = Error`.
6. WHEN `TranspilerResult.Success` is `true`, every `Diagnostic` in
   `TranspilerResult.Diagnostics` SHALL have `Severity` of `Warning` or `Info`.

---

### Requirement 7: Subprocess Execution Contract

**User Story:** As a pipeline integrator, I want the Validator to invoke Dart tooling through an
abstracted subprocess interface, so that the analysis and formatting steps can be tested without
requiring a real Dart SDK installation.

#### Acceptance Criteria

1. THE Validator SHALL invoke `dart format`, `dart analyze`, and `dart pub get` through an
   `IProcessRunner` abstraction (or language-equivalent) rather than calling the OS process API
   directly.
2. THE `IProcessRunner` interface SHALL expose at minimum: `Run(command, args, workingDirectory)`
   returning `(exitCode, stdout, stderr)`.
3. THE Validator SHALL be constructable with a fake `IProcessRunner` that returns pre-recorded
   `(exitCode, stdout, stderr)` tuples, enabling unit tests that exercise all analysis and
   formatting code paths without a Dart SDK.
4. THE Validator SHALL pass the absolute path of the package root as the working directory for
   all subprocess invocations.
5. WHEN a subprocess invocation times out (exceeding a configurable `VA_SUBPROCESS_TIMEOUT_SECONDS`
   environment variable, defaulting to 120 seconds), THE Validator SHALL emit a `VA`-prefixed
   `Warning` diagnostic identifying the timed-out command and SHALL continue processing remaining
   packages.

---

### Requirement 8: Diagnostics

**User Story:** As a transpiler user, I want all validation findings reported as structured
diagnostics, so that I can programmatically inspect them and integrate them into CI tooling.

#### Acceptance Criteria

1. THE Validator SHALL assign diagnostic codes in the range `VA0001`–`VA9999`; no other pipeline
   component SHALL use the `VA` prefix.
2. THE Validator SHALL maintain a stable mapping from `dart analyze` diagnostic codes to `VA`
   codes; this mapping SHALL be versioned alongside the transpiler so that CI systems can rely on
   stable `VA` codes across transpiler versions.
3. THE Validator SHALL NOT emit duplicate diagnostics for the same source path, line/column, and
   `VA` code within a single run.
4. THE Validator SHALL aggregate all `VA` diagnostics into `TranspilerResult.Diagnostics` rather
   than writing to standard output or throwing exceptions.
5. WHEN the Validator emits a `VA` `Error` diagnostic wrapping a `dart analyze` error, the
   `Diagnostic.Message` SHALL include both the original `dart analyze` message and the generated
   file path so that the developer can locate the problem without cross-referencing separate logs.

---

### Requirement 9: Configuration Service Integration

**User Story:** As a pipeline integrator, I want the Validator to receive all configuration values
through `IConfigService`, so that skip flags and timeout settings are applied consistently.

#### Acceptance Criteria

1. THE Validator SHALL accept an `IConfigService` instance at construction time and SHALL use it
   as the sole source of all configuration values.
2. THE Validator SHALL NOT read `transpiler.yaml` directly; all configuration access SHALL go
   through `IConfigService`.
3. WHEN `IConfigService.experimentalFeatures` contains `validation.skip_format = true`, THE
   Validator SHALL skip `dart format` as specified in Requirement 3.7.
4. WHEN `IConfigService.experimentalFeatures` contains `validation.skip_analyze = true`, THE
   Validator SHALL skip `dart analyze` as specified in Requirement 4.7.
5. WHEN `IConfigService.experimentalFeatures` contains `validation.skip_pub_get = true`, THE
   Validator SHALL skip `dart pub get` as specified in Requirement 5.6.
6. WHEN all `IConfigService` accessors return their Default_Values, THE Validator SHALL run the
   full format → analyze → pub-get sequence without error.

---

### Requirement 10: Correctness Properties for Testing

**User Story:** As a transpiler test engineer, I want well-defined correctness properties for the
Validator, so that I can write property-based tests that catch regressions.

#### Acceptance Criteria

1. FOR ALL `Gen_Result` inputs where every `Gen_File.Content` is syntactically valid Dart, THE
   Validator SHALL produce a `TranspilerResult` where every `Output_File.FormattedContent` is
   non-empty and parseable by the Dart parser (format completeness property).
2. FOR ALL `Gen_Result` inputs, `TranspilerResult.Diagnostics` SHALL contain every diagnostic
   present in `Gen_Result.Diagnostics` (upstream diagnostic preservation property).
3. FOR ALL `Gen_Result` inputs, `TranspilerResult.Success` SHALL be `false` whenever
   `Gen_Result.Success` is `false` (upstream failure propagation property).
4. FOR ALL `TranspilerResult` values, `TranspilerResult.Success = true` implies that
   `TranspilerResult.Diagnostics` contains no `Error`-severity entry (success consistency
   property).
5. FOR ALL `Gen_Result` inputs processed twice with identical `IProcessRunner` responses, THE
   Validator SHALL produce identical `TranspilerResult` values (determinism property).
6. FOR ALL `VA` diagnostic codes emitted, the code SHALL fall within the range `VA0001`–`VA9999`
   and SHALL NOT duplicate any code used by another pipeline stage (prefix exclusivity property).
