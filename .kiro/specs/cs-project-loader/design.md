# C# Project Loader — Design Document

## Overview

The C# Project Loader (`Project_Loader`) is the entry-point stage of the cs2dart transpiler
pipeline. It accepts a `.csproj` or `.sln` file path, orchestrates all resolution sub-components,
and emits a `Load_Result` that the `Roslyn_Frontend` consumes.

Its responsibilities are:

1. **Input parsing** — parse `.csproj` and `.sln` files to discover source files, project
   references, and package references.
2. **NuGet resolution** — delegate to the `NuGet_Handler` to restore packages, classify them into
   tiers, and add their assemblies as `MetadataReference` entries in the `Compilation`.
3. **SDK resolution** — delegate to the `SDK_Resolver` to locate the correct .NET SDK reference
   assemblies for the target framework.
4. **Compilation construction** — build a `CSharpCompilation` per project using Roslyn's
   `CSharpCompilation.Create`, incorporating all source trees and metadata references.
5. **Dependency graph construction** — compute a topological ordering of projects for
   multi-project solutions.
6. **Diagnostic aggregation** — collect `PL`-prefixed diagnostics from its own logic plus
   `NR`-prefixed diagnostics from the `NuGet_Handler` and SDK diagnostics, and surface them in
   `Load_Result.Diagnostics`.

The `Project_Loader` is the only pipeline stage that interacts with the file system for project
and package resolution. All downstream stages operate on the `Load_Result` it produces.

---

## Architecture

### Pipeline Position

```
CLI / Orchestrator
        │
        ▼
 ┌─────────────────────────────────────────────────────────────┐
 │                     Project_Loader                          │
 │                                                             │
 │  ┌──────────────┐   ┌──────────────┐   ┌────────────────┐  │
 │  │ Input_Parser │   │ SDK_Resolver │   │ NuGet_Handler  │  │
 │  └──────┬───────┘   └──────┬───────┘   └───────┬────────┘  │
 │         │                  │                   │            │
 │         └──────────────────┴───────────────────┘            │
 │                            │                                │
 │                  ┌─────────▼──────────┐                     │
 │                  │ Compilation_Builder│                     │
 │                  └─────────┬──────────┘                     │
 │                            │                                │
 │                  ┌─────────▼──────────┐                     │
 │                  │  Load_Result       │                     │
 │                  └────────────────────┘                     │
 └─────────────────────────────────────────────────────────────┘
        │
        ▼
  Roslyn_Frontend
```

### Sub-Component Responsibilities

| Sub-Component | Responsibility | Diagnostic Prefix |
|---|---|---|
| `Input_Parser` | Parse `.csproj`/`.sln` XML; enumerate source files; extract metadata | `PL` |
| `SDK_Resolver` | Locate .NET SDK reference assemblies for the target framework | `PL` |
| `NuGet_Handler` | Restore packages, classify tiers, add assemblies to Compilation | `NR` |
| `Compilation_Builder` | Invoke `CSharpCompilation.Create`; wire all references | `PL` |
| `Dependency_Graph_Builder` | Compute topological order for multi-project solutions | `PL` |

The `NuGet_Handler` is an internal sub-component of the `Project_Loader`. The `Orchestrator`
never invokes it directly; all `NR`-prefixed diagnostics flow into `Load_Result.Diagnostics`.

---

## Components and Interfaces

### `IProjectLoader`

The public interface exposed to the `Orchestrator`:

```dart
abstract interface class IProjectLoader {
  /// Loads the project or solution at [inputPath] using [config] for all
  /// configuration values.
  ///
  /// Returns a [LoadResult] that is always non-null. [LoadResult.success]
  /// is false when any Error-severity diagnostic is present.
  Future<LoadResult> load(String inputPath, IConfigService config);
}
```

### `IInputParser`

Parses `.csproj` and `.sln` XML files:

```dart
abstract interface class IInputParser {
  /// Parses a .csproj file and returns a [ProjectFileData] containing
  /// source file globs, package references, project references, and metadata.
  ///
  /// Uses [XmlDocument.parse] from `package:xml` internally.
  /// Throws [MalformedCsprojException] on malformed XML or unexpected root element.
  Future<ProjectFileData> parseCsproj(String absolutePath);

  /// Parses a .sln file and returns the list of .csproj paths it references.
  /// Uses regex-based line matching; does not use `package:xml`.
  Future<List<String>> parseSln(String absolutePath);
}
```

### `ISdkResolver`

Locates .NET SDK reference assemblies:

```dart
abstract interface class ISdkResolver {
  /// Resolves the reference assembly paths for [targetFramework].
  ///
  /// Uses [sdkPath] when non-null; otherwise auto-detects the SDK.
  /// Returns a [SdkResolveResult] containing assembly paths and any diagnostics.
  Future<SdkResolveResult> resolve(String targetFramework, {String? sdkPath});
}
```

### `INuGetHandler`

Resolves and classifies NuGet packages:

```dart
abstract interface class INuGetHandler {
  /// Resolves all [packageReferences] for [targetFramework].
  ///
  /// Returns a [NuGetResolveResult] containing resolved assembly paths,
  /// tier classifications, Dart mappings, and NR-prefixed diagnostics.
  Future<NuGetResolveResult> resolve(
    List<PackageReferenceSpec> packageReferences,
    String targetFramework,
    IConfigService config,
  );
}
```

### `ICompilationBuilder`

Constructs the Roslyn `CSharpCompilation`:

```dart
abstract interface class ICompilationBuilder {
  /// Creates a [CSharpCompilation] from [sourceFiles], [metadataReferences],
  /// and [options] derived from the project metadata.
  CSharpCompilation build(
    String assemblyName,
    List<String> sourceFilePaths,
    List<MetadataReference> metadataReferences,
    CompilationOptions options,
  );
}
```

---

## Data Models

### `LoadResult`

The complete output of the `Project_Loader`:

```dart
final class LoadResult {
  /// Projects in topological dependency order (leaf projects first).
  /// Empty when Success is false and no projects could be loaded.
  final List<ProjectEntry> projects;

  /// The full dependency graph of inter-project references.
  final DependencyGraph dependencyGraph;

  /// Aggregated diagnostics from all sub-components (PL + NR prefixes).
  /// Ordered: PL diagnostics first, then NR diagnostics, within each group
  /// ordered by source file path then line number.
  final List<Diagnostic> diagnostics;

  /// True if and only if diagnostics contains no Error-severity entry.
  final bool success;

  /// The active Config_Object for this pipeline run. Never null;
  /// contains Default_Values when no transpiler.yaml was found.
  final ConfigObject config;
}
```

### `ProjectEntry`

One loaded C# project:

```dart
final class ProjectEntry {
  /// Absolute path to the .csproj file.
  final String projectPath;

  /// The assembly name (from AssemblyName or project file name).
  final String projectName;

  /// Resolved target framework moniker, e.g. "net8.0".
  final String targetFramework;

  /// Output kind derived from <OutputType>: Exe, Library, or WinExe.
  final OutputKind outputKind;

  /// Resolved C# language version string, e.g. "12.0". Defaults to "Latest".
  final String langVersion;

  /// True when <Nullable>enable</Nullable> is set in the project file.
  final bool nullableEnabled;

  /// The fully-configured Roslyn CSharpCompilation for this project.
  final CSharpCompilation compilation;

  /// Resolved NuGet package references with tier and Dart mapping annotations.
  final List<PackageReferenceEntry> packageReferences;

  /// Diagnostics scoped to this project (PL + NR + CS prefixes).
  final List<Diagnostic> diagnostics;
}
```

### `PackageReferenceEntry`

A resolved NuGet package reference with tier classification:

```dart
final class PackageReferenceEntry {
  /// NuGet package ID, e.g. "Newtonsoft.Json".
  final String packageName;

  /// Resolved version string, e.g. "13.0.3".
  final String version;

  /// Tier classification: 1 (mapped), 2 (transpiled), or 3 (stubbed).
  final int tier;

  /// Dart mapping record. Non-null for Tier 1 packages; null for Tier 2/3.
  final DartMapping? dartMapping;
}
```

### `DependencyGraph`

The inter-project dependency graph:

```dart
final class DependencyGraph {
  /// All project nodes, keyed by absolute .csproj path.
  final Map<String, DependencyNode> nodes;

  /// Directed edges: key depends on all values in the set.
  final Map<String, Set<String>> edges;
}

final class DependencyNode {
  final String projectPath;
  final String projectName;
  /// Direct project reference paths (absolute).
  final List<String> dependsOn;
}
```

### `Diagnostic`

Pipeline-wide diagnostic record (shared schema):

```dart
final class Diagnostic {
  final DiagnosticSeverity severity; // Error, Warning, Info
  final String code;                 // e.g. "PL0001", "NR0042"
  final String message;
  final String? source;              // file path, nullable
  final SourceLocation? location;    // line + column, nullable
}
```

### `ProjectFileData`

Intermediate data extracted from a `.csproj` file by `Input_Parser`:

```dart
final class ProjectFileData {
  final String absolutePath;
  final String? assemblyName;
  final String? targetFramework;
  final String? outputType;
  final String? langVersion;
  final bool nullableEnabled;
  final List<String> sourceGlobs;
  final List<String> projectReferencePaths;
  final List<PackageReferenceSpec> packageReferences;
}
```

---

## Processing Flow

### Single `.csproj` Input

```
1. Validate input path (exists, correct extension)
2. Input_Parser.parseCsproj(path) → ProjectFileData
3. Expand source globs → List<String> sourceFilePaths
4. SDK_Resolver.resolve(targetFramework) → SdkResolveResult
5. NuGet_Handler.resolve(packageReferences, targetFramework, config) → NuGetResolveResult
6. Compilation_Builder.build(assemblyName, sourceFilePaths,
     sdkAssemblies + nugetAssemblies, options) → CSharpCompilation
7. Collect Roslyn diagnostics from Compilation
8. Assemble ProjectEntry
9. Return LoadResult { projects: [entry], dependencyGraph: trivial, ... }
```

### `.sln` Input

```
1. Validate input path (exists, correct extension)
2. Input_Parser.parseSln(path) → List<String> csprojPaths
3. For each .csproj path: Input_Parser.parseCsproj → ProjectFileData
4. Dependency_Graph_Builder.build(allProjectData) → DependencyGraph
   - Detect cycles → emit PL Error if found, return empty Projects
5. Topological sort (leaf-first, alphabetical tie-breaking)
6. For each project in topological order:
   a. SDK_Resolver.resolve(targetFramework)
   b. NuGet_Handler.resolve(packageReferences, targetFramework, config)
   c. Compilation_Builder.build(..., projectRefMetadata from prior entries)
   d. Collect Roslyn diagnostics
   e. Assemble ProjectEntry
7. Return LoadResult { projects: orderedEntries, dependencyGraph, ... }
```

### Diagnostic Aggregation

All diagnostics are collected into a single `List<Diagnostic>` during processing:

- `PL`-prefixed: emitted by `Input_Parser`, `SDK_Resolver`, `Compilation_Builder`,
  `Dependency_Graph_Builder`, and the `Project_Loader` coordinator itself.
- `NR`-prefixed: emitted by `NuGet_Handler`; included unchanged.
- `CS`-prefixed: Roslyn compiler diagnostics propagated from each `Compilation`; included unchanged.

`Load_Result.Success` is set to `true` if and only if no `Error`-severity diagnostic is present
across all three prefixes.

---

## SDK Resolution Strategy

The `SDK_Resolver` uses the following resolution order:

1. If `IConfigService.sdkPath` is non-null, use that path directly.
2. Otherwise, probe standard SDK installation locations:
   - Windows: `%ProgramFiles%\dotnet\packs\Microsoft.NETCore.App.Ref\`
   - macOS/Linux: `/usr/local/share/dotnet/packs/Microsoft.NETCore.App.Ref/`
   - `DOTNET_ROOT` environment variable override
3. Among all SDK versions found, select the highest version that satisfies the target framework.
4. If no matching SDK is found, emit `PL`-prefixed `Error` diagnostic.

The SDK reference assemblies are the `.dll` files in the `ref/` subdirectory of the selected
SDK pack, not the runtime assemblies. This ensures the `Compilation` uses the stable public API
surface rather than implementation details.

---

## NuGet Handler Integration

The `NuGet_Handler` is invoked once per project during step 5 of the processing flow. It:

1. Reads `<PackageReference>` entries from `ProjectFileData`.
2. Resolves the full transitive dependency graph using the local NuGet cache or configured feeds.
3. Classifies each package as Tier 1, 2, or 3 using the `Mapping_Registry` and any
   `Mapping_Config` overrides from `IConfigService`.
4. For Tier 1 packages: adds the package's `.dll` assembly as a `MetadataReference`.
5. For Tier 2 packages: adds the package's C# source `SyntaxTree` objects to the `Compilation`.
6. For Tier 3 packages: does not add any reference; Roslyn binding errors will result in
   `UnresolvedSymbol` nodes in the IR.
7. Populates `PackageReferenceEntry.Tier` and `PackageReferenceEntry.DartMapping` for every
   resolved package.
8. Returns all `NR`-prefixed diagnostics in `NuGetResolveResult.diagnostics`.

The `Project_Loader` merges `NuGetResolveResult.diagnostics` into `Load_Result.Diagnostics`
unchanged (no renaming or renumbering of `NR` codes).

---

## Determinism Guarantees

The `Project_Loader` achieves determinism through the following rules:

1. **Source file enumeration**: `.cs` files are sorted alphabetically by absolute path before
   being added to the `Compilation`.
2. **Metadata reference ordering**: SDK assemblies are added first (sorted by file name), then
   NuGet assemblies (sorted by package ID then file name), then project reference assemblies
   (sorted by project path).
3. **Topological ordering**: when multiple valid topological orderings exist, ties are broken
   alphabetically by `ProjectPath`.
4. **Diagnostic ordering**: within each prefix group, diagnostics are sorted by source file path
   then line number then column.
5. **No environment-dependent data**: no timestamps, process IDs, or random values are embedded
   in any `Load_Result` field.

---

## Error Handling

### Input Validation Errors

| Condition | Diagnostic | Behavior |
|---|---|---|
| File path does not exist | `PL0001` Error | Return empty `Projects`, `Success = false` |
| File extension not `.csproj` or `.sln` | `PL0002` Error | Return empty `Projects`, `Success = false` |
| `.csproj` XML is malformed | `PL0003` Error | Skip project, continue with others |
| `.sln` file is malformed | `PL0004` Error | Return empty `Projects`, `Success = false` |

### Project Reference Errors

| Condition | Diagnostic | Behavior |
|---|---|---|
| `<ProjectReference>` path unresolvable | `PL0010` Error | Skip reference, continue loading |
| Dependency cycle detected | `PL0011` Error | Return empty `Projects`, `Success = false` |
| Missing `<TargetFramework>` element | `PL0012` Warning | Default to `net8.0`, continue |

### SDK Resolution Errors

| Condition | Diagnostic | Behavior |
|---|---|---|
| No SDK found for target framework | `PL0020` Error | Skip project, continue with others |
| Configured `sdkPath` does not exist | `PL0021` Error | Return empty `Projects`, `Success = false` |

### NuGet Resolution Errors

| Condition | Diagnostic | Behavior |
|---|---|---|
| Package not found in any feed | `NR`-prefixed Error | Skip package, continue loading |
| Version conflict unresolvable | `NR`-prefixed Error | Skip package, continue loading |
| Tier 1 assembly missing from cache | `NR`-prefixed Error | Downgrade to Tier 3, continue |

### Roslyn Compilation Errors

Roslyn `CS`-prefixed diagnostics from the `Compilation` are propagated into both
`Project_Entry.Diagnostics` and `Load_Result.Diagnostics` unchanged. They do not affect
`Load_Result.Success` directly — only `Error`-severity entries in `Load_Result.Diagnostics`
(regardless of prefix) set `Success = false`.

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a
system — essentially, a formal statement about what the system should do. Properties serve as the
bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Single-project load produces exactly one Project_Entry

*For any* valid `.csproj` file, loading it SHALL produce a `Load_Result` whose `Projects` list
contains exactly one `Project_Entry` with a `ProjectPath` equal to the resolved absolute path of
the input file.

**Validates: Requirements 1.1**

---

### Property 2: Solution load produces one Project_Entry per project

*For any* valid `.sln` file containing N project references, loading it SHALL produce a
`Load_Result` whose `Projects` list contains exactly N `Project_Entry` items (one per project
defined in the solution).

**Validates: Requirements 1.2**

---

### Property 3: Invalid input produces empty Projects and Error diagnostic

*For any* file path that does not exist or has an unsupported extension, loading it SHALL produce
a `Load_Result` where `Projects` is empty, `Success` is `false`, and `Diagnostics` contains at
least one `Error`-severity entry.

**Validates: Requirements 1.3, 1.4**

---

### Property 4: Source file count matches Compilation.SyntaxTrees count

*For any* valid `.csproj` file containing N `.cs` source files (after glob expansion), the
resulting `Project_Entry.Compilation.SyntaxTrees.Count` SHALL equal N.

**Validates: Requirements 2.1, 6.4**

---

### Property 5: Project metadata round-trip

*For any* valid `.csproj` file, the `TargetFramework`, `OutputKind`, `LangVersion`, and
`NullableEnabled` values written in the project file SHALL be faithfully reflected in the
corresponding fields of the resulting `Project_Entry`.

**Validates: Requirements 2.2, 2.5, 6.2, 6.3**

---

### Property 6: Topological ordering invariant

*For any* valid multi-project solution, the `Load_Result.Projects` list SHALL be ordered such
that for every `Project_Entry` at index `i`, none of the projects it depends on (directly or
transitively) appear at any index `j > i` in the list.

**Validates: Requirements 5.2, 8.2**

---

### Property 7: Cycle detection produces empty Projects and Error diagnostic

*For any* set of projects whose `<ProjectReference>` declarations form a cycle, loading the
solution SHALL produce a `Load_Result` where `Projects` is empty, `Success` is `false`, and
`Diagnostics` contains at least one `Error`-severity entry identifying the cycle.

**Validates: Requirements 5.3**

---

### Property 8: Success iff no Error-severity diagnostic

*For any* `Load_Result`, `Success` SHALL be `true` if and only if `Diagnostics` contains no
entry with `Severity == Error`.

**Validates: Requirements 7.3**

---

### Property 9: All diagnostics conform to the pipeline-wide schema

*For any* `Load_Result`, every `Diagnostic` in `Diagnostics` SHALL have a non-null `Severity`,
a non-null `Code` matching the pattern `[A-Z]+[0-9]{4}`, and a non-null `Message`.

**Validates: Requirements 7.1**

---

### Property 10: PL diagnostic codes are in range PL0001–PL9999

*For any* `Load_Result`, every `Diagnostic` whose `Code` starts with `"PL"` SHALL have a numeric
suffix in the range `[1, 9999]`.

**Validates: Requirements 7.4**

---

### Property 11: Determinism — identical inputs produce identical outputs

*For any* valid input path and `IConfigService` state, invoking `Load` twice SHALL produce
`Load_Result` values where `Success`, `Diagnostics.length`, and the set of
`Project_Entry.ProjectName` values are identical.

**Validates: Requirements 8.1, 8.4**

---

### Property 12: Load_Result.Config is value-equal to IConfigService.config

*For any* `IConfigService` instance, the `Config` field of the resulting `Load_Result` SHALL be
value-equal to the `ConfigObject` returned by `IConfigService.config` for the same run.

**Validates: Requirements 9.6**

---

### Property 13: PackageReferences entries have Tier and DartMapping populated

*For any* valid `.csproj` file with `<PackageReference>` elements, every entry in the resulting
`Project_Entry.PackageReferences` list SHALL have a `Tier` value of 1, 2, or 3, and a non-null
`DartMapping` if and only if `Tier == 1`.

**Validates: Requirements 3.1**

---

### Property 14: Roslyn Error diagnostics are propagated to both diagnostic lists

*For any* `.cs` source file containing Roslyn-detectable errors, the resulting `CS`-prefixed
diagnostics SHALL appear in both `Project_Entry.Diagnostics` and `Load_Result.Diagnostics`.

**Validates: Requirements 6.5**

---

## Testing Strategy

### Dual Testing Approach

The `Project_Loader` is tested with both unit/example-based tests and property-based tests.

**Unit tests** cover:
- Specific `.csproj` and `.sln` parsing examples with known expected outputs
- Error conditions with specific invalid inputs (missing file, bad extension, malformed XML)
- SDK resolution with a pinned SDK version
- NuGet resolution with a small set of known packages
- Integration between sub-components using real Roslyn APIs

**Property-based tests** cover:
- Universal invariants that hold across all valid inputs (Properties 1–14 above)
- Edge cases generated by the property framework (empty source lists, large project counts,
  deep dependency chains, etc.)

### Property-Based Testing Library

The property-based tests use [fast_check](https://fast-check.dev/) (via the Dart FFI bridge) or
the Dart-native [propcheck](https://pub.dev/packages/propcheck) package. Each property test runs
a minimum of **100 iterations**.

---

## XML Parsing

### Library

The `Input_Parser` uses [`package:xml`](https://pub.dev/packages/xml) for all `.csproj` XML
parsing. The hand-rolled `_XmlParser` / `_XmlElement` implementation is replaced by the
`XmlDocument.parse` DOM API provided by this package.

Add to `pubspec.yaml`:

```yaml
dependencies:
  xml: ^6.5.0
```

Import in `input_parser.dart`:

```dart
import 'package:xml/xml.dart';
```

### Parsing a `.csproj` file

```dart
final document = XmlDocument.parse(content); // throws XmlException on malformed input
final root = document.rootElement;           // the <Project> element
```

`XmlException` (from `package:xml`) is caught and re-thrown as `MalformedCsprojException`
with the original message forwarded as `details`.

### Querying elements

| Task | API |
|---|---|
| Find all `<PropertyGroup>` children | `root.findElements('PropertyGroup')` |
| Find all `<ItemGroup>` children | `root.findElements('ItemGroup')` |
| Read text content of a child element | `element.getElement('TargetFramework')?.innerText` |
| Read an attribute value | `element.getAttribute('Include')` |
| Find all `<PackageReference>` in an item group | `itemGroup.findElements('PackageReference')` |

### Error mapping

| `package:xml` condition | `InputParser` exception |
|---|---|
| `XmlException` thrown by `XmlDocument.parse` | `MalformedCsprojException(path, e.message)` |
| `rootElement` name ≠ `"Project"` (case-insensitive) | `MalformedCsprojException(path, 'Root element must be <Project>')` |
| Empty file content | `MalformedCsprojException(path, 'File is empty')` |

The `.sln` parser is unaffected — it uses regex-based line matching and does not use
`package:xml`.

Each property test is tagged with a comment referencing the design property:

```dart
// Feature: cs-project-loader, Property 8: Success iff no Error-severity diagnostic
test('success iff no error diagnostic', () async {
  await propcheck.forAll(
    arbitraryLoadResult(),
    (result) {
      expect(
        result.success,
        equals(result.diagnostics.every((d) => d.severity != DiagnosticSeverity.error)),
      );
    },
    numRuns: 100,
  );
});
```

### Test Doubles

All sub-components (`ISdkResolver`, `INuGetHandler`, `IInputParser`, `ICompilationBuilder`) are
injected via constructor injection, enabling full replacement with fakes in tests:

- **`FakeInputParser`**: returns `ProjectFileData` from in-memory fixtures without file I/O.
  Uses `XmlDocument.parse` from `package:xml` internally when parsing real fixture strings.
- **`FakeSdkResolver`**: returns a fixed set of assembly paths without probing the file system.
- **`FakeNuGetHandler`**: returns pre-classified `NuGetResolveResult` without network access.
- **`FakeCompilationBuilder`**: wraps real Roslyn `CSharpCompilation.Create` with in-memory
  source trees, or returns a stub `CSharpCompilation` for pure unit tests.

### Integration Tests

A small set of integration tests run against real `.csproj` files in the `test/fixtures/`
directory with a real .NET SDK installed:

- `test/fixtures/simple_console/` — single-project console app
- `test/fixtures/multi_project_solution/` — three-project solution with inter-project references
- `test/fixtures/nuget_packages/` — project with Tier 1, 2, and 3 NuGet packages
- `test/fixtures/nullable_enabled/` — project with `<Nullable>enable</Nullable>`

Integration tests verify end-to-end behavior including real SDK resolution and NuGet restore.
They are tagged `@Tags(['integration'])` and excluded from the default test run.
