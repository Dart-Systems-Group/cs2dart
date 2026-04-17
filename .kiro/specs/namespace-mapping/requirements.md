# Namespace Mapping Requirements

## Introduction

This section specifies the detailed, testable requirements for the namespace mapping subsystem of the C# → Dart transpiler. The subsystem is responsible for translating C# namespace declarations and `using` directives into Dart library files, `part`/`part of` directives, and `import` statements, while producing idiomatic snake_case Dart library identifiers from PascalCase C# namespace segments.

## Glossary

- **Namespace_Mapper**: The subsystem component that converts C# namespace identifiers and structure into Dart library paths and import directives.
- **Namespace_Segment**: A single dot-separated component of a C# namespace (e.g., `Collections` in `System.Collections.Generic`).
- **Library_Path**: The relative file path of a generated Dart library file (e.g., `lib/system/collections/generic.dart`).
- **Library_Identifier**: The Dart `library` directive name derived from the namespace (e.g., `system.collections.generic`).
- **Mapping_Config**: The optional user-supplied configuration (in `transpiler.yaml`) that overrides default namespace-to-library mappings.
- **Conflict**: A situation where two distinct C# namespaces with the same number of dot-separated segments produce identical Canonical_Forms for every corresponding segment, resulting in the same Library_Path. This can only occur when segments differ solely in casing or in characters that are normalised away (e.g. `HTTPClient` vs `HttpClient`, or `My_Utils` vs `MyUtils`). Namespaces with different segment counts always produce different Library_Paths and cannot conflict.
- **Root_Namespace**: The top-level namespace segment configured as the Dart package root (defaults to the first segment of the dominant namespace in the project).
- **Canonical_Form**: The normalized, lowercased, snake_case representation of a namespace segment used for all comparisons and conflict detection.

---

## Requirements

### Requirement 1: Namespace Segment Transformation

**User Story:** As a developer migrating a C# codebase, I want C# namespace names to be converted to valid, idiomatic Dart library identifiers, so that the generated Dart code follows Dart naming conventions without manual renaming.

#### Acceptance Criteria

1. WHEN the Namespace_Mapper processes a Namespace_Segment, THE Namespace_Mapper SHALL convert PascalCase and camelCase segments to snake_case by inserting an underscore before each uppercase letter that follows a lowercase letter or digit.
2. WHEN the Namespace_Mapper processes a Namespace_Segment, THE Namespace_Mapper SHALL convert all characters in the resulting identifier to lowercase.
3. WHEN a Namespace_Segment contains consecutive uppercase letters (e.g., `HTTPClient`), THE Namespace_Mapper SHALL treat the run of uppercase letters as a single word, producing `http_client`.
4. WHEN a Namespace_Segment contains digits (e.g., `OAuth2`), THE Namespace_Mapper SHALL preserve the digits in place, producing `o_auth2`.
5. WHEN a Namespace_Segment contains characters that are not alphanumeric or underscores, THE Namespace_Mapper SHALL replace each such character with an underscore.
6. WHEN a transformed Namespace_Segment would begin with a digit, THE Namespace_Mapper SHALL prepend a single underscore to produce a valid Dart identifier.
7. FOR ALL Namespace_Segments, THE Namespace_Mapper SHALL produce a Canonical_Form that is deterministic: applying the transformation twice to the same input SHALL produce the same output (idempotence).

### Requirement 2: Namespace-to-Library-Path Mapping

**User Story:** As a developer, I want each C# namespace to map to a predictable Dart library file path, so that the generated package structure is navigable and consistent.

#### Acceptance Criteria

1. WHEN the Namespace_Mapper maps a fully-qualified C# namespace, THE Namespace_Mapper SHALL produce a Library_Path by joining the snake_case Canonical_Form of each Namespace_Segment with `/` as separator and appending `.dart`.
2. WHEN the Root_Namespace is configured, THE Namespace_Mapper SHALL strip the Root_Namespace prefix from the Library_Path and place the resulting file under `lib/`.
3. WHEN a C# namespace has no configured Root_Namespace, THE Namespace_Mapper SHALL place all generated files under `lib/` using the full transformed namespace path.
4. WHEN two C# source files share the same namespace, THE Namespace_Mapper SHALL map both to the same Library_Path and emit their declarations into that single Dart library file.
5. THE Namespace_Mapper SHALL produce Library_Paths that contain only lowercase letters, digits, underscores, and `/` separators.

### Requirement 3: Nested Namespace Handling

**User Story:** As a developer with deeply nested C# namespaces, I want nested namespaces to produce a corresponding nested Dart directory structure, so that the package layout mirrors the logical hierarchy of the original code.

#### Acceptance Criteria

1. WHEN a C# namespace is nested (contains two or more dot-separated segments), THE Namespace_Mapper SHALL create a corresponding nested directory hierarchy under `lib/`.
2. WHEN a parent namespace and a child namespace both contain declarations, THE Namespace_Mapper SHALL generate separate Dart library files for each level (e.g., `lib/foo.dart` and `lib/foo/bar.dart`).
3. WHEN a child namespace file is generated, THE Namespace_Mapper SHALL NOT automatically add a `part of` directive to the parent library unless the user explicitly configures barrel-file generation.
4. WHERE barrel-file generation is enabled in Mapping_Config, THE Namespace_Mapper SHALL generate an `export` statement in the parent library file for each direct child library.
5. WHEN the nesting depth exceeds 10 segments, THE Namespace_Mapper SHALL emit a diagnostic warning and continue processing.

### Requirement 4: Conflict Detection and Resolution

**User Story:** As a developer, I want the transpiler to detect and resolve namespace mapping conflicts, so that distinct C# namespaces never silently overwrite each other's generated Dart files or lose their identity in the output package.

#### Background

A Conflict can only arise between namespaces that have the **same number of dot-separated segments** and whose corresponding segments all normalise to the same snake_case string. Namespaces with different segment counts always produce paths with different depths and therefore can never conflict. Typical real-world examples:

- `Acme.HTTPClient` vs `Acme.HttpClient` → both produce `lib/acme/http_client.dart`
- `Acme.My_Utils` vs `Acme.MyUtils` → both produce `lib/acme/my_utils.dart`

Because the C# compiler already rejects duplicate fully-qualified type names within a single compilation, merging two conflicting namespaces into one Dart file would not cause Dart name collisions. However, merging is still harmful because it erases namespace identity (provenance is lost), silently exposes unrelated types to importers, and produces non-deterministic declaration ordering across runs.

#### Acceptance Criteria

1. WHEN two distinct C# namespaces with the same segment count produce identical Canonical_Forms for every corresponding segment, THE Namespace_Mapper SHALL detect this as a Conflict.
2. WHEN a Conflict is detected, THE Namespace_Mapper SHALL emit a diagnostic error identifying both conflicting C# namespaces, their shared Library_Path, and a suggested `namespace_mappings` override to resolve it.
3. WHEN a Conflict is detected and no Mapping_Config override is provided and `auto_resolve_conflicts` is not enabled, THE Namespace_Mapper SHALL halt code generation for the conflicting namespaces and continue processing non-conflicting namespaces.
4. WHEN a Mapping_Config override resolves a Conflict by assigning distinct Library_Paths to the conflicting namespaces, THE Namespace_Mapper SHALL use the overridden paths and emit no error.
5. WHEN `auto_resolve_conflicts: true` is set in `transpiler.yaml` and a Conflict is detected, THE Namespace_Mapper SHALL automatically generate a `namespace_mappings` entry for each conflicting namespace using the following deterministic procedure: sort the conflicting fully-qualified C# namespace strings lexicographically, assign the shared base Library_Path (without a suffix) to the first namespace in sorted order, and append `_2`, `_3`, … to the final path segment (before `.dart`) for each subsequent namespace in sorted order (e.g. `Acme.HttpClient` → `lib/acme/http_client.dart`, `Acme.HTTPClient` → `lib/acme/http_client_2.dart`). THE Namespace_Mapper SHALL emit a diagnostic warning listing the auto-generated mappings and write the resolved entries into a `transpiler.generated.yaml` file alongside `transpiler.yaml` so the developer can review and promote them to the main config.
6. WHEN `auto_resolve_conflicts: true` is set and a `transpiler.generated.yaml` already contains a resolved entry for a conflicting namespace, THE Namespace_Mapper SHALL reuse that entry rather than generating a new one, ensuring stable output across repeated runs.
7. IF a generated Library_Path would collide with an existing hand-written Dart file in the output directory, THEN THE Namespace_Mapper SHALL emit a diagnostic error and SHALL NOT overwrite the existing file.

### Requirement 5: Configuration and Override Options

**User Story:** As a developer, I want to override the default namespace-to-library mapping via configuration, so that I can handle special cases, legacy naming, and third-party namespace conventions without modifying generated code.

#### Acceptance Criteria

1. THE Mapping_Config SHALL support a `namespace_mappings` key whose value is a map from fully-qualified C# namespace strings to explicit Dart Library_Path strings.
2. WHEN a namespace appears in `namespace_mappings`, THE Namespace_Mapper SHALL use the configured Library_Path instead of the derived one.
3. THE Mapping_Config SHALL support a `root_namespace` key that specifies the namespace prefix to strip when computing Library_Paths.
4. THE Mapping_Config SHALL support a `barrel_files` boolean key; WHEN set to `true`, THE Namespace_Mapper SHALL generate barrel export files for each namespace level.
5. THE Mapping_Config SHALL support a `namespace_prefix_aliases` key whose value is a map from C# namespace prefixes to replacement strings applied before snake_case conversion.
6. THE Mapping_Config SHALL support an `auto_resolve_conflicts` boolean key; WHEN set to `true`, THE Namespace_Mapper SHALL automatically generate disambiguating `namespace_mappings` entries for any detected Conflicts as described in Requirement 4.
7. WHEN an invalid Library_Path is specified in `namespace_mappings` (e.g., contains uppercase letters or spaces), THE Namespace_Mapper SHALL emit a diagnostic error and fall back to the derived path.
8. WHEN Mapping_Config is absent or empty, THE Namespace_Mapper SHALL apply all default transformation rules without error.

### Requirement 6: Import Directive Generation

**User Story:** As a developer, I want the transpiler to generate correct Dart `import` statements for cross-namespace references, so that the generated Dart code compiles without manual import management.

#### Acceptance Criteria

1. WHEN a C# type in namespace A references a type in namespace B, THE Namespace_Mapper SHALL emit a Dart `import` statement for the Library_Path of namespace B in the generated file for namespace A.
2. WHEN multiple types from the same namespace B are referenced in namespace A, THE Namespace_Mapper SHALL emit exactly one `import` statement for namespace B's Library_Path.
3. WHEN a C# `using` directive references a namespace that has a configured `namespace_mappings` override, THE Namespace_Mapper SHALL use the overridden Library_Path in the generated `import` statement.
4. WHEN a C# `using static` directive is encountered, THE Namespace_Mapper SHALL emit a `show` clause on the corresponding Dart `import` listing the statically-imported members.
5. WHEN a C# `using` alias directive is encountered (e.g., `using Alias = Some.Namespace.Type`), THE Namespace_Mapper SHALL emit a Dart `import … as alias` statement using the snake_case form of the alias name.
6. THE Namespace_Mapper SHALL NOT emit self-imports (a library importing itself).

### Requirement 7: Correctness Properties for Property-Based Testing

**User Story:** As a transpiler maintainer, I want the namespace mapping subsystem to satisfy formal correctness properties, so that I can use property-based tests to catch regressions across arbitrary namespace inputs.

#### Acceptance Criteria

1. FOR ALL valid C# namespace strings, THE Namespace_Mapper SHALL produce a Library_Path that is a valid relative POSIX file path containing only `[a-z0-9_/]` characters followed by `.dart`.
2. FOR ALL valid C# namespace strings N, applying the namespace-to-Library_Path transformation twice SHALL produce the same result as applying it once (idempotence): `map(map(N)) == map(N)`.
3. FOR ALL pairs of distinct C# namespace strings N1 and N2 that do not form a Conflict (i.e. they differ in segment count or have at least one non-colliding segment), THE Namespace_Mapper SHALL produce distinct Library_Paths: `N1 ≠ N2 → map(N1) ≠ map(N2)`.
4. FOR ALL C# namespace strings, the number of `/`-separated segments in the Library_Path (excluding the `.dart` suffix) SHALL equal the number of dot-separated Namespace_Segments in the input namespace (after Root_Namespace stripping).
5. FOR ALL Mapping_Config inputs that are valid YAML, THE Namespace_Mapper SHALL produce output that is a deterministic function of (namespace string, Mapping_Config): same inputs always yield the same Library_Path.
6. FOR ALL namespace strings that differ only in casing (e.g., `Foo.Bar` vs `foo.bar` vs `FOO.BAR`), THE Namespace_Mapper SHALL produce the same Canonical_Form, ensuring case-insensitive equivalence detection.
7. FOR ALL generated sets of `import` statements in a Dart library file, THE Namespace_Mapper SHALL produce no duplicate import paths (import deduplication invariant).
8. WHEN `auto_resolve_conflicts: true` is set and a set of conflicting namespaces is auto-resolved, the assignment of Library_Paths to namespaces SHALL be a deterministic function of the lexicographic order of the fully-qualified C# namespace strings: the same set of conflicting namespaces SHALL always produce the same mapping regardless of the order in which they were encountered during parsing.