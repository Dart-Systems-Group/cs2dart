# Requirements Document

## Introduction

The C# Project Loader is the entry-point component of the cs2dart transpiler pipeline. It accepts a `.csproj` or `.sln` file, resolves all source files and NuGet package references, invokes the Roslyn compiler to produce a fully-typed semantic model, and emits a `Compilation` object that the `IR_Builder` consumes to begin code generation. The loader must handle multi-project solutions, transitive NuGet dependencies, and configuration-driven SDK resolution while producing actionable diagnostics for any inputs it cannot process.

## Glossary

- **Project_Loader**: The component described by this specification; responsible for loading C# projects and producing `Compilation` objects.
- **Compilation**: A Roslyn `Microsoft.CodeAnalysis.CSharp.CSharpCompilation` instance containing the full semantic model for one logical C# project.
- **IR_Builder**: The downstream component that consumes a `Load_Result` and produces the language-agnostic intermediate representation.
- **Solution**: A `.sln` file that groups one or more C# projects.
- **Project**: A single `.csproj` file representing one compilable unit.
- **NuGet_Resolver**: The sub-component responsible for locating and restoring NuGet package assemblies.
- **SDK_Resolver**: The sub-component responsible for locating the .NET SDK and its reference assemblies.
- **Diagnostic**: A pipeline-wide structured record emitted by any transpiler component. Every `Diagnostic` contains: `Severity` (one of `Error`, `Warning`, `Info`), `Code` (a string in the format `<prefix><4-digit-number>`, e.g. `PL0001`), `Message` (human-readable string), `Source` (optional file path), and `Location` (optional line and column numbers). Components use reserved code prefixes to avoid collisions: `PL` for Project_Loader, `IR` for IR_Builder, `CG` for code generator.
- **Dependency_Graph**: A directed acyclic graph of `Project_Entry` nodes representing inter-project dependencies, used to determine topological processing order.
- **Project_Entry**: A record within `Load_Result` representing one loaded project. Contains: `ProjectPath` (absolute path to the `.csproj` file), `ProjectName` (assembly name), `TargetFramework` (resolved TFM string, e.g. `net8.0`), `OutputKind` (one of `Exe`, `Library`, `WinExe`), `LangVersion` (resolved C# language version string), `NullableEnabled` (boolean), `Compilation` (the Roslyn `CSharpCompilation` for this project), `PackageReferences` (list of `{ PackageName, Version }` records for resolved NuGet packages), and `Diagnostics` (list of `Diagnostic` items scoped to this project).
- **Load_Result**: The complete output of the `Project_Loader`. Contains: `Projects` (ordered list of `Project_Entry` items in topological dependency order, leaf projects first), `DependencyGraph` (the full `Dependency_Graph`), `Diagnostics` (aggregated list of all `Diagnostic` items from all sub-components), `Success` (boolean, true when no `Diagnostic` of severity `Error` is present), and `Config` (the parsed `Mapping_Config`, or a default instance if no `transpiler.yaml` was found).
- **Mapping_Config**: An optional user-supplied configuration object parsed from `transpiler.yaml`. It may contain the following top-level keys: `sdk_path` (string, overrides SDK auto-detection), `nuget_feeds` (list of URLs, queried before `nuget.org`), `package_mappings` (map of NuGet package name to Dart package name), `linq_strategy` (one of `lower_to_loops` or `preserve_functional`, controls IR LINQ lowering), `naming_conventions` (object controlling identifier casing rules), `nullability` (object controlling nullable reference type handling), `async_behavior` (object controlling async/await mapping), and `experimental` (map of feature-flag strings to booleans).

---

## Requirements

### Requirement 1: Accept .csproj and .sln Input Files

**User Story:** As a transpiler pipeline, I want the `Project_Loader` to accept both `.csproj` and `.sln` files as entry points, so that I can load individual projects or entire solutions uniformly.

#### Acceptance Criteria

1. WHEN a valid `.csproj` file path is provided, THE `Project_Loader` SHALL parse the project file and produce a `Load_Result` whose `Projects` list contains exactly one `Project_Entry`.
2. WHEN a valid `.sln` file path is provided, THE `Project_Loader` SHALL parse the solution file and produce a `Load_Result` whose `Projects` list contains one `Project_Entry` per project defined in the solution.
3. IF the provided file path does not exist, THEN THE `Project_Loader` SHALL return a `Load_Result` with an empty `Projects` list, `Success = false`, and at least one `Diagnostic` of severity `Error` identifying the missing path.
4. IF the provided file has an extension other than `.csproj` or `.sln`, THEN THE `Project_Loader` SHALL return a `Load_Result` with an empty `Projects` list, `Success = false`, and at least one `Diagnostic` of severity `Error` describing the unsupported file type.
5. THE `Project_Loader` SHALL accept file paths as both absolute and relative paths, resolving relative paths against the current working directory.

---

### Requirement 2: Parse Project File Metadata

**User Story:** As a transpiler pipeline, I want the `Project_Loader` to extract all source files, target framework, and project references from a `.csproj` file, so that the `Compilation` reflects the complete project structure.

#### Acceptance Criteria

1. WHEN a `.csproj` file is parsed, THE `Project_Loader` SHALL enumerate all `<Compile>` and implicitly included `*.cs` source files relative to the project directory.
2. WHEN a `.csproj` file is parsed, THE `Project_Loader` SHALL extract the `<TargetFramework>` or `<TargetFrameworks>` value, select a single target framework, and record it in the `Project_Entry.TargetFramework` field.
3. WHEN a `.csproj` file specifies `<ProjectReference>` elements, THE `Project_Loader` SHALL resolve each referenced project and include its `Compilation` as a metadata reference in the referencing project's `Compilation`.
4. IF a `<ProjectReference>` path cannot be resolved, THEN THE `Project_Loader` SHALL emit a `Diagnostic` of severity `Error` identifying the unresolvable reference and continue loading remaining projects.
5. WHEN a `.csproj` file specifies `<Nullable>enable</Nullable>`, THE `Project_Loader` SHALL enable nullable reference type analysis in the resulting `Compilation` and set `Project_Entry.NullableEnabled = true`.

---

### Requirement 3: Resolve NuGet Package References

**User Story:** As a transpiler pipeline, I want the `Project_Loader` to resolve NuGet package assemblies, so that the `Compilation` includes all type information needed for semantic analysis.

#### Acceptance Criteria

1. WHEN a `.csproj` file contains `<PackageReference>` elements, THE `NuGet_Resolver` SHALL locate the corresponding assemblies in the local NuGet cache or restore them from the configured feed.
2. WHEN a package is successfully resolved, THE `Project_Loader` SHALL add the package's reference assemblies as `MetadataReference` entries in the `Compilation`.
3. IF a package cannot be resolved after exhausting all configured feeds, THEN THE `NuGet_Resolver` SHALL emit a `Diagnostic` of severity `Error` identifying the package name and version, and THE `Project_Loader` SHALL continue loading remaining references.
4. THE `NuGet_Resolver` SHALL resolve transitive dependencies and include their assemblies in the `Compilation`.
5. WHERE a `Mapping_Config` specifies a custom NuGet feed URL, THE `NuGet_Resolver` SHALL query that feed before falling back to `nuget.org`.

---

### Requirement 4: Resolve .NET SDK Reference Assemblies

**User Story:** As a transpiler pipeline, I want the `Project_Loader` to locate the correct .NET SDK reference assemblies for the target framework, so that the `Compilation` has access to all BCL types.

#### Acceptance Criteria

1. WHEN a target framework is determined, THE `SDK_Resolver` SHALL locate the matching .NET SDK reference assemblies on the host machine.
2. WHEN the SDK reference assemblies are located, THE `Project_Loader` SHALL add them as `MetadataReference` entries in the `Compilation`.
3. IF no matching SDK installation is found for the target framework, THEN THE `SDK_Resolver` SHALL emit a `Diagnostic` of severity `Error` identifying the missing SDK version.
4. WHERE a `Mapping_Config` specifies an explicit SDK path, THE `SDK_Resolver` SHALL use that path instead of auto-detecting the SDK.
5. WHEN multiple SDK versions satisfy the target framework, THE `SDK_Resolver` SHALL select the highest compatible version.

---

### Requirement 5: Build the Dependency Graph for Solutions

**User Story:** As a transpiler pipeline, I want the `Project_Loader` to determine the correct build order for multi-project solutions, so that project references are compiled before the projects that depend on them.

#### Acceptance Criteria

1. WHEN a `.sln` file is loaded, THE `Project_Loader` SHALL construct a `Dependency_Graph` from the inter-project references declared in each `.csproj` file.
2. WHEN the `Dependency_Graph` is constructed, THE `Project_Loader` SHALL populate `Load_Result.Projects` in topological order, leaf projects first, so that every `Project_Entry` appears after all projects it depends on.
3. IF the `Dependency_Graph` contains a cycle, THEN THE `Project_Loader` SHALL emit a `Diagnostic` of severity `Error` identifying all projects involved in the cycle and return a `Load_Result` with an empty `Projects` list and `Success = false`.
4. THE `Project_Loader` SHALL set `Load_Result.DependencyGraph` to the constructed `Dependency_Graph` so that the `IR_Builder` can traverse projects in dependency order without recomputing it.

---

### Requirement 6: Produce a Valid Compilation Object

**User Story:** As an IR_Builder, I want each `Compilation` in the `Load_Result` to be fully configured and semantically valid, so that I can query type symbols and syntax trees without additional setup.

#### Acceptance Criteria

1. THE `Project_Loader` SHALL produce each `Compilation` using `CSharpCompilation.Create` with all source syntax trees, metadata references, and compilation options derived from the project file, and store it in the corresponding `Project_Entry.Compilation` field.
2. WHEN a `Compilation` is produced, THE `Project_Loader` SHALL set `Project_Entry.OutputKind` to match the project's `<OutputType>` element (`Exe`, `Library`, or `WinExe`), defaulting to `Library` when the element is absent.
3. WHEN a `Compilation` is produced, THE `Project_Loader` SHALL set `Project_Entry.LangVersion` to match the `<LangVersion>` element in the project file, defaulting to `Latest` when the element is absent.
4. THE `Project_Loader` SHALL include all resolved source syntax trees in the `Compilation` such that `Compilation.SyntaxTrees.Count` equals the number of `.cs` files enumerated for the project.
5. WHEN the `Compilation` contains Roslyn `Diagnostic` entries of severity `Error`, THE `Project_Loader` SHALL propagate those diagnostics into both `Project_Entry.Diagnostics` and `Load_Result.Diagnostics`.

---

### Requirement 7: Emit Structured Diagnostics

**User Story:** As a developer using the transpiler, I want all loading errors and warnings to be reported as structured `Diagnostic` objects, so that I can programmatically inspect and display them.

#### Acceptance Criteria

1. THE `Project_Loader` SHALL represent every diagnostic as a `Diagnostic` record conforming to the pipeline-wide schema: `Severity` (`Error`, `Warning`, `Info`), `Code` (string), `Message` (string), optional `Source` (file path), and optional `Location` (line and column).
2. WHEN loading completes, `Load_Result.Diagnostics` SHALL contain the union of all `Diagnostic` objects emitted during loading, including those from the `NuGet_Resolver`, `SDK_Resolver`, and all `Project_Entry.Diagnostics` lists.
3. THE `Project_Loader` SHALL set `Load_Result.Success = true` if and only if `Load_Result.Diagnostics` contains no entry with `Severity = Error`.
4. THE `Project_Loader` SHALL assign diagnostic codes in the range `PL0001`–`PL9999`; no other pipeline component SHALL use the `PL` prefix.

---

### Requirement 9: Parse and Validate the Mapping Configuration

**User Story:** As a developer, I want the `Project_Loader` to read and validate the optional `transpiler.yaml` configuration file, so that custom SDK paths and NuGet feed overrides are applied before loading begins.

#### Acceptance Criteria

1. WHEN a `transpiler.yaml` file is present in the same directory as the entry-point `.csproj` or `.sln` file, THE `Project_Loader` SHALL parse it into a `Mapping_Config` object before beginning project loading and store it in `Load_Result.Config`.
2. WHEN a `transpiler.yaml` file is absent, THE `Project_Loader` SHALL populate `Load_Result.Config` with a default `Mapping_Config` instance (all fields at their documented defaults) and proceed without emitting a diagnostic.
3. IF the `transpiler.yaml` file is present but contains invalid YAML or unrecognized fields, THEN THE `Project_Loader` SHALL emit a `Diagnostic` of severity `Error` identifying the offending field or line, set `Load_Result.Success = false`, and halt loading.
4. FOR ALL valid `Mapping_Config` objects, parsing then serializing then parsing SHALL produce an equivalent `Mapping_Config` object (round-trip property).
