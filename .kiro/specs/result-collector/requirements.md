# Result Collector — Requirements Document

## Introduction

The Result Collector is a passive assembly stage that sits between the Validator and the final
`TranspilerResult` returned to the caller. It receives the completed `Gen_Result` (from the
`Dart_Generator`) and the full ordered diagnostic list (from the Validator), writes every
generated artifact to disk, and constructs the authoritative `TranspilerResult` record.

The Result Collector does **not** run `dart format`, `dart analyze`, or `dart pub get` — those
remain the responsibility of the Validation & Analysis stage. The Result Collector is invoked by
the Validator after all tooling has completed, receiving the final diagnostic list as input.

The Result Collector also owns the `dependency_report.md` write: the NuGet handler produces the
report content as a string and places it in `Gen_Result`; the Result Collector writes it to disk
and adds it to the file manifest.

---

## Glossary

- **Result_Collector**: The component described by this specification. Accepts `Gen_Result` and
  the final `Diagnostics` list; writes all artifacts to disk; returns `TranspilerResult`.
- **TranspilerResult**: The single authoritative output of the entire pipeline. Contains
  `Packages` (list of `Output_Package`), `Diagnostics` (complete ordered list from all stages),
  and `Success` (`true` when no `Error`-severity diagnostic is present).
- **Output_Package**: A record describing one fully-written Dart package on disk. Fields:
  `ProjectName` (string — original C# project name), `PackageName` (string — snake_case Dart
  package name), `OutputPath` (string — absolute path to the package root directory), and `Files`
  (list of strings — paths relative to `OutputPath` for every file written to disk in this
  package).
- **Gen_Result**: The output of the `Dart_Generator`. Contains `Packages` (list of
  `Dart_Package`), `Diagnostics`, and `Success`. Full schema defined in the Dart_Generator
  specification.
- **Dart_Package**: One entry in `Gen_Result.Packages`. Contains `ProjectName`, `PackageName`,
  `OutputPath` (absolute, resolved by the Orchestrator before the Validator runs), `Files` (list
  of `Gen_File`), `PubspecYaml` (string — generated `pubspec.yaml` content), and
  `DependencyReportContent` (nullable string — generated `dependency_report.md` content, produced
  by the NuGet handler and carried through the pipeline).
- **Gen_File**: A single in-memory generated Dart source file. Contains `RelativePath` (relative
  to the package `lib/` directory) and `Content` (Dart source text, already formatted by
  `dart format` when the Validator ran it).
- **RC_Diagnostic**: A `Diagnostic` record emitted by the Result Collector itself using the
  reserved `RC` prefix (`RC0001`–`RC9999`). Used for I/O errors encountered while writing
  artifacts to disk.
- **Diagnostic**: A pipeline-wide structured record. `Severity` (`Error`, `Warning`, `Info`),
  `Code` (string), `Message` (string), optional `Source` (file path), optional `Location`
  (`{ Line, Column }`). Full schema defined in the top-level transpiler specification.
- **File_Manifest**: The list of relative file paths recorded in `Output_Package.Files` for a
  single package. Populated incrementally as each artifact is written to disk.

---

## Requirements

### Requirement 1: Integration Contract

**User Story:** As a pipeline integrator, I want a well-defined input and output contract for the
Result Collector, so that the Validator and the Orchestrator can depend on it without coupling to
its internal file-writing logic.

#### Acceptance Criteria

1. THE Result_Collector SHALL expose a single public entry point:
   `TranspilerResult Collect(Gen_Result genResult, List<Diagnostic> finalDiagnostics)` (or
   language-equivalent), with no mutable global state.
2. THE Result_Collector SHALL accept `Gen_Result` as its primary input and SHALL NOT re-invoke
   any pipeline stage or re-read any source file.
3. THE Result_Collector SHALL accept `finalDiagnostics` as the complete, ordered diagnostic list
   assembled by the Validator; it SHALL NOT re-aggregate diagnostics from `Gen_Result.Diagnostics`
   independently.
4. THE Result_Collector SHALL be constructable via dependency injection, accepting a file-system
   abstraction so that disk writes can be replaced with in-memory fakes in tests.
5. THE Result_Collector SHALL set `TranspilerResult.Success = true` if and only if
   `finalDiagnostics` contains no entry with `Severity = Error`.
6. THE Result_Collector SHALL set `TranspilerResult.Diagnostics` to `finalDiagnostics` unchanged,
   appending any `RC`-prefixed diagnostics it emits during artifact writing after all existing
   entries.

---

### Requirement 2: Output_Package Schema

**User Story:** As a library consumer of `TranspilerResult`, I want each `Output_Package` to carry
a complete, typed description of what was written to disk, so that I can enumerate generated files
without scanning the filesystem.

#### Acceptance Criteria

1. FOR EACH `Dart_Package` in `Gen_Result.Packages`, THE Result_Collector SHALL produce exactly
   one `Output_Package` in `TranspilerResult.Packages`, in the same order.
2. THE `Output_Package.ProjectName` SHALL be set to `Dart_Package.ProjectName` unchanged.
3. THE `Output_Package.PackageName` SHALL be set to `Dart_Package.PackageName` (the snake_case
   Dart package name derived by the `Dart_Generator`).
4. THE `Output_Package.OutputPath` SHALL be set to `Dart_Package.OutputPath`, which is the
   absolute path resolved by the Orchestrator before the Validator ran; the Result_Collector SHALL
   NOT modify this path.
5. THE `Output_Package.Files` SHALL contain the relative path (relative to `OutputPath`) of every
   file successfully written to disk for that package, in the order they were written.
6. WHEN a file write fails, the failed file SHALL NOT be added to `Output_Package.Files`; an
   `RC`-prefixed `Error` diagnostic SHALL be emitted instead (see Requirement 5).

---

### Requirement 3: Artifact Writing

**User Story:** As a developer consuming transpiler output, I want every generated artifact written
to the correct location under the output directory, so that the resulting Dart package is
immediately usable without manual file placement.

#### Acceptance Criteria

1. FOR EACH `Gen_File` in `Dart_Package.Files`, THE Result_Collector SHALL write `Gen_File.Content`
   to `<OutputPath>/lib/<Gen_File.RelativePath>`, creating any intermediate directories as needed.
2. THE Result_Collector SHALL write `Dart_Package.PubspecYaml` to `<OutputPath>/pubspec.yaml`.
3. WHEN `Dart_Package.DependencyReportContent` is non-null, THE Result_Collector SHALL write it
   to `<OutputPath>/dependency_report.md`.
4. WHEN `Dart_Package.DependencyReportContent` is null (no NuGet packages were resolved), THE
   Result_Collector SHALL NOT write a `dependency_report.md` file and SHALL NOT add it to
   `Output_Package.Files`.
5. THE Result_Collector SHALL add the relative path of each successfully written file to
   `Output_Package.Files` immediately after the write completes, so that a partial failure leaves
   `Files` reflecting only what was actually written.
6. THE Result_Collector SHALL write files in the following deterministic order within each package:
   `pubspec.yaml` first, then `lib/` files in the order they appear in `Dart_Package.Files`, then
   `dependency_report.md` last (when present).
7. THE Result_Collector SHALL NOT overwrite a file that already exists at the target path with
   identical content; it SHALL skip the write and still add the path to `Output_Package.Files`.

---

### Requirement 4: File Manifest Contents

**User Story:** As a library consumer, I want `Output_Package.Files` to be a complete, accurate
manifest of every file in the package, so that I can verify output completeness without filesystem
access.

#### Acceptance Criteria

1. `Output_Package.Files` SHALL include `pubspec.yaml` as the first entry (relative path:
   `pubspec.yaml`).
2. `Output_Package.Files` SHALL include every `lib/` source file written from `Dart_Package.Files`
   (relative paths: `lib/<Gen_File.RelativePath>`).
3. WHEN `dependency_report.md` is written, `Output_Package.Files` SHALL include it as the last
   entry (relative path: `dependency_report.md`).
4. `Output_Package.Files` SHALL NOT include any file that was not written during the current
   `Collect` invocation (no phantom entries).
5. `Output_Package.Files` SHALL NOT contain duplicate entries for the same relative path.
6. THE Result_Collector SHALL NOT scan the output directory to discover pre-existing files; the
   manifest is built solely from writes performed in the current invocation.

---

### Requirement 5: I/O Error Handling

**User Story:** As a transpiler operator, I want I/O errors during artifact writing to be reported
as structured diagnostics rather than exceptions, so that the caller always receives a
`TranspilerResult` even when disk writes partially fail.

#### Acceptance Criteria

1. WHEN any file write fails (e.g., permission denied, disk full), THE Result_Collector SHALL
   catch the I/O error, emit an `RC`-prefixed `Error` diagnostic with `Code = RC0001`, a message
   containing the target file path and the underlying error message, and continue writing
   remaining files.
2. WHEN writing `pubspec.yaml` fails, THE Result_Collector SHALL emit `RC0001` and continue
   writing `lib/` files; the package SHALL still appear in `TranspilerResult.Packages` with a
   partial `Files` list.
3. WHEN creating an intermediate directory fails, THE Result_Collector SHALL emit `RC0001` for
   every file that cannot be written as a result, treating each as an individual write failure.
4. THE Result_Collector SHALL NOT throw exceptions to the caller; all errors SHALL be captured as
   `RC`-prefixed diagnostics and returned in `TranspilerResult.Diagnostics`.
5. WHEN one or more `RC0001` diagnostics are emitted, `TranspilerResult.Success` SHALL be `false`.
6. THE Result_Collector SHALL NOT emit duplicate `RC` diagnostics for the same file path within a
   single `Collect` invocation.

---

### Requirement 6: Determinism

**User Story:** As a CI/CD pipeline operator, I want the Result Collector to produce an identical
`TranspilerResult` for identical inputs on every run, so that golden-file tests and build caches
remain stable.

#### Acceptance Criteria

1. THE Result_Collector SHALL produce an identical `TranspilerResult` for identical `Gen_Result`
   and `finalDiagnostics` inputs regardless of execution environment, OS, or process ID.
2. THE Result_Collector SHALL write files in the fixed order defined in Requirement 3.6; it SHALL
   NOT vary write order based on filesystem state or OS scheduling.
3. THE Result_Collector SHALL NOT embed timestamps, process IDs, or environment-dependent values
   in any field of `TranspilerResult` or in any `RC`-prefixed diagnostic.
4. `Output_Package.Files` SHALL list entries in the same deterministic write order defined in
   Requirement 3.6, regardless of the order in which the OS completes the writes.
5. FOR ALL valid inputs, invoking `Collect` twice with the same `Gen_Result` and `finalDiagnostics`
   SHALL produce `TranspilerResult` values where `Success`, `Diagnostics`, and every
   `Output_Package.Files` list are identical (determinism property).

---

### Requirement 7: Diagnostic Code Reservation

**User Story:** As a transpiler maintainer, I want the `RC` diagnostic prefix reserved exclusively
for the Result Collector, so that diagnostic codes remain unambiguous across the pipeline.

#### Acceptance Criteria

1. THE Result_Collector SHALL assign all self-emitted diagnostic codes in the range
   `RC0001`–`RC9999`; no other pipeline component SHALL use the `RC` prefix.
2. THE Result_Collector SHALL NOT re-emit or rewrite diagnostics from `finalDiagnostics`; it SHALL
   only append new `RC`-prefixed entries.
3. FOR ALL `RC`-prefixed diagnostic codes emitted, each code SHALL appear at most once per file
   path per `Collect` invocation (no-duplicate-RC-diagnostics property).

---

### Requirement 8: Correctness Properties for Testing

**User Story:** As a transpiler test engineer, I want well-defined correctness properties for the
Result Collector, so that I can write property-based tests that catch regressions across a wide
range of `Gen_Result` inputs.

#### Acceptance Criteria

1. FOR ALL valid `Gen_Result` inputs with no I/O errors, the count of entries in
   `TranspilerResult.Packages` SHALL equal the count of `Dart_Package` entries in
   `Gen_Result.Packages` (package count preservation property).
2. FOR ALL `Output_Package` entries, the count of entries in `Output_Package.Files` SHALL equal
   the count of `Gen_File` entries in the corresponding `Dart_Package.Files`, plus one for
   `pubspec.yaml`, plus one when `DependencyReportContent` is non-null (file count property).
3. FOR ALL `TranspilerResult` values where `Success = true`, `TranspilerResult.Diagnostics` SHALL
   contain no `Error`-severity entry (success consistency property).
4. FOR ALL `TranspilerResult` values where `Success = false`, `TranspilerResult.Diagnostics` SHALL
   contain at least one `Error`-severity entry (failure consistency property).
5. FOR ALL valid inputs, invoking `Collect` twice SHALL produce `TranspilerResult` values where
   `Success`, the count of `Diagnostics`, and every `Output_Package.Files` list are identical
   (determinism property).
6. FOR ALL `Output_Package` entries, `Output_Package.Files` SHALL NOT contain duplicate relative
   paths (no-duplicate-files property).
7. FOR ALL `Output_Package` entries, `pubspec.yaml` SHALL appear as the first entry in
   `Output_Package.Files` when no I/O error occurred for that file (pubspec-first property).
