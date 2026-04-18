# Implementation Plan: C# Project Loader

## Overview

Implement the `Project_Loader` pipeline stage in Dart, building incrementally from data models
and interfaces through sub-component implementations to the top-level coordinator. Each task
wires into the previous, ending with a fully integrated `IProjectLoader` that the `Orchestrator`
can consume.

## Tasks

- [x] 1. Define data models and core interfaces
  - Create `lib/src/project_loader/models/` with all data model classes: `LoadResult`,
    `ProjectEntry`, `PackageReferenceEntry`, `DependencyGraph`, `DependencyNode`,
    `ProjectFileData`, `SdkResolveResult`, `NuGetResolveResult`, `PackageReferenceSpec`,
    `CompilationOptions`, `OutputKind` enum
  - Ensure `Diagnostic` and `DiagnosticSeverity` from the shared pipeline schema are imported
    (do not redefine them)
  - Create `lib/src/project_loader/interfaces/` with abstract interface classes:
    `IProjectLoader`, `IInputParser`, `ISdkResolver`, `INuGetHandler`, `ICompilationBuilder`
  - Export all public symbols from `lib/src/project_loader/project_loader.dart`
  - _Requirements: 1.1, 1.2, 2.2, 3.1, 5.1, 6.1, 7.1, 9.6_

- [x] 2. Implement `InputParser`
  - [x] 2.1 Implement `.csproj` XML parsing
    - Create `lib/src/project_loader/input_parser.dart` implementing `IInputParser`
    - Parse `<TargetFramework>` / `<TargetFrameworks>` (select first when multiple), `<AssemblyName>`,
      `<OutputType>`, `<LangVersion>`, `<Nullable>`, `<Compile>` includes/excludes,
      `<ProjectReference>`, and `<PackageReference>` elements
    - Expand implicit `**/*.cs` glob relative to the project directory; sort results
      alphabetically by absolute path
    - Emit `PL0003` Error on malformed XML
    - _Requirements: 2.1, 2.2, 2.5, 6.2, 6.3_

  - [x] 2.2 Implement `.sln` file parsing
    - Parse `Project(...)` lines in the `.sln` format to extract `.csproj` paths
    - Resolve each path relative to the `.sln` directory
    - Emit `PL0004` Error on malformed `.sln`
    - _Requirements: 1.2_

  - [ ]* 2.3 Write unit tests for `InputParser`
    - Test `.csproj` parsing with fixture files covering all metadata fields
    - Test glob expansion and alphabetical sorting of source files
    - Test `.sln` parsing with a multi-project fixture
    - Test `PL0003` and `PL0004` error emission on malformed inputs
    - _Requirements: 2.1, 2.2, 2.5, 6.2, 6.3_

- [x] 3. Implement `SdkResolver`
  - [x] 3.1 Implement SDK auto-detection and path resolution
    - Create `lib/src/project_loader/sdk_resolver.dart` implementing `ISdkResolver`
    - Probe `%ProgramFiles%\dotnet\packs\Microsoft.NETCore.App.Ref\` (Windows),
      `/usr/local/share/dotnet/packs/Microsoft.NETCore.App.Ref/` (macOS/Linux), and
      `DOTNET_ROOT` environment variable override
    - When `sdkPath` is non-null, use it directly; emit `PL0021` Error if it does not exist
    - Among found SDK versions, select the highest version satisfying the target framework
    - Return `.dll` files from the `ref/` subdirectory, sorted by file name
    - Emit `PL0020` Error when no matching SDK is found
    - _Requirements: 4.1, 4.3, 4.4, 4.5, 9.3_

  - [ ]* 3.2 Write unit tests for `SdkResolver`
    - Test config-supplied `sdkPath` is used when non-null
    - Test `PL0021` Error when configured path does not exist
    - Test `PL0020` Error when no SDK satisfies the target framework
    - Test highest-version selection when multiple SDKs are present
    - _Requirements: 4.3, 4.4, 4.5_

- [x] 4. Implement `NuGetHandler`
  - [x] 4.1 Implement package resolution and tier classification
    - Create `lib/src/project_loader/nuget_handler.dart` implementing `INuGetHandler`
    - Resolve packages from local NuGet cache; restore from configured feeds in order,
      falling back to `nuget.org`
    - Resolve transitive dependencies and include their assemblies
    - Classify each package as Tier 1, 2, or 3 using `MappingRegistry` and config overrides
    - For Tier 1: populate `DartMapping`; for Tier 2/3: set `dartMapping` to null
    - Emit `NR`-prefixed Error when a package cannot be resolved
    - Return `NuGetResolveResult` with assembly paths, `PackageReferenceEntry` list, and
      `NR`-prefixed diagnostics
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 9.4_

  - [ ]* 4.2 Write unit tests for `NuGetHandler`
    - Test Tier 1 package produces non-null `DartMapping` and assembly path
    - Test Tier 2/3 packages produce null `DartMapping`
    - Test `NR`-prefixed Error emitted when package not found
    - Test configured feed URLs are queried before `nuget.org`
    - Test transitive dependency assemblies are included
    - _Requirements: 3.1, 3.3, 3.4, 3.5_

- [x] 5. Implement `CompilationBuilder`
  - [x] 5.1 Implement Roslyn `CSharpCompilation` construction
    - Create `lib/src/project_loader/compilation_builder.dart` implementing `ICompilationBuilder`
    - Call `CSharpCompilation.Create` with assembly name, source syntax trees (parsed from
      source file paths), metadata references, and `CSharpCompilationOptions` derived from
      `CompilationOptions` (output kind, nullable context, language version)
    - Add metadata references in deterministic order: SDK assemblies first (sorted by file name),
      then NuGet assemblies (sorted by package ID then file name), then project reference
      assemblies (sorted by project path)
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 8.1_

  - [ ]* 5.2 Write unit tests for `CompilationBuilder`
    - Test `SyntaxTrees.Count` equals the number of source files provided
    - Test metadata reference ordering is deterministic
    - Test nullable context is set correctly when `nullableEnabled` is true/false
    - _Requirements: 6.1, 6.4_

- [x] 6. Implement `DependencyGraphBuilder`
  - [x] 6.1 Implement topological sort and cycle detection
    - Create `lib/src/project_loader/dependency_graph_builder.dart`
    - Build `DependencyGraph` from a list of `ProjectFileData` items
    - Perform topological sort (leaf-first); break ties alphabetically by `projectPath`
    - Detect cycles using DFS; emit `PL0011` Error listing all projects in the cycle
    - Return empty project list when a cycle is detected
    - _Requirements: 5.1, 5.2, 5.3, 8.2_

  - [ ]* 6.2 Write property test for topological ordering invariant
    - **Property 6: Topological ordering invariant**
    - **Validates: Requirements 5.2, 8.2**
    - For any valid multi-project DAG, every project appears after all its dependencies
    - _Requirements: 5.2, 8.2_

  - [ ]* 6.3 Write property test for cycle detection
    - **Property 7: Cycle detection produces empty Projects and Error diagnostic**
    - **Validates: Requirements 5.3**
    - For any project graph containing a cycle, result has empty projects and Error diagnostic
    - _Requirements: 5.3_

  - [ ]* 6.4 Write unit tests for `DependencyGraphBuilder`
    - Test single-project graph produces correct trivial `DependencyGraph`
    - Test three-project chain is sorted leaf-first
    - Test alphabetical tie-breaking when multiple valid orderings exist
    - Test `PL0011` Error is emitted for a two-project cycle
    - _Requirements: 5.1, 5.2, 5.3_

- [x] 7. Checkpoint — Ensure all sub-component tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Implement `ProjectLoader` coordinator
  - [x] 8.1 Implement single `.csproj` load flow
    - Create `lib/src/project_loader/project_loader_impl.dart` implementing `IProjectLoader`
    - Accept `IConfigService` at construction; store it as the sole config source
    - Validate input path: emit `PL0001` Error if file does not exist; emit `PL0002` Error if
      extension is not `.csproj` or `.sln`; resolve relative paths against CWD
    - For `.csproj`: call `IInputParser.parseCsproj`, expand globs, call `ISdkResolver.resolve`,
      call `INuGetHandler.resolve`, call `ICompilationBuilder.build`, collect Roslyn diagnostics,
      assemble `ProjectEntry`, return `LoadResult`
    - Store `IConfigService.config` in `LoadResult.config`
    - _Requirements: 1.1, 1.3, 1.4, 1.5, 2.1, 4.2, 6.1, 9.1, 9.2, 9.6_

  - [x] 8.2 Implement `.sln` load flow with dependency graph
    - For `.sln`: call `IInputParser.parseSln`, parse each `.csproj`, build `DependencyGraph`,
      topologically sort projects, load each project in order (passing prior project compilations
      as metadata references), assemble `LoadResult`
    - Emit `PL0010` Error for unresolvable `<ProjectReference>` paths; continue loading
    - Return empty `Projects` and `Success = false` when cycle detected
    - _Requirements: 1.2, 2.3, 2.4, 5.1, 5.2, 5.3, 5.4_

  - [x] 8.3 Implement diagnostic aggregation
    - Merge `PL`-prefixed, `NR`-prefixed, and `CS`-prefixed diagnostics into
      `LoadResult.diagnostics`; order: PL first, then NR, within each group sorted by source
      file path then line number then column
    - Propagate Roslyn `CS`-prefixed Error diagnostics into both `ProjectEntry.diagnostics`
      and `LoadResult.diagnostics`
    - Set `LoadResult.success = true` iff no Error-severity diagnostic is present
    - _Requirements: 6.5, 7.1, 7.2, 7.3, 7.4_

- [x] 9. Implement test doubles
  - Create `test/project_loader/fakes/fake_input_parser.dart` — returns `ProjectFileData` from
    in-memory fixtures
  - Create `test/project_loader/fakes/fake_sdk_resolver.dart` — returns a fixed set of assembly
    paths
  - Create `test/project_loader/fakes/fake_nuget_handler.dart` — returns pre-classified
    `NuGetResolveResult`
  - Create `test/project_loader/fakes/fake_compilation_builder.dart` — wraps real Roslyn
    `CSharpCompilation.Create` with in-memory source trees or returns a stub
  - _Requirements: (supports all testing tasks)_

- [x] 10. Write property-based tests for `ProjectLoader`
  - [ ]* 10.1 Write property test: single-project load produces exactly one `ProjectEntry`
    - **Property 1: Single-project load produces exactly one Project_Entry**
    - **Validates: Requirements 1.1**
    - _Requirements: 1.1_

  - [ ]* 10.2 Write property test: solution load produces one entry per project
    - **Property 2: Solution load produces one Project_Entry per project**
    - **Validates: Requirements 1.2**
    - _Requirements: 1.2_

  - [ ]* 10.3 Write property test: invalid input produces empty Projects and Error diagnostic
    - **Property 3: Invalid input produces empty Projects and Error diagnostic**
    - **Validates: Requirements 1.3, 1.4**
    - _Requirements: 1.3, 1.4_

  - [ ]* 10.4 Write property test: source file count matches `Compilation.SyntaxTrees` count
    - **Property 4: Source file count matches Compilation.SyntaxTrees count**
    - **Validates: Requirements 2.1, 6.4**
    - _Requirements: 2.1, 6.4_

  - [ ]* 10.5 Write property test: project metadata round-trip
    - **Property 5: Project metadata round-trip**
    - **Validates: Requirements 2.2, 2.5, 6.2, 6.3**
    - _Requirements: 2.2, 2.5, 6.2, 6.3_

  - [ ]* 10.6 Write property test: Success iff no Error-severity diagnostic
    - **Property 8: Success iff no Error-severity diagnostic**
    - **Validates: Requirements 7.3**
    - _Requirements: 7.3_

  - [ ]* 10.7 Write property test: all diagnostics conform to pipeline-wide schema
    - **Property 9: All diagnostics conform to the pipeline-wide schema**
    - **Validates: Requirements 7.1**
    - _Requirements: 7.1_

  - [ ]* 10.8 Write property test: PL diagnostic codes are in range PL0001–PL9999
    - **Property 10: PL diagnostic codes are in range PL0001–PL9999**
    - **Validates: Requirements 7.4**
    - _Requirements: 7.4_

  - [ ]* 10.9 Write property test: determinism — identical inputs produce identical outputs
    - **Property 11: Determinism — identical inputs produce identical outputs**
    - **Validates: Requirements 8.1, 8.4**
    - _Requirements: 8.1, 8.4_

  - [ ]* 10.10 Write property test: `LoadResult.config` is value-equal to `IConfigService.config`
    - **Property 12: Load_Result.Config is value-equal to IConfigService.config**
    - **Validates: Requirements 9.6**
    - _Requirements: 9.6_

  - [ ]* 10.11 Write property test: `PackageReferences` entries have Tier and DartMapping populated
    - **Property 13: PackageReferences entries have Tier and DartMapping populated**
    - **Validates: Requirements 3.1**
    - _Requirements: 3.1_

  - [ ]* 10.12 Write property test: Roslyn Error diagnostics propagated to both diagnostic lists
    - **Property 14: Roslyn Error diagnostics are propagated to both diagnostic lists**
    - **Validates: Requirements 6.5**
    - _Requirements: 6.5_

- [x] 11. Write integration tests
  - [ ]* 11.1 Write integration test: simple console project
    - Use `test/fixtures/simple_console/` fixture with a real .NET SDK
    - Verify single `ProjectEntry`, correct metadata, non-empty `SyntaxTrees`
    - Tag `@Tags(['integration'])`
    - _Requirements: 1.1, 2.1, 2.2, 6.1_

  - [ ]* 11.2 Write integration test: multi-project solution
    - Use `test/fixtures/multi_project_solution/` fixture (three projects with inter-project refs)
    - Verify topological ordering and `DependencyGraph` correctness
    - Tag `@Tags(['integration'])`
    - _Requirements: 1.2, 5.1, 5.2_

  - [ ]* 11.3 Write integration test: NuGet packages (Tier 1, 2, 3)
    - Use `test/fixtures/nuget_packages/` fixture
    - Verify `PackageReferenceEntry.tier` and `dartMapping` for each tier
    - Tag `@Tags(['integration'])`
    - _Requirements: 3.1, 3.2, 3.4_

  - [ ]* 11.4 Write integration test: nullable enabled project
    - Use `test/fixtures/nullable_enabled/` fixture
    - Verify `ProjectEntry.nullableEnabled == true` and nullable context in `Compilation`
    - Tag `@Tags(['integration'])`
    - _Requirements: 2.5, 6.1_

- [x] 12. Create integration test fixtures
  - Create `test/fixtures/simple_console/` — minimal single-project console app `.csproj`
  - Create `test/fixtures/multi_project_solution/` — three-project `.sln` with inter-project refs
  - Create `test/fixtures/nuget_packages/` — project referencing one Tier 1, one Tier 2, one
    Tier 3 package
  - Create `test/fixtures/nullable_enabled/` — project with `<Nullable>enable</Nullable>`
  - _Requirements: (supports integration tests)_

- [x] 13. Wire `ProjectLoader` into the pipeline bootstrap
  - Register `ProjectLoader` (with its sub-component dependencies) in
    `lib/src/pipeline_bootstrap.dart` so the `Orchestrator` can resolve `IProjectLoader`
  - Ensure `IConfigService` is injected at construction time
  - _Requirements: 9.1, 9.2_

- [x] 14. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass (excluding `@Tags(['integration'])` unless SDK is available), ask the
    user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties (Properties 1–14 from the design)
- Unit tests validate specific examples and edge cases
- Integration tests require a real .NET SDK and are excluded from the default test run
