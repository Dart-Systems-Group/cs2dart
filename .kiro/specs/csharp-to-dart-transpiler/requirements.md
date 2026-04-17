# C# → Dart Transpiler — High‑Level Product Specification

## 1. Product overview
The C# → Dart transpiler is a static, deterministic source‑to‑source compiler that converts C# projects (including modern .NET features) into Dart packages. It is designed for:

- Migrating existing .NET codebases to Flutter
- Sharing business logic between C# and Dart ecosystems
- Enabling incremental adoption of Dart in .NET organizations
- Providing a predictable, testable translation pipeline for long‑term maintainability

The transpiler prioritizes semantic fidelity, type safety, and idiomatic Dart output.

---

## 2. Target users

### Primary
- Engineering teams migrating .NET apps to Flutter
- Companies with large C# business‑logic libraries
- Developers maintaining cross‑platform codebases

### Secondary
- Researchers and tool builders exploring language interoperability
- Teams building multi‑language SDKs

---

## 3. Product goals

### Core goals
- Translate C# syntax, types, and semantics into Dart with predictable, reproducible output
- Support real‑world .NET features, not just toy examples
- Provide configurable library mappings for .NET → Dart equivalents
- Support NuGet dependency analysis, mapping, and optional transpilation
- Integrate with Flutter, Dart CLI, and Dart analysis tools

### Non‑goals
- Not a runtime emulator for .NET
- Not a full .NET → Dart API compatibility layer
- Not a dynamic execution environment

---

## 4. Supported C# features

### MVP
- Classes, structs, interfaces, enums
- Methods, fields, properties, events
- Generics (in/out variance mapped to Dart)
- Async/await
- LINQ (lowered to loops or mapped to Dart extensions)
- Nullable reference types
- Exceptions
- Namespaces → Dart library structure
- Basic NuGet dependency mapping

### Full version
- Attributes → Dart annotations
- Delegates → typedefs + closures
- Expression trees (lowered or unsupported with diagnostics)
- Records → Dart records
- Pattern matching
- Source generators (partial support)
- Advanced NuGet dependency transpilation

---

## 5. Input & output

### Input
- `.csproj` or `.sln` file
- Full C# source tree
- NuGet package references
- Optional mapping configuration files

### Output
- Dart package (`pubspec.yaml`, `lib/`, `test/`)
- Generated Dart source files
- Mapping reports (C# → Dart)
- `TranspilerResult`: a structured result object containing the list of generated file paths, a `Diagnostic` list (see §5.1), and a boolean `Success` flag (true when no `Error`-severity diagnostics are present)
- Optional: Dart extension libraries for .NET‑like APIs

### 5.1 Diagnostic schema

Every component in the transpiler pipeline emits diagnostics using a shared `Diagnostic` record with the following fields:

| Field      | Type                          | Required | Description                                              |
|------------|-------------------------------|----------|----------------------------------------------------------|
| `Severity` | `Error` \| `Warning` \| `Info` | Yes      | Impact level of the diagnostic                           |
| `Code`     | string (`<prefix><4-digits>`) | Yes      | Stable, unique code. Prefix is component-reserved (see below) |
| `Message`  | string                        | Yes      | Human-readable description of the issue                  |
| `Source`   | string (file path)            | No       | Path to the file where the issue originates              |
| `Location` | `{ Line: int, Column: int }`  | No       | Line and column within `Source`                          |

**Reserved diagnostic code prefixes:**

| Prefix | Component            | Range           |
|--------|----------------------|-----------------|
| `PL`   | Project_Loader       | `PL0001–PL9999` |
| `IR`   | IR_Builder           | `IR0001–IR9999` |
| `CG`   | Dart code generator  | `CG0001–CG9999` |
| `NR`   | NuGet dependency handler | `NR0001–NR9999` |
| `VA`   | Validation & analysis | `VA0001–VA9999` |

No two components SHALL share a prefix. Roslyn compiler diagnostics are passed through with their original `CS`-prefixed codes and are not renumbered.

---

## 6. Architecture overview

### 6.1 Pipeline

1. **Project loader**
   - Parses `.csproj`
   - Resolves NuGet dependencies
   - Builds a dependency graph

2. **Roslyn frontend**
   - Produces typed AST + semantic model
   - Normalizes C# constructs
   - Lowers LINQ, async state machines, pattern matching

3. **Intermediate representation (IR)**
   - Language‑agnostic, typed, deterministic
   - Captures semantics, not syntax
   - Enables optimization and consistent codegen

4. **Dart code generator**
   - Emits idiomatic Dart
   - Enforces Dart style rules
   - Generates extension methods for missing APIs

5. **NuGet dependency handler**
   - Maps known packages to Dart equivalents
   - Optionally transpiles C# source from packages
   - Emits warnings for unsupported APIs

6. **Validation & analysis**
   - Runs `dart analyze`
   - Ensures type correctness
   - Ensures deterministic output

---

## 7. NuGet dependency strategy

### Tier 1: Known mappings
- `System.*` → `dart:core`, `dart:async`, `dart:collection`
- Common libraries (e.g., `Newtonsoft.Json` → `dart:convert` or popular JSON packages)

### Tier 2: Source‑available packages
- Transpile package source
- Apply mapping rules
- Emit compatibility shims

### Tier 3: Unsupported packages
- Emit diagnostics
- Provide fallback stubs
- Allow user‑defined mappings

---

## 8. Configuration model

### Transpiler config file (`transpiler.yaml`)

The `transpiler.yaml` file is parsed by the `Project_Loader` into a `Mapping_Config` object that is threaded through the entire pipeline. All components read their settings from this object rather than from the file directly. Supported top-level keys:

| Key                  | Type              | Default               | Description                                              |
|----------------------|-------------------|-----------------------|----------------------------------------------------------|
| `sdk_path`           | string            | auto-detected         | Explicit path to the .NET SDK reference assemblies       |
| `nuget_feeds`        | list of URLs      | `[nuget.org]`         | NuGet feeds queried in order before falling back to nuget.org |
| `package_mappings`   | map string→string | `{}`                  | NuGet package name → Dart package name overrides         |
| `linq_strategy`      | enum              | `preserve_functional` | `lower_to_loops` or `preserve_functional`                |
| `naming_conventions` | object            | Dart defaults         | Controls identifier casing (PascalCase, camelCase, etc.) |
| `nullability`        | object            | enabled               | Controls nullable reference type handling                |
| `async_behavior`     | object            | standard              | Controls async/await mapping strategy                    |
| `experimental`       | map string→bool   | `{}`                  | Feature-flag toggles for in-progress features            |

---

## 9. Quality guarantees

### Determinism
- Same input → same output
- No nondeterministic ordering or formatting

### Semantic fidelity
- Behaviorally equivalent code (within defined constraints)
- Verified via test harness and golden tests

### Idiomatic Dart
- Avoids “C#‑shaped Dart”
- Uses Dart patterns where safe and compatible

---

## 10. Tooling integration
- VS Code extension
- CLI tool (`cs2dart`)
- GitHub Action for CI
- Flutter integration templates
- Dart analyzer integration

---

## 11. Maintenance & evolution

### Versioning
- Semantic versioning
- Language compatibility matrix (C# version × Dart version)

### Update strategy
- Track Roslyn updates
- Track Dart language evolution
- Maintain mapping library
- Regression test suite for both languages and key frameworks

### Community extensions
- Plugin system for custom mappings and transforms
- Community‑maintained NuGet → Dart mapping registry

---

## 12. Risks & mitigations

### Risk: .NET APIs too large to map fully
- **Mitigation:** Tiered mapping, plugin system, explicit diagnostics, documented unsupported surface area.

### Risk: Dart evolves faster than mapping rules
- **Mitigation:** Versioned mapping profiles, deprecation warnings, and upgrade guides.

### Risk: NuGet packages with native bindings or platform‑specific code
- **Mitigation:** Mark unsupported; allow user stubs and platform‑specific Dart implementations.

---

## 13. Success metrics
- Percentage of C# syntax/semantics supported (tracked by feature matrix)
- Percentage of NuGet packages with known mappings or plugins
- Dart analyzer error rate after transpilation (target: near‑zero for supported feature set)
- Number of real‑world project migrations completed
- Developer satisfaction and DX scores (surveys, GitHub issues, adoption)
