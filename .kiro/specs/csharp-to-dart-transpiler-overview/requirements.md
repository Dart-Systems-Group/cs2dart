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
- Dart package (`pubspec.yaml`, `lib/`, `test/`) — formatted by `dart format`
- Generated Dart source files
- Mapping reports (C# → Dart)
- `TranspilerResult`: the single authoritative output of the pipeline, assembled by the
  Result Collector stage (invoked by the Validator after all tooling has completed). Contains:
  - `Packages` — list of `Output_Package` records (one per generated Dart package), each
    carrying the package name, output path, and the complete manifest of files written to disk
  - `Diagnostics` — the complete ordered list of all diagnostics from every pipeline stage
    (`PL`, `RF`, `IR`, `CG`, `NR`, `VA`, `RC`), ordered by stage then by source file and line number
  - `Success` — `true` if and only if `Diagnostics` contains no `Error`-severity entry across
    the entire pipeline run
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
| `PL`   | Project_Loader           | `PL0001–PL9999` |
| `RF`   | Roslyn Frontend          | `RF0001–RF9999` |
| `IR`   | IR_Builder               | `IR0001–IR9999` |
| `CG`   | Dart code generator      | `CG0001–CG9999` |
| `NR`   | NuGet dependency handler | `NR0001–NR9999` |
| `VA`   | Validation & analysis    | `VA0001–VA9999` |
| `CFG`  | Configuration Service    | `CFG0001–CFG9999` |
| `RC`   | Result Collector         | `RC0001–RC9999` |

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
   - Runs `dart format` over every generated `.dart` file (unconditional; always produces
     well-formed output for syntactically valid input)
   - Runs `dart analyze` as a correctness assertion — findings become `VA`-prefixed diagnostics;
     the stage never patches or retries generated code
   - Runs `dart pub get` to verify dependency resolution — failure is reported as a `Warning`
     (may be a network issue, not a transpiler bug)
   - Aggregates all upstream diagnostics (`PL`, `RF`, `IR`, `CG`, `NR`) with its own `VA`
     findings into a single ordered diagnostic list, then forwards to the Result Collector

7. **Result Collector**
   - Receives the completed `Gen_Result` and final diagnostic list from the Validator
   - Writes all generated artifacts to disk (`pubspec.yaml`, `lib/` files,
     `dependency_report.md` when present)
   - Constructs `Output_Package` records with a complete file manifest for each package
   - Assembles and returns the final `TranspilerResult`

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

All transpiler configuration is managed by the **Configuration Service** (`IConfigService`), which parses and validates `transpiler.yaml` once at pipeline startup and exposes typed accessors to every pipeline module. No module may read `transpiler.yaml` directly.

### Transpiler config file (`transpiler.yaml`)
- Library mappings (`libraryMappings`, `nugetMappings`)
- Naming conventions (`namingConventions`)
- Nullability rules (`nullability`)
- Async behavior (`async`)
- LINQ lowering strategy (`linqStrategy`)
- NuGet feed and mapping overrides (`nugetFeedUrls`, `nugetMappings`)
- Namespace mapping overrides (`namespaceMappings`, `rootNamespace`, `barrelFiles`, `autoResolveConflicts`)
- Event mapping overrides (`eventStrategy`, `eventMappings`)
- Struct mapping overrides (`structMappings`)
- Experimental feature toggles (`experimentalFeatures`)


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
