# Requirements Document

## Introduction

The C# Project Loader is the entry-point component of the cs2dart transpiler pipeline. It accepts a `.csproj` or `.sln` file, resolves all source files and NuGet package references, invokes the Roslyn compiler to produce a fully-typed semantic model, and emits a `Compilation` object that the `IR_Builder` consumes to begin code generation. The loader must handle multi-project solutions, transitive NuGet dependencies, and configuration-driven SDK resolution while producing actionable diagnostics for any inputs it cannot process.

## Glossary

- **Project_Loader**: The component described by this specification; responsible for loading C# projects and producing `Compilation` objects.
- **Compilation**: A Roslyn `Microsoft.CodeAnalysis.CSharp.CSharpCompilation` instance containing the full semantic model for one logical C# project.
- **IR_Builder**: The downstream component that consumes a `Compilation` object and produces the language-agnostic intermediate representation.
- **Solution**: A `.sln` file that groups one or more C# projects.
- **Project**: A single `.csproj` file representing one compilable unit.
- **NuGet_Resolver**: The sub-component responsible for locating and restoring NuGet package assemblies.
- **SDK_Resolver**: The sub-component responsible for locating the .NET SDK and its reference assemblies.
- **Diagnostic**: A structured message (error, warning, or info) produced by the `Project_Loader` describing a problem encountered during loading.
- **Dependency_Graph**: A directed acyclic graph of `Project` nodes and their inter-project and NuGet dependencies.
- **Load_Result**: The output of the `Project_Loader`; contains one `Compilation` per project and a list of `Diagnostic` items.
- **Mapping_Config**: An optional user-supplied configuration file (`transpiler.yaml`) that may override SDK paths, NuGet feed URLs, and package mappings.

---

## Requirements

### Requirement 1: Accept .csproj and .sln Input Files

**User Story:** As a transpiler pipeline, I want the `Project_Loader` to accept both `.csproj` and `.sln` files as entry points, so that I can load individual projects or entire solutions uniformly.

#### Acceptance Criteria

1. WHEN a valid `.csproj` file path is provided, THE `Project_Loader` SHALL parse the project file and produce a `Load_Result` containing exactly one `Compilation`.
2. WHEN a valid `.sln` file path is provided, THE `Project_Loader` SHALL parse the solution file and produce a `Load_Result` containing one `Compilation` per project defined in the solution.
3. IF the provided file path does not exist, THEN THE `Project_Loader` SHALL return a `Load_Result` with zero `Compilation` objects and at least one `Diagnostic` of severity `Error` identifying the missing path.
4. IF the provided file has an extension other than `.csproj` or `.sln`, THEN THE `Project_Loader` SHALL return a `Load_Result` with zero `Compilation` objects and at least one `Diagnostic` of severity `Error` describing the unsupported file type.
5. THE `Project_Loader` SHALL accept file paths as both absolute and relative paths, resolving relative paths against the current working directory.

---

### Requirement 2: Parse Project File Metadata

**User Story:** As a transpiler pipeline, I want the `Project_Loader` to extract all source files, target framework, and project references from a `.csproj` file, so that the `Compilation` reflects the complete project structure.

#### Acceptance Criteria

1. WHEN a `.csproj` file is parsed, THE `Project_Loader` SHALL enumerate all `<Compile>` and implicitly included `*.cs` source files relative to the project directory.
2. WHEN a `.csproj` file is parsed, THE `Project_Loader` SHALL extract the `<TargetFramework>` or `<TargetFrameworks>` value and select a single target framework for compilation.
3. WHEN a `.csproj` file specifies `<ProjectReference>` elements, THE `Project_Loader` SHALL resolve each referenced project and include its `Compilation` as a metadata reference in the referencing project's `Compilation`.
4. IF a `<ProjectReference>` path cannot be resolved, THEN THE `Project_Loader` SHALL emit a `Diagnostic` of severity `Error` identifying the unresolvable reference and continue loading remaining projects.
5. WHEN a `.csproj` file specifies `<Nullable>enable</Nullable>`, THE `Project_Loader` SHALL enable nullable reference type analysis in the resulting `Compilation`.

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
2. WHEN the `Dependency_Graph` is constructed, THE `Project_Loader` SHALL produce `Compilation` objects in topological order, leaf projects first.
3. IF the `Dependency_Graph` contains a cycle, THEN THE `Project_Loader` SHALL emit a `Diagnostic` of severity `Error` identifying all projects involved in the cycle and return a `Load_Result` with zero `Compilation` objects.
4. THE `Project_Loader` SHALL expose the `Dependency_Graph` as part of the `Load_Result` so that the `IR_Builder` can process projects in dependency order.

---

### Requirement 6: Produce a Valid Compilation Object

**User Story:** As an IR_Builder, I want each `Compilation` in the `Load_Result` to be fully configured and semantically valid, so that I can query type symbols and syntax trees without additional setup.

#### Acceptance Criteria

1. THE `Project_Loader` SHALL produce each `Compilation` using `CSharpCompilation.Create` with all source syntax trees, metadata references, and compilation options derived from the project file.
2. WHEN a `Compilation` is produced, THE `Project_Loader` SHALL set the `OutputKind` to match the project's `<OutputType>` element (`Exe`, `Library`, or `WinExe`).
3. WHEN a `Compilation` is produced, THE `Project_Loader` SHALL set the `LangVersion` to match the `<LangVersion>` element in the project file, defaulting to `Latest` when the element is absent.
4. THE `Project_Loader` SHALL include all resolved source syntax trees in the `Compilation` such that `Compilation.SyntaxTrees.Count` equals the number of `.cs` files enumerated for the project.
5. WHEN the `Compilation` contains Roslyn `Diagnostic` entries of severity `Error`, THE `Project_Loader` SHALL propagate those diagnostics into the `Load_Result` alongside the `Compilation`.

---

### Requirement 7: Emit Structured Diagnostics

**User Story:** As a developer using the transpiler, I want all loading errors and warnings to be reported as structured `Diagnostic` objects, so that I can programmatically inspect and display them.

#### Acceptance Criteria

1. THE `Project_Loader` SHALL represent every diagnostic as a `Diagnostic` record containing: severity (`Error`, `Warning`, `Info`), a unique diagnostic code, a human-readable message, and an optional source location (file path and line number).
2. WHEN loading completes, THE `Load_Result` SHALL contain the complete list of all `Diagnostic` objects emitted during loading, including those from the `NuGet_Resolver` and `SDK_Resolver`.
3. IF loading produces zero `Diagnostic` entries of severity `Error`, THE `Load_Result` SHALL be considered successful.
4. THE `Project_Loader` SHALL assign diagnostic codes in the range `PL0001`–`PL9999` to distinguish loader diagnostics from Roslyn compiler diagnostics.

---

### Requirement 9: Parse and Validate the Mapping Configuration

**User Story:** As a developer, I want the `Project_Loader` to read and validate the optional `transpiler.yaml` configuration file, so that custom SDK paths and NuGet feed overrides are applied before loading begins.

#### Acceptance Criteria

1. WHEN a `transpiler.yaml` file is present in the same directory as the entry-point `.csproj` or `.sln` file, THE `Project_Loader` SHALL parse it into a `Mapping_Config` object before beginning project loading.
2. WHEN a `transpiler.yaml` file is absent, THE `Project_Loader` SHALL proceed with default SDK and NuGet resolution without emitting a diagnostic.
3. IF the `transpiler.yaml` file is present but contains invalid YAML or unrecognized fields, THEN THE `Project_Loader` SHALL emit a `Diagnostic` of severity `Error` identifying the offending field or line and halt loading.
4. FOR ALL valid `Mapping_Config` objects, parsing then serializing then parsing SHALL produce an equivalent `Mapping_Config` object (round-trip property).
