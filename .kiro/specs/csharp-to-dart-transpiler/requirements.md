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
- Diagnostics and warnings
- Optional: Dart extension libraries for .NET‑like APIs

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
- Library mappings
- Naming conventions
- Nullability rules
- Async behavior
- LINQ lowering strategy
- NuGet mapping overrides
- Experimental feature toggles

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
