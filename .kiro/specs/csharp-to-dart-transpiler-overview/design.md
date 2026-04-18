# C# → Dart Transpiler — Architecture Design

## Overview

The transpiler is split across two language runtimes connected by a serialized Intermediate Representation (IR). This split is forced by a hard constraint: the only production-quality C# parser and semantic model available is **Roslyn**, which is a .NET API and cannot run in a Dart process.

---

## Language Boundary

```
┌─────────────────────────────────┐        ┌──────────────────────────────────────┐
│         .NET Process            │        │           Dart Process               │
│                                 │        │                                      │
│  ┌─────────────┐                │        │  ┌──────────────────────────────┐   │
│  │   Project   │                │        │  │       IR Consumer            │   │
│  │   Loader    │                │        │  │  (reads + validates IR)      │   │
│  │ (.csproj /  │                │        │  └──────────────┬───────────────┘   │
│  │   .sln)     │                │        │                 │                   │
│  └──────┬──────┘                │        │  ┌──────────────▼───────────────┐   │
│         │                       │        │  │      Config Service          │   │
│  ┌──────▼──────┐                │  IR    │  │   (transpiler.yaml)          │   │
│  │   Roslyn    │   serialized   │ ──────▶│  └──────────────┬───────────────┘   │
│  │  Frontend   │ ─────────────▶ │        │                 │                   │
│  │  (AST +     │  (JSON/proto)  │        │  ┌──────────────▼───────────────┐   │
│  │  semantic   │                │        │  │     Pipeline Modules         │   │
│  │   model)    │                │        │  │  Namespace Mapper            │   │
│  └─────────────┘                │        │  │  Struct Transpiler           │   │
│                                 │        │  │  Event Transpiler            │   │
│  Writes IR to stdout or file    │        │  │  NuGet Dependency Handler    │   │
└─────────────────────────────────┘        │  └──────────────┬───────────────┘   │
                                           │                 │                   │
                                           │  ┌──────────────▼───────────────┐   │
                                           │  │     Dart Code Generator      │   │
                                           │  │  (emits .dart files)         │   │
                                           │  └──────────────────────────────┘   │
                                           └──────────────────────────────────────┘
```

---

## .NET Side

### Why .NET is required

Roslyn (`Microsoft.CodeAnalysis.CSharp`) is the only production-grade C# parser with full semantic analysis. It provides:

- A complete, typed syntax tree for all C# language versions
- Full symbol resolution (types, members, overloads)
- Semantic model queries (type inference, nullability flow, constant folding)
- Lowering of complex constructs (LINQ query syntax, async state machines, pattern matching)

There is no Dart binding or cross-platform port of Roslyn. The .NET process is therefore a hard requirement.

### Components

| Component | Responsibility |
|---|---|
| **Project Loader** | Parses `.csproj` / `.sln`, resolves NuGet package references, builds the project dependency graph |
| **Roslyn Frontend** | Invokes the Roslyn compiler pipeline to produce a typed AST and semantic model for all source files |
| **IR Serializer** | Converts the Roslyn semantic model into the language-agnostic IR format and writes it to stdout or a file |

### What the .NET side does NOT do

- It does not read `transpiler.yaml` or apply any configuration policy
- It does not make decisions about LINQ strategy, naming conventions, or nullability mapping
- It does not emit any Dart code
- It does not run `dart analyze`

The .NET process is a faithful, policy-free extractor. All transformation decisions are made on the Dart side.

---

## IR — The Language Boundary

The Intermediate Representation is the only interface between the two processes. It must be:

- **Language-agnostic**: no C#-specific or Dart-specific concepts; pure semantics
- **Versioned**: the IR schema carries a version field; the Dart consumer rejects incompatible versions
- **Deterministic**: the same source input always produces the same IR bytes
- **Self-contained**: the IR includes all type information needed by the Dart side; the Dart process never re-reads `.csproj` or NuGet feeds

### IR Transport

The .NET process writes the IR to **stdout** (default) or to a file path passed via `--ir-out`. The Dart `cs2dart` CLI reads it from stdin or the file.

```
cs2dart-frontend MyProject.csproj | cs2dart transpile --config transpiler.yaml
# or
cs2dart-frontend MyProject.csproj --ir-out project.ir.json
cs2dart transpile project.ir.json --config transpiler.yaml
```

### IR Format

The IR is serialized as **JSON** for the initial implementation (human-readable, easy to debug). A protobuf encoding may be added later for performance on large codebases.

---

## Dart Side

### Why Dart

All pipeline stages after IR ingestion are implemented in Dart because:

- The output is Dart code; Dart tooling (`dart analyze`, `dart format`) is needed for validation
- The `cs2dart` CLI is a Dart executable distributed via `pub.dev`
- All feature specs (transpiler-configuration, namespace-mapping, struct-mapping, event-mapping, nuget-dependency-handling) are Dart implementations
- Tests use Dart's `package:test` and property-based testing libraries

### Components

| Component | Responsibility |
|---|---|
| **IR Consumer** | Reads and validates the IR; rejects unknown IR versions |
| **Config Service** | Loads `transpiler.yaml`; exposes `IConfigService` to all pipeline modules |
| **Namespace Mapper** | Maps C# namespaces to Dart library paths using IR + config |
| **Struct Transpiler** | Converts IR struct nodes to immutable Dart value classes |
| **Event Transpiler** | Converts IR event nodes to Dart streams |
| **NuGet Dependency Handler** | Maps NuGet packages to Dart pub packages; optionally transpiles package source |
| **Dart Code Generator** | Emits `.dart` source files from the transformed IR |
| **Validation & Analysis** | Runs `dart analyze` on generated output; reports diagnostics |

### Process Orchestration

The `cs2dart` CLI orchestrates the full pipeline:

```dart
Future<void> run(TranspileCommand cmd) async {
  // 1. Invoke the .NET frontend as a subprocess
  final irBytes = await DotnetFrontend.invoke(cmd.entryPath, cmd.irOutPath);

  // 2. Load configuration
  final configResult = await ConfigLoader.load(
    entryPath: cmd.entryPath,
    explicitConfigPath: cmd.configPath,
  );
  if (configResult.hasErrors) exit(1);

  // 3. Consume IR
  final ir = IrConsumer.parse(irBytes);

  // 4. Run pipeline modules (each receives IConfigService via DI)
  final dartIr = Pipeline(config: configResult.service!).transform(ir);

  // 5. Emit Dart files
  await DartCodeGenerator.emit(dartIr, cmd.outputDir);

  // 6. Validate
  await DartAnalyzer.run(cmd.outputDir);
}
```

---

## Testing Strategy by Layer

| Layer | Language | Test Tooling |
|---|---|---|
| Roslyn frontend / IR serializer | C# | xUnit, Roslyn test helpers |
| IR schema validation | Dart | `package:test`, golden IR fixtures |
| Config Service | Dart | `package:test`, `package:fast_check` (PBT) |
| Pipeline modules (namespace, struct, event, etc.) | Dart | `package:test`, `package:fast_check` (PBT) |
| Dart code generator | Dart | Golden file tests, `dart analyze` on output |
| End-to-end | Both | Input C# project → expected Dart package (golden tests) |

---

## Key Constraints

1. **The .NET process is a subprocess**, not a library. The Dart side communicates with it only through the IR; there is no in-process FFI or shared memory.
2. **`transpiler.yaml` is read only by the Dart side.** The .NET frontend receives no configuration; it always produces a maximally faithful IR.
3. **The IR version must be checked** before any Dart pipeline module processes it. A version mismatch is a hard error.
4. **The .NET frontend must be installed separately** (as a .NET global tool: `dotnet tool install cs2dart-frontend`). The Dart `cs2dart` package declares it as a required external dependency and checks for its presence at startup.
