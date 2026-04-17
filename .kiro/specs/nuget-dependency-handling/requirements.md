# NuGet Dependency Handling — Requirements

## Introduction

This document specifies the requirements for the **NuGet dependency handling** subsystem of the C# → Dart transpiler. The subsystem is responsible for resolving NuGet package references from `.csproj` and `.sln` files, classifying each package into a handling tier, mapping known packages to their Dart equivalents, optionally transpiling source-available packages, generating compatibility stubs for unsupported packages, and emitting the correct `pubspec.yaml` dependency entries in the output Dart package.

---

## Glossary

- **NuGet_Handler**: The transpiler subsystem responsible for resolving, classifying, and mapping NuGet package references.
- **Package_Reference**: A `<PackageReference>` element in a `.csproj` file, carrying a package ID and version constraint.
- **Package_Graph**: The directed acyclic graph of all direct and transitive NuGet dependencies resolved for a project.
- **Tier_1_Package**: A NuGet package with a built-in, maintained mapping to a Dart SDK library or a well-known pub.dev package (e.g., `Newtonsoft.Json` → `dart:convert`).
- **Tier_2_Package**: A NuGet package whose C# source is available (either bundled or downloadable) and can be transpiled by the C# → Dart pipeline.
- **Tier_3_Package**: A NuGet package with no known mapping and no available source; handled via stubs and diagnostics.
- **Dart_Mapping**: A record that associates a NuGet package ID and version range with a Dart package name, version constraint, and optional API surface shim.
- **Compatibility_Stub**: A generated Dart file that declares the public API surface of an unsupported NuGet package with `throw UnimplementedError()` bodies, allowing the project to compile while flagging missing implementations.
- **Mapping_Registry**: The built-in and user-extensible database of Tier_1 and Tier_2 Dart_Mappings, stored as YAML and versioned alongside the transpiler.
- **Mapping_Config**: The optional user-supplied configuration in `transpiler.yaml` that overrides or extends the Mapping_Registry.
- **pubspec.yaml**: The Dart package manifest file that lists Dart dependencies; the NuGet_Handler is responsible for populating its `dependencies` and `dev_dependencies` sections.
- **Version_Constraint**: A NuGet version range (e.g., `[1.2.0, 2.0.0)`) or Dart version constraint (e.g., `^1.2.0`) that restricts acceptable package versions.
- **Transitive_Dependency**: A package that is not directly referenced by the project but is required by one of its direct dependencies.
- **API_Shim**: A thin Dart wrapper that adapts a Dart package's API to match the shape of the original .NET API, reducing the number of call-site changes needed in transpiled code.
- **Result_Collector**: The downstream stage that receives `Dart_Package.DependencyReportContent`
  and writes it to disk as `dependency_report.md`. The NuGet_Handler produces the content;
  the Result_Collector owns the write. Full contract defined in the Result Collector specification.

---

## Requirements

### Requirement 1: Project File Parsing and Package Reference Extraction

**User Story:** As a developer migrating a .NET project, I want the transpiler to automatically discover all NuGet package references from my project files, so that I don't have to manually list dependencies for the Dart output.

#### Acceptance Criteria

1. THE NuGet_Handler SHALL parse `.csproj` files and extract all `<PackageReference>` elements, capturing the `Include` (package ID) and `Version` attributes.
2. THE NuGet_Handler SHALL parse `.sln` files and extract all referenced `.csproj` project paths, then process each project file individually.
3. WHEN a `.csproj` file uses `<PackageReference>` elements with `PrivateAssets="all"` or `ExcludeAssets` attributes, THE NuGet_Handler SHALL respect those attributes and exclude development-only packages from the runtime `dependencies` section of `pubspec.yaml`, placing them in `dev_dependencies` instead.
4. THE NuGet_Handler SHALL support `Directory.Packages.props` (Central Package Management) files; WHEN a `Directory.Packages.props` file is present, THE NuGet_Handler SHALL resolve version constraints from it rather than from individual `.csproj` files.
5. WHEN a package version is specified as a floating version (e.g., `1.2.*`), THE NuGet_Handler SHALL resolve it to the latest matching stable version available in the configured NuGet feed and record the resolved version in the output.
6. THE NuGet_Handler SHALL produce a deterministic Package_Graph: the same set of project files SHALL always produce the same resolved dependency list regardless of processing order.

---

### Requirement 2: Transitive Dependency Resolution

**User Story:** As a developer, I want the transpiler to resolve the full transitive closure of NuGet dependencies, so that all required packages are accounted for in the generated Dart project.

#### Acceptance Criteria

1. THE NuGet_Handler SHALL resolve the full transitive dependency graph for each project, not just direct `<PackageReference>` entries.
2. WHEN two packages in the graph require different version ranges of the same transitive dependency, THE NuGet_Handler SHALL apply NuGet's lowest-applicable-version resolution rule and record the resolved version.
3. WHEN a version conflict cannot be resolved (no version satisfies all constraints), THE NuGet_Handler SHALL emit a diagnostic error identifying the conflicting packages and their version requirements, and SHALL continue processing other dependencies.
4. THE NuGet_Handler SHALL deduplicate transitive dependencies: each package ID SHALL appear at most once in the resolved Package_Graph at its resolved version.
5. THE NuGet_Handler SHALL support offline resolution using a local NuGet cache; WHEN the cache is available, THE NuGet_Handler SHALL prefer it over network requests.
6. THE NuGet_Handler SHALL expose the resolved Package_Graph as a structured data structure (list of `{id, resolvedVersion, isDirect, tier}` records) for use by downstream pipeline stages.

---

### Requirement 3: Package Classification into Tiers

**User Story:** As a developer, I want each NuGet package to be automatically classified so that the transpiler applies the right handling strategy without requiring me to configure every package manually.

#### Acceptance Criteria

1. THE NuGet_Handler SHALL classify each resolved package as Tier_1, Tier_2, or Tier_3 by consulting the Mapping_Registry and any Mapping_Config overrides.
2. A package SHALL be classified as Tier_1 WHEN the Mapping_Registry contains a Dart_Mapping entry for its package ID and the resolved version falls within the mapping's version range.
3. A package SHALL be classified as Tier_2 WHEN no Tier_1 mapping exists but the package's source is available (either as a NuGet source package or via a configured source path) and the package is not explicitly excluded from transpilation in Mapping_Config.
4. A package SHALL be classified as Tier_3 WHEN neither Tier_1 nor Tier_2 conditions are met.
5. WHEN a Mapping_Config entry explicitly sets a package's tier, THE NuGet_Handler SHALL use that tier and SHALL NOT reclassify it.
6. THE NuGet_Handler SHALL emit a diagnostic info message for each package listing its resolved tier and the reason for classification.

---

### Requirement 4: Tier 1 — Known Package Mappings

**User Story:** As a developer, I want well-known NuGet packages to automatically map to their Dart equivalents, so that common dependencies like JSON serialization or HTTP clients are handled without any manual configuration.

#### Acceptance Criteria

1. THE NuGet_Handler SHALL include a built-in Mapping_Registry with Tier_1 entries for at minimum the following packages:

   | NuGet Package | Dart Equivalent |
   |---|---|
   | `System.*` (BCL) | `dart:core`, `dart:async`, `dart:collection`, `dart:convert`, `dart:math` |
   | `Newtonsoft.Json` | `dart:convert` + optional `json_serializable` |
   | `Microsoft.Extensions.Logging.Abstractions` | `logging` (pub.dev) |
   | `Microsoft.Extensions.DependencyInjection.Abstractions` | generated service locator stub |
   | `System.Text.Json` | `dart:convert` |
   | `System.Net.Http` | `dart:io` (`HttpClient`) |
   | `System.Collections.Immutable` | built-in Dart immutable collections |
   | `System.Reactive` (Rx.NET) | `rxdart` (pub.dev) |
   | `FluentValidation` | generated validation stub |

   > **`System.Text.Json` classification note:** `System.Text.Json` is inbox BCL on `net5.0`+ but a standalone NuGet package on `netstandard2.x` and `net4x`. The NuGet_Handler SHALL apply TFM-conditional classification:
   > - WHEN `Project_Entry.TargetFramework` is `net5.0` or later AND no explicit `<PackageReference>` for `System.Text.Json` is present in the project file, THE NuGet_Handler SHALL synthesize a virtual Tier_1 BCL entry (mapping to `dart:convert`) without adding a `pubspec.yaml` dependency entry, since `dart:convert` is always available.
   > - WHEN `Project_Entry.TargetFramework` is `netstandard2.x`, `net4x`, or any pre-`net5.0` TFM, OR when an explicit `<PackageReference>` for `System.Text.Json` is present regardless of TFM, THE NuGet_Handler SHALL classify it as a regular Tier_1 NuGet package via the Mapping_Registry and add the `dart:convert` mapping to `pubspec.yaml` as normal.
   > This ensures `System.Text.Json` never appears in both the BCL synthetic path and the NuGet package path simultaneously for the same project.

2. WHEN a Tier_1 package is resolved, THE NuGet_Handler SHALL add the corresponding Dart package and version constraint to the `dependencies` section of `pubspec.yaml`.
3. WHEN a Tier_1 mapping includes an API_Shim, THE NuGet_Handler SHALL emit the shim Dart file into `lib/src/shims/` and add the necessary `import` statements to transpiled files that reference the mapped package's types.
4. WHEN a Tier_1 package version falls outside the mapping's supported version range, THE NuGet_Handler SHALL emit a diagnostic warning and apply the mapping anyway, noting the version mismatch.
5. THE NuGet_Handler SHALL allow Tier_1 mappings to be overridden or extended via the `nuget_mappings` key in `transpiler.yaml`.

---

### Requirement 5: Tier 2 — Source Transpilation

**User Story:** As a developer, I want NuGet packages whose source code is available to be automatically transpiled alongside my project, so that I get a complete Dart output without manually porting third-party libraries.

#### Acceptance Criteria

1. WHEN a package is classified as Tier_2, THE NuGet_Handler SHALL locate the package's C# source (from a `.nupkg` source package, a configured local path, or a NuGet symbol server) and pass it to the main transpiler pipeline as an additional compilation unit.
2. THE NuGet_Handler SHALL emit the transpiled Dart output for a Tier_2 package into `lib/src/packages/<package_id>/` within the output Dart package.
3. WHEN a Tier_2 package itself has NuGet dependencies, THE NuGet_Handler SHALL recursively classify and handle those transitive dependencies using the same tier rules.
4. WHEN a Tier_2 package source cannot be located, THE NuGet_Handler SHALL downgrade it to Tier_3, emit a diagnostic warning, and generate a Compatibility_Stub instead.
5. THE NuGet_Handler SHALL NOT re-transpile a Tier_2 package if a cached transpiled output already exists for the same package ID and resolved version; it SHALL reuse the cached output.
6. WHEN a Tier_2 package contains platform-specific code (e.g., P/Invoke, `unsafe` blocks, `DllImport`), THE NuGet_Handler SHALL emit a diagnostic error for each unsupported construct and substitute `UnsupportedNode` placeholders, continuing transpilation of the remaining package source.

---

### Requirement 6: Tier 3 — Unsupported Package Stubs

**User Story:** As a developer, I want unsupported NuGet packages to produce Dart stub files that let my project compile, so that I can identify and manually implement the missing pieces without the entire build failing.

#### Acceptance Criteria

1. WHEN a package is classified as Tier_3, THE NuGet_Handler SHALL generate a Compatibility_Stub Dart file at `lib/src/stubs/<package_id>.dart` that declares all public types and members referenced in the transpiled project source.
2. Each stub type SHALL be a Dart `abstract class` (for interfaces) or a concrete class with `throw UnimplementedError('Stub: <PackageId>.<TypeName>.<MemberName>')` bodies for all methods and getters.
3. THE NuGet_Handler SHALL emit a `// STUB: <PackageId> v<Version> — no Dart mapping available` comment at the top of each stub file.
4. THE NuGet_Handler SHALL emit a diagnostic warning for each Tier_3 package listing the package ID, version, and the number of stub types generated.
5. WHEN a Mapping_Config entry provides a `stub_path` for a Tier_3 package, THE NuGet_Handler SHALL use the user-supplied stub file instead of generating one.
6. THE NuGet_Handler SHALL add a `# TODO: replace stub` comment in `pubspec.yaml` next to any dependency entry that corresponds to a Tier_3 stub, so developers can track unresolved dependencies.

---

### Requirement 7: pubspec.yaml Generation

**User Story:** As a developer, I want the transpiler to produce a correct and complete `pubspec.yaml` for the output Dart package, so that `dart pub get` succeeds without manual editing.

#### Acceptance Criteria

1. THE NuGet_Handler SHALL emit a `pubspec.yaml` file in the root of the output Dart package containing `name`, `description`, `version`, `environment` (Dart SDK constraint), `dependencies`, and `dev_dependencies` sections.
2. THE NuGet_Handler SHALL derive the Dart package `name` from the root namespace or project name, converted to snake_case following the same rules as the Namespace_Mapper.
3. THE NuGet_Handler SHALL populate `dependencies` with all Tier_1 Dart package mappings and all Tier_2 path dependencies, and SHALL populate `dev_dependencies` with packages whose NuGet `PrivateAssets="all"` was set.
4. WHEN a Dart package appears as a dependency of multiple mapped NuGet packages, THE NuGet_Handler SHALL emit it exactly once in `pubspec.yaml` using the most permissive compatible version constraint.
5. THE NuGet_Handler SHALL emit the `environment.sdk` constraint based on the minimum Dart SDK version required by all mapped Dart packages.
6. THE NuGet_Handler SHALL produce a deterministic `pubspec.yaml`: the same Package_Graph SHALL always produce the same file content, with dependencies sorted alphabetically.

---

### Requirement 8: Mapping Registry Management

**User Story:** As a developer or tool maintainer, I want to extend and override the built-in NuGet-to-Dart mapping registry, so that I can add mappings for internal packages or override defaults for my project.

#### Acceptance Criteria

1. THE Mapping_Registry SHALL be stored as a versioned YAML file bundled with the transpiler, with a schema that supports `package_id`, `version_range`, `dart_package`, `dart_version_constraint`, `shim_path` (optional), and `tier` fields.
2. THE NuGet_Handler SHALL support a `nuget_mappings` key in `transpiler.yaml` whose entries are merged with the built-in Mapping_Registry, with user entries taking precedence over built-in entries for the same package ID.
3. WHEN a user-supplied mapping entry omits `dart_version_constraint`, THE NuGet_Handler SHALL use `any` as the constraint and emit a diagnostic warning recommending a pinned version.
4. THE NuGet_Handler SHALL validate all Mapping_Registry entries at startup and emit a diagnostic error for any entry with an invalid `version_range`, missing required fields, or a `dart_package` name that is not a valid pub.dev identifier.
5. THE NuGet_Handler SHALL support a `mapping_registry_path` key in `transpiler.yaml` that points to an external YAML file to merge as an additional registry source.
6. THE NuGet_Handler SHALL expose a `cs2dart registry list` CLI command that prints all active Mapping_Registry entries (built-in + user overrides) in a tabular format.

---

### Requirement 9: Version Constraint Translation

**User Story:** As a developer, I want NuGet version ranges to be translated to equivalent Dart pub version constraints, so that the generated `pubspec.yaml` enforces compatible dependency versions.

#### Acceptance Criteria

1. THE NuGet_Handler SHALL translate NuGet minimum-inclusive ranges (e.g., `[1.2.0,)`) to Dart `^1.2.0` constraints when the major version is non-zero.
2. THE NuGet_Handler SHALL translate NuGet exact-version pins (e.g., `[1.2.3]`) to Dart `1.2.3` exact constraints.
3. THE NuGet_Handler SHALL translate NuGet upper-bounded ranges (e.g., `[1.0.0, 2.0.0)`) to Dart `>=1.0.0 <2.0.0` constraints.
4. WHEN a NuGet version range has no direct Dart equivalent (e.g., non-contiguous ranges), THE NuGet_Handler SHALL use the widest covering Dart constraint and emit a diagnostic warning.
5. WHEN the Mapping_Registry specifies an explicit `dart_version_constraint` for a Tier_1 package, THE NuGet_Handler SHALL use that constraint verbatim rather than translating the NuGet version range.
6. THE NuGet_Handler SHALL validate that all emitted Dart version constraints are syntactically valid pub constraints and emit a diagnostic error for any that are not.

---

### Requirement 10: Diagnostics and Reporting

**User Story:** As a developer, I want a clear dependency mapping report after transpilation, so that I can quickly identify which packages were fully mapped, partially handled, or left as stubs.

#### Acceptance Criteria

1. THE NuGet_Handler SHALL produce the content of `dependency_report.md` as a string conforming
   to the following schema and place it in `Dart_Package.DependencyReportContent`; the
   Result_Collector is responsible for writing this string to disk. The schema is:

   **Required sections (in order):**

   ```markdown
   # NuGet Dependency Report

   ## Summary

   | Metric | Count |
   |---|---|
   | Total packages resolved | <integer> |
   | Tier 1 (mapped) | <integer> |
   | Tier 2 (transpiled) | <integer> |
   | Tier 3 (stubbed) | <integer> |

   ## Tier 3 Stubs

   | Package ID | Resolved Version | Stub File | Types Stubbed |
   |---|---|---|---|
   | <package_id> | <semver> | `lib/src/stubs/<package_id>.dart` | <integer> |

   ## Version Conflicts

   | Package ID | Requested By | Required Range | Resolved Version |
   |---|---|---|---|
   | <package_id> | <dependent_package_id> | <nuget_version_range> | <semver> |
   ```

   - The **Summary** section SHALL always be present, even when all counts are zero.
   - The **Tier 3 Stubs** table SHALL contain one row per Tier_3 package; WHEN no Tier_3 packages exist, the section SHALL contain the text `_No Tier 3 stubs generated._` in place of the table.
   - The **Version Conflicts** section SHALL contain one row per conflict recorded during transitive resolution (per Requirement 2.2–2.3); WHEN no conflicts exist, the section SHALL contain the text `_No version conflicts encountered._` in place of the table.
   - The `Resolved Version` column in the **Version Conflicts** table SHALL be the version selected by NuGet's lowest-applicable-version rule, or the text `UNRESOLVED` when no satisfying version exists.
   - Rows in both tables SHALL be sorted alphabetically by Package ID.

2. EACH diagnostic emitted by THE NuGet_Handler SHALL contain: a severity level (Error, Warning, Info), a stable diagnostic code (e.g., `NR0001`), a human-readable message, and the source `.csproj` file path and line number where applicable.
3. THE NuGet_Handler SHALL NOT emit duplicate diagnostics for the same package ID and diagnostic code within a single run.
4. WHEN all NuGet dependencies are resolved to Tier_1 or Tier_2 with no errors, THE NuGet_Handler SHALL emit a single Info diagnostic confirming successful dependency resolution.
5. THE NuGet_Handler SHALL include NuGet dependency handling coverage in the transpiler's feature support matrix, tracking the percentage of resolved packages per tier across a run.
6. WHEN no NuGet packages are resolved for a project, THE NuGet_Handler SHALL set
   `Dart_Package.DependencyReportContent` to `null`; the Result_Collector will not write a
   `dependency_report.md` file for that package.

---

### Requirement 11: Configuration

**User Story:** As a developer, I want fine-grained control over NuGet dependency handling via `transpiler.yaml`, so that I can tune the behavior for my project's specific package ecosystem.

#### Acceptance Criteria

1. THE Mapping_Config SHALL support a `nuget_feed` key specifying the NuGet feed URL (defaults to `https://api.nuget.org/v3/index.json`).
2. THE Mapping_Config SHALL support a `nuget_cache_path` key specifying a local directory to use as the NuGet package cache.
3. THE Mapping_Config SHALL support a `tier2_source_paths` key: a list of local directory paths where Tier_2 package source trees can be found, searched in order before attempting network download.
4. THE Mapping_Config SHALL support a `exclude_packages` list: packages in this list SHALL be excluded from the Package_Graph entirely and SHALL NOT appear in `pubspec.yaml` or generate stubs.
5. THE Mapping_Config SHALL support a `force_tier` map from package ID to tier (`1`, `2`, or `3`), overriding automatic classification.
6. THE Mapping_Config SHALL support a `transpile_tier2` boolean (default `true`); WHEN set to `false`, all Tier_2 packages SHALL be downgraded to Tier_3 and handled via stubs.
7. WHEN Mapping_Config is absent or empty, THE NuGet_Handler SHALL apply all default rules and built-in Mapping_Registry entries without error.

---

### Requirement 13: Roslyn Compilation Preparation Contract

**User Story:** As a pipeline integrator, I want the NuGet_Handler to fully prepare the Roslyn Compilation before the IR_Builder runs, so that the IR_Builder receives a fully-bound Compilation with no unresolved external references.

#### Acceptance Criteria

1. THE NuGet_Handler SHALL add a metadata reference (`.dll` assembly) to the Roslyn `Compilation` for every Tier_1 package in the resolved Package_Graph before the `Compilation` is passed to the IR_Builder.
2. THE NuGet_Handler SHALL add all C# `SyntaxTree` objects from Tier_2 package sources to the Roslyn `Compilation` before the `Compilation` is passed to the IR_Builder, so that Tier_2 types are fully resolvable by Roslyn's `SemanticModel`.
3. THE NuGet_Handler SHALL NOT add any source or metadata to the Roslyn `Compilation` for Tier_3 packages; references to Tier_3 types SHALL appear as binding errors in the `SemanticModel`, causing the IR_Builder to emit `UnresolvedSymbol` nodes per IR Requirement 2.5.
4. THE NuGet_Handler SHALL annotate each entry in `Load_Result.PackageReferences` with its resolved `Tier` (1, 2, or 3) and its `DartMapping` (nullable) before the `Load_Result` is passed to the IR_Builder, so that downstream stages can determine the correct Dart output strategy from the IR alone without re-consulting the Mapping_Registry.
5. WHEN a Tier_1 assembly cannot be located in the local NuGet cache or configured feed, THE NuGet_Handler SHALL emit a diagnostic error and downgrade the package to Tier_3, ensuring the IR_Builder still receives a processable (if incomplete) `Compilation`.
6. THE NuGet_Handler SHALL complete all Compilation preparation steps before invoking the IR_Builder; it SHALL NOT modify the `Compilation` or `Load_Result` after the IR_Builder has started processing.

---

### Requirement 14: IR Symbol to Dart Output Mapping Contract

**User Story:** As a Dart code generator author, I want every external IR_Symbol to carry enough information to determine the correct Dart import and type name, so that I can emit correct Dart code for NuGet-sourced types without consulting the Mapping_Registry at code generation time.

#### Acceptance Criteria

1. WHEN the IR_Builder emits an `IR_Symbol` for a type from a Tier_1 package assembly, THE IR_Symbol SHALL carry the NuGet package ID in a `SourcePackageId` field so that the Dart code generator can look up the `DartMapping` from the annotated `PackageReferences` list on the `IrCompilationUnit`.
2. WHEN the IR_Builder emits an `IR_Symbol` for a type from a Tier_2 transpiled package, THE IR_Symbol SHALL carry the NuGet package ID in `SourcePackageId`; the Dart code generator SHALL resolve the import path as `lib/src/packages/<package_id>/<type_path>.dart`.
3. WHEN the IR_Builder emits an `UnresolvedSymbol` node for a type that originates from a Tier_3 package (identifiable via the assembly name in the binding error), THE IR_Symbol SHALL carry the NuGet package ID in `SourcePackageId`; the Dart code generator SHALL resolve the import path as `lib/src/stubs/<package_id>.dart`.
4. THE IR_Validator SHALL verify that every `IR_Symbol` whose `AssemblyName` matches a package in `IrCompilationUnit.PackageReferences` carries a non-null `SourcePackageId` field (package symbol completeness invariant).
5. THE NuGet_Handler SHALL ensure that the `SourcePackageId` values recorded in `IR_Symbol` nodes are identical to the package IDs in the `Load_Result.PackageReferences` list, so that lookups by the Dart code generator are unambiguous.

---

### Requirement 12: Correctness Properties for Property-Based Testing

**User Story:** As a transpiler test engineer, I want well-defined correctness properties for the NuGet_Handler, so that I can write property-based tests that catch regressions across a wide range of project configurations.

#### Acceptance Criteria

1. FOR ALL valid `.csproj` inputs, THE NuGet_Handler SHALL produce a Package_Graph where every direct `<PackageReference>` entry appears as a node with `isDirect = true` (direct reference preservation property).
2. FOR ALL valid `.csproj` inputs, running THE NuGet_Handler twice on the same input SHALL produce an identical Package_Graph and `pubspec.yaml` (determinism property).
3. FOR ALL resolved packages classified as Tier_1, the generated `pubspec.yaml` SHALL contain a `dependencies` entry for the mapped Dart package (Tier_1 coverage property).
4. FOR ALL resolved packages classified as Tier_3, a Compatibility_Stub file SHALL exist at `lib/src/stubs/<package_id>.dart` in the output (Tier_3 stub completeness property).
5. FOR ALL generated `pubspec.yaml` files, running `dart pub get` on the output package SHALL succeed without manual edits when all Tier_1 Dart packages exist on pub.dev (pub compatibility property).
6. FOR ALL Package_Graphs, the count of entries in the `dependencies` section of `pubspec.yaml` SHALL be less than or equal to the count of resolved packages (no phantom dependencies property — every pubspec entry traces to a resolved NuGet package or a shim).
