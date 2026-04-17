# Transpiler Configuration Service — Requirements Document

## Introduction

This document specifies the requirements for the **Configuration Service** of the C# → Dart transpiler. The Configuration Service is responsible for locating, parsing, validating, and exposing the `transpiler.yaml` configuration file to all pipeline modules. It is the single authoritative source of configuration values for the entire transpiler pipeline; no module may read `transpiler.yaml` directly.

---

## Glossary

- **Config_Service**: The component described by this specification; responsible for loading and exposing transpiler configuration.
- **Config_File**: The `transpiler.yaml` file that contains user-supplied configuration for the transpiler.
- **Config_Object**: The strongly-typed, validated in-memory representation of the parsed `transpiler.yaml`.
- **Config_Section**: A named top-level key in `transpiler.yaml` (e.g., `nuget`, `namespace_mappings`, `linq_strategy`).
- **Config_Consumer**: Any pipeline module that reads configuration values via the `Config_Service` interface (e.g., `IR_Builder`, `Namespace_Mapper`, `Event_Transpiler`, `Struct_Transpiler`, `Project_Loader`).
- **Default_Value**: The value used by a Config_Consumer when a Config_Section or key is absent from the Config_File.
- **Validation_Error**: A structured diagnostic emitted when the Config_File contains an invalid value, unrecognized key, or type mismatch.
- **Config_Diagnostic**: A structured message (error, warning, or info) produced by the Config_Service describing a problem encountered during loading or validation.

---

## Requirements

### Requirement 1: Config File Discovery

**User Story:** As a pipeline operator, I want the Config_Service to automatically locate `transpiler.yaml` relative to the entry-point project file, so that I do not need to pass the config path explicitly in the common case.

#### Acceptance Criteria

1. WHEN the transpiler is invoked with a `.csproj` or `.sln` entry-point path, THE Config_Service SHALL search for `transpiler.yaml` in the same directory as the entry-point file.
2. IF `transpiler.yaml` is not found in the entry-point directory, THE Config_Service SHALL search each parent directory up to the filesystem root, stopping at the first `transpiler.yaml` found.
3. IF no `transpiler.yaml` is found after exhausting the directory search, THE Config_Service SHALL return a Config_Object populated entirely with Default_Values and SHALL NOT emit a Validation_Error.
4. WHEN an explicit config file path is provided via the CLI `--config` flag, THE Config_Service SHALL use that path exclusively and SHALL NOT perform directory search.
5. IF an explicitly provided config file path does not exist, THE Config_Service SHALL emit a Config_Diagnostic of severity `Error` and halt pipeline initialization.

---

### Requirement 2: Config File Parsing

**User Story:** As a developer, I want `transpiler.yaml` to be parsed into a strongly-typed Config_Object, so that all pipeline modules receive validated, type-safe configuration values.

#### Acceptance Criteria

1. THE Config_Service SHALL parse `transpiler.yaml` using a YAML 1.2-compliant parser.
2. WHEN parsing succeeds, THE Config_Service SHALL produce a Config_Object that exposes all recognized Config_Sections as typed properties.
3. IF the file contains invalid YAML syntax, THE Config_Service SHALL emit a Config_Diagnostic of severity `Error` identifying the offending line and column, and SHALL halt pipeline initialization.
4. IF the file contains a recognized key with a value of the wrong type (e.g., a string where a boolean is expected), THE Config_Service SHALL emit a Config_Diagnostic of severity `Error` identifying the key and expected type, and SHALL halt pipeline initialization.
5. IF the file contains an unrecognized top-level key, THE Config_Service SHALL emit a Config_Diagnostic of severity `Warning` identifying the key and continue parsing.
6. FOR ALL valid `transpiler.yaml` files, parsing then serializing then parsing SHALL produce an equivalent Config_Object (round-trip property).

---

### Requirement 3: Application Interface

**User Story:** As a pipeline module author, I want a well-defined, stable interface to retrieve configuration values, so that my module is decoupled from YAML parsing and file I/O.

#### Acceptance Criteria

1. THE Config_Service SHALL expose a single interface `IConfigService` (or language-equivalent) with the following read-only accessor methods, one per Config_Section:
   - `LinqStrategy get linqStrategy` — returns `lower_to_loops` or `preserve_functional`; default: `preserve_functional`
   - `NullabilityConfig get nullability` — returns nullability rules (see Requirement 4)
   - `AsyncConfig get asyncBehavior` — returns async/await behavior settings; (`async_behavior` in `transpiler.yaml`, see Requirement 5)
   - `Map<String, String> get namespaceMappings` — returns fully-qualified C# namespace → Dart library path overrides; default: empty map
   - `String? get rootNamespace` — returns the namespace prefix to strip; default: null
   - `bool get barrelFiles` — returns whether barrel export files are generated; default: false
   - `Map<String, String> get namespacePrefixAliases` — returns namespace prefix replacement map; default: empty map
   - `bool get autoResolveConflicts` — returns whether namespace conflicts are auto-resolved; default: false
   - `EventStrategy get eventStrategy` — returns `stream` or `callback`; default: `stream`
   - `Map<String, EventMappingOverride> get eventMappings` — returns per-event overrides; default: empty map
   - `Map<String, String> get packageMappings` — returns NuGet package name → Dart package name overrides; default: empty map (`package_mappings` in `transpiler.yaml`)
   - `String? get sdkPath` — returns explicit .NET SDK path override; default: null
   - `List<String> get nugetFeedUrls` — returns ordered list of NuGet feed URLs to query before falling back to `nuget.org`; default: `["https://api.nuget.org/v3/index.json"]` (`nuget_feeds` in `transpiler.yaml`)
   - `Map<String, String> get libraryMappings` — returns .NET type → Dart type overrides; default: empty map
   - `Map<String, StructMappingOverride> get structMappings` — returns per-struct BCL overrides; default: empty map
   - `NamingConventions get namingConventions` — returns naming convention settings; default: all Dart-idiomatic defaults
   - `Map<String, bool> get experimentalFeatures` — returns feature-flag toggles for in-progress features; default: empty map (`experimental` in `transpiler.yaml`)
   - `Map<String, dynamic> get nugetMappings` — returns full NuGet registry override entries (package ID → `MappingEntry` record); default: empty map (`nuget_mappings` in `transpiler.yaml`). Distinct from `packageMappings`: `packageMappings` maps package names to Dart package names (string→string), while `nugetMappings` carries full registry records (version range, shim path, tier override, etc.)
   - `String? get nugetCachePath` — returns local directory path to use as the NuGet package cache; default: null (`nuget_cache_path` in `transpiler.yaml`)
   - `List<String> get tier2SourcePaths` — returns ordered list of local directory paths where Tier 2 package source trees can be found; default: empty list (`tier2_source_paths` in `transpiler.yaml`)
   - `List<String> get excludePackages` — returns list of NuGet package IDs to exclude from the Package_Graph entirely; default: empty list (`exclude_packages` in `transpiler.yaml`)
   - `Map<String, int> get forceTier` — returns map from NuGet package ID to tier (1, 2, or 3), overriding automatic classification; default: empty map (`force_tier` in `transpiler.yaml`)
   - `bool get transpileTier2` — when false, all Tier 2 packages are downgraded to Tier 3 and handled via stubs; default: true (`transpile_tier2` in `transpiler.yaml`)
   - `String? get mappingRegistryPath` — returns path to an external YAML file to merge as an additional NuGet mapping registry source; default: null (`mapping_registry_path` in `transpiler.yaml`)
2. ALL accessor methods SHALL be pure (no side effects, no I/O) after the Config_Object is constructed.
3. THE `IConfigService` interface SHALL be the only mechanism by which pipeline modules access configuration; direct file I/O or YAML parsing within pipeline modules is forbidden.
4. THE Config_Service SHALL be constructed once at pipeline startup and passed to all pipeline modules via dependency injection or an equivalent mechanism; it SHALL NOT use global/static mutable state.
5. WHEN a Config_Section is absent from the Config_File, the corresponding accessor SHALL return the documented Default_Value without error.

---

### Requirement 4: Nullability Configuration

**User Story:** As a developer, I want to configure how C# nullable reference types are mapped to Dart null-safety annotations, so that I can tune the generated code for my project's null-safety posture.

#### Acceptance Criteria

1. THE Config_Service SHALL expose a `NullabilityConfig` value object with the following fields:
   - `bool treatNullableAsOptional` — when true, `T?` parameters are emitted as optional Dart parameters; default: false
   - `bool emitNullAsserts` — when true, non-nullable dereferences emit `!` assertions; default: false
   - `bool preserveNullableAnnotations` — when true, all `?` annotations from C# are preserved in Dart; default: true
2. WHEN `preserveNullableAnnotations` is false, THE Config_Service SHALL document that all types are emitted as non-nullable in Dart.
3. IF an unrecognized key appears under the `nullability` section, THE Config_Service SHALL emit a Config_Diagnostic of severity `Warning` and ignore the key.

---

### Requirement 5: Async Configuration

**User Story:** As a developer, I want to configure how C# async patterns are mapped to Dart, so that I can control `ConfigureAwait` behavior, `ValueTask` handling, and unawaited-call wrapping.

#### Acceptance Criteria

1. THE Config_Service SHALL expose an `AsyncConfig` value object with the following fields:
   - `bool omitConfigureAwait` — when true, `ConfigureAwait(false)` calls are silently dropped; default: `false`
   - `bool mapValueTaskToFuture` — when true, `ValueTask<T>` is mapped to `Future<T>`; default: `true`
   - `bool wrapUnawaitedVoid` — when true, `InvocationExpression` nodes with `IsFireAndForget = true` are emitted as `unawaited(...)` in Dart; when false, they are emitted as plain calls; default: `true`
2. The `wrapUnawaitedVoid` field controls only calls that were explicitly marked as fire-and-forget in C# source (i.e., `IsFireAndForget = true` on the IR node, set by the IR_Builder for explicit-discard `_ = SomeAsync()` patterns or `#pragma warning disable CS4014`-suppressed call sites). It does NOT affect bare unawaited calls that carry no suppression signal.
3. IF an unrecognized key appears under the `async_behavior` section, THE Config_Service SHALL emit a Config_Diagnostic of severity `Warning` and ignore the key.

---

### Requirement 6: Naming Conventions Configuration

**User Story:** As a developer, I want to configure naming convention rules, so that the generated Dart identifiers follow my project's style guide.

#### Acceptance Criteria

1. THE Config_Service SHALL expose a `NamingConventions` value object with the following fields:
   - `CaseStyle classNameStyle` — casing for generated class names; default: `PascalCase`
   - `CaseStyle methodNameStyle` — casing for generated method names; default: `camelCase`
   - `CaseStyle fieldNameStyle` — casing for generated field names; default: `camelCase`
   - `CaseStyle fileNameStyle` — casing for generated file names; default: `snake_case`
   - `String privatePrefix` — prefix for library-private identifiers; default: `_`
2. `CaseStyle` SHALL be an enum with values: `PascalCase`, `camelCase`, `snake_case`, `SCREAMING_SNAKE_CASE`.
3. IF an unrecognized key appears under the `naming_conventions` section, THE Config_Service SHALL emit a Config_Diagnostic of severity `Warning` and ignore the key.

---

### Requirement 7: Diagnostics

**User Story:** As a developer, I want all configuration errors and warnings to be reported as structured diagnostics, so that I can programmatically inspect and display them.

#### Acceptance Criteria

1. THE Config_Service SHALL represent every diagnostic as a `Config_Diagnostic` record containing: severity (`Error`, `Warning`, `Info`), a unique diagnostic code in the range `CFG0001`–`CFG9999`, a human-readable message, and an optional source location (file path and line/column).
2. THE Config_Service SHALL aggregate all Config_Diagnostics and return them alongside the Config_Object rather than writing to standard output or throwing exceptions.
3. THE Config_Service SHALL NOT emit duplicate diagnostics for the same source location and diagnostic code.
4. WHEN any Config_Diagnostic has severity `Error`, THE Config_Service SHALL return a null or sentinel Config_Object and the pipeline SHALL halt before any module begins processing.
5. WHEN all Config_Diagnostics have severity `Warning` or `Info`, THE Config_Service SHALL return a fully populated Config_Object and the pipeline SHALL proceed.

---

### Requirement 8: Experimental Feature Flags

**User Story:** As a transpiler developer, I want to expose in-progress features behind named boolean flags in `transpiler.yaml`, so that users can opt in to experimental behavior without requiring a new release, and so that the flags are discoverable and validated like all other configuration.

#### Acceptance Criteria

1. THE Config_Service SHALL recognize an `experimental` top-level section in `transpiler.yaml` containing a map of feature-flag names (strings) to boolean values.
2. THE Config_Service SHALL expose the parsed flags via `IConfigService.experimentalFeatures` returning `Map<String, bool>`; WHEN the `experimental` section is absent, the accessor SHALL return an empty map.
3. WHEN an `experimental` entry has a value that is not a boolean, THE Config_Service SHALL emit a Config_Diagnostic of severity `Error` identifying the offending key and halt pipeline initialization.
4. THE Config_Service SHALL NOT emit a Config_Diagnostic for unrecognized feature-flag names within the `experimental` section; unknown flags SHALL be silently ignored to allow forward-compatible config files.
5. FOR ALL valid `transpiler.yaml` files, parsing then serializing the `experimental` section then parsing again SHALL produce a value-equal `experimentalFeatures` map (round-trip property).
6. WHEN a pipeline module queries `IConfigService.experimentalFeatures` for a flag name that is not present in the map, the module SHALL treat the flag as `false` (disabled by default).

---

### Requirement 9: Load_Result Config Field

**User Story:** As a pipeline integrator, I want the `Load_Result` to carry the active Config_Object, so that downstream stages and diagnostic reporters can inspect which configuration was in effect for a given run without re-reading the file.

#### Acceptance Criteria

1. THE Config_Service SHALL expose the resolved Config_Object via a `get config` accessor so that the `Project_Loader` can store it in `Load_Result.Config` after pipeline initialization.
2. WHEN `Load_Result.Config` is read by any downstream stage, it SHALL be value-equal to the Config_Object returned by `IConfigService` accessors for the same run (consistency property).
3. WHEN no `transpiler.yaml` was found, `Load_Result.Config` SHALL be a default Config_Object (all fields at documented Default_Values), not null.
4. FOR ALL valid `transpiler.yaml` files, parsing then serializing `Load_Result.Config` then parsing again SHALL produce a Config_Object that is value-equal to the original (round-trip property).

---

### Requirement 10: LINQ Strategy Default

**User Story:** As a developer, I want the default LINQ strategy to be `preserve_functional`, so that generated Dart code uses idiomatic collection method chains unless I explicitly opt in to loop lowering.

#### Acceptance Criteria

1. WHEN `linq_strategy` is absent from `transpiler.yaml`, `IConfigService.linqStrategy` SHALL return `preserve_functional`.
2. WHEN `linq_strategy` is set to `lower_to_loops`, `IConfigService.linqStrategy` SHALL return `lower_to_loops`.
3. WHEN `linq_strategy` is set to `preserve_functional`, `IConfigService.linqStrategy` SHALL return `preserve_functional`.
4. IF `linq_strategy` is set to any value other than `lower_to_loops` or `preserve_functional`, THE Config_Service SHALL emit a Config_Diagnostic of severity `Error` identifying the invalid value and halt pipeline initialization.

---

### Requirement 11: Correctness Properties for Property-Based Testing

**User Story:** As a transpiler test engineer, I want well-defined correctness properties for the Config_Service, so that I can write property-based tests that catch regressions across a wide range of config inputs.

#### Acceptance Criteria

1. FOR ALL valid `transpiler.yaml` files, THE Config_Service SHALL produce a Config_Object where every accessor returns a value of the documented type (type safety property).
2. FOR ALL valid `transpiler.yaml` files, parsing the file twice SHALL produce Config_Objects that are value-equal (determinism property).
3. FOR ALL Config_Objects, every accessor called on a Config_Object produced from an empty `transpiler.yaml` SHALL return the documented Default_Value (default value property).
4. FOR ALL valid `transpiler.yaml` files, the set of Config_Diagnostics produced SHALL be a deterministic function of the file content: the same file content SHALL always produce the same set of diagnostics (diagnostic determinism property).
5. FOR ALL `transpiler.yaml` files that contain only recognized keys with valid types, THE Config_Service SHALL produce zero Config_Diagnostics of severity `Error` or `Warning` (clean config property).
