# Roslyn Frontend — Design Document

## Overview

The Roslyn Frontend (`Roslyn_Frontend`) is the second stage of the cs2dart transpiler pipeline.
It sits between the `Project_Loader` and the `IR_Builder`, consuming the `Load_Result` produced
by the `Project_Loader` and emitting a `Frontend_Result` that the `IR_Builder` consumes.

Its three core responsibilities are:

1. **SemanticModel querying** — obtaining fully-resolved type information, symbol bindings, and
   constant values from each `CSharpCompilation` in the `Load_Result` via the Roslyn
   `SemanticModel` API.
2. **Syntax tree normalization** — rewriting syntactic sugar and multi-form constructs into a
   single canonical form so that the `IR_Builder` handles a minimal, well-defined vocabulary.
3. **Construct lowering** — transforming LINQ query syntax, async annotations, pattern matching,
   and other high-level constructs into simpler, semantically equivalent forms that map cleanly
   to IR nodes.

The `Roslyn_Frontend` is the **only** pipeline stage permitted to call Roslyn APIs. All
downstream stages operate exclusively on the `Frontend_Result` and must not hold or query Roslyn
objects.

### Interop Architecture

Dart cannot call Roslyn APIs natively. The `Roslyn_Frontend` is therefore implemented as a Dart
class (`RoslynFrontend`) that delegates all Roslyn work to a pool of companion .NET processes
(`cs2dart_roslyn_worker`) via `PipeInteropBridge`. Each worker communicates over its own
stdin/stdout pair using a 4-byte little-endian length-prefixed JSON protocol. The Dart side
sends a serialized `InteropRequest` (project paths, compilation options, metadata references)
and receives back a serialized `FrontendResult` (plain-data records only — no Roslyn types
cross the boundary).

The worker binary is produced by running `dotnet publish` on the `cs2dart_roslyn_worker/`
project as part of the Dart build step (via `build_runner`). The published self-contained
binary is placed at `build/roslyn_worker/cs2dart_roslyn_worker[.exe]`.

`PipeInteropBridge` maintains a pool of worker processes (default size: logical CPU count,
clamped to 1–8). The pool is created lazily on the first `invoke()` call. Each worker handles
one request at a time; concurrent `invoke()` calls are queued and dispatched to the next free
worker. All workers are terminated on `dispose()`.

The interop boundary is the point where Roslyn types are converted to plain-data records. Once
the .NET worker has finished processing a request, it serializes the `FrontendResult` to JSON,
writes the length-prefixed payload to stdout, and waits for the next request. No Roslyn type
ever appears in the Dart heap.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Pipeline_Orchestrator                                               │
│    RoslynFrontend.process(loadResult, config)                        │
└──────────────────────────────┬───────────────────────────────────────┘
                               │  LoadResult (plain-data)
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│  lib/src/roslyn_frontend/roslyn_frontend_impl.dart                   │
│  RoslynFrontend  (implements IRoslynFrontend)                        │
│                                                                      │
│   ┌──────────────────────────────────────────────────────────────┐   │
│   │  PipeInteropBridge  (implements IInteropBridge)              │   │
│   │    ├─ WorkerPool (N worker processes, default = CPU count)   │   │
│   │    │    ├─ WorkerProcess #1  (stdin/stdout, length-prefix)   │   │
│   │    │    ├─ WorkerProcess #2                                  │   │
│   │    │    └─ WorkerProcess #N                                  │   │
│   │    ├─ queue pending invoke() calls                           │   │
│   │    ├─ dispatch to free worker                                │   │
│   │    ├─ serialize InteropRequest → length-prefixed JSON        │   │
│   │    └─ deserialize length-prefixed JSON → FrontendResult      │   │
│   └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│   ┌──────────────────────────────────────────────────────────────┐   │
│   │  FrontendResultAssembler  (Dart-side post-processing)        │   │
│   │    ├─ propagate PL diagnostics from LoadResult               │   │
│   │    ├─ set Frontend_Result.Success                            │   │
│   │    └─ deduplicate diagnostics (RF0012)                       │   │
│   └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────┬───────────────────────────────────────┘
                               │  (stdin/stdout, length-prefixed JSON)
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│  cs2dart_roslyn_worker/  (.NET 8 self-contained console process)     │
│  Built by: dotnet publish -c Release -r <rid> --self-contained true  │
│  Output:   build/roslyn_worker/cs2dart_roslyn_worker[.exe]           │
│                                                                      │
│   ┌──────────────────────────────────────────────────────────────┐   │
│   │  Program.cs  (request loop)                                  │   │
│   │    ├─ read 4-byte LE length from stdin                       │   │
│   │    ├─ read N bytes of UTF-8 JSON                             │   │
│   │    ├─ deserialize → InteropRequest                           │   │
│   │    ├─ invoke WorkerRequestHandler                            │   │
│   │    ├─ serialize FrontendResult → UTF-8 JSON                  │   │
│   │    ├─ write 4-byte LE length to stdout                       │   │
│   │    └─ write N bytes of UTF-8 JSON to stdout                  │   │
│   └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│   ┌──────────────────────────────────────────────────────────────┐   │
│   │  WorkerRequestHandler                                        │   │
│   │    └─ invoke ProjectProcessor per ProjectEntry               │   │
│   └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│   ┌──────────────────────────────────────────────────────────────┐   │
│   │  ProjectProcessor  (one per ProjectEntry)                    │   │
│   │    ├─ obtain SemanticModel per SyntaxTree                    │   │
│   │    ├─ NormalizationPipeline (ordered passes)                 │   │
│   │    │    ├─ PartialMergingPass                                │   │
│   │    │    ├─ LinqNormalizationPass                             │   │
│   │    │    ├─ AsyncAnnotationPass                               │   │
│   │    │    ├─ PatternMatchingPass                               │   │
│   │    │    ├─ AutoPropertyPass                                  │   │
│   │    │    ├─ UsingLockCheckedPass                              │   │
│   │    │    ├─ ForeachPass                                       │   │
│   │    │    ├─ IndexerPass                                       │   │
│   │    │    ├─ ExtensionMethodPass                               │   │
│   │    │    └─ ExplicitInterfacePass                             │   │
│   │    ├─ TypeAnnotationEnricher                                 │   │
│   │    ├─ AttributeExtractor                                     │   │
│   │    ├─ SymbolTableBuilder                                     │   │
│   │    └─ DeclarationMetadataExtractor                           │   │
│   └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│   ┌──────────────────────────────────────────────────────────────┐   │
│   │  WorkerResponseSerializer                                    │   │
│   │    └─ serialize FrontendResult → JSON (plain-data only)      │   │
│   └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
                               │  FrontendResult (plain-data JSON)
                               ▼
                         IR_Builder
```

All Roslyn types are confined to the .NET worker processes. The `FrontendResult` that crosses
the interop boundary contains only plain-data records.

---

## Components and Interfaces

### `IRoslynFrontend`

The public interface exposed to the `Orchestrator`:

```dart
abstract interface class IRoslynFrontend {
  /// Processes [loadResult] using [config] for all configuration values.
  ///
  /// Returns a [FrontendResult] that is always non-null.
  /// [FrontendResult.success] is false when any Error-severity diagnostic
  /// is present in [FrontendResult.diagnostics].
  Future<FrontendResult> process(LoadResult loadResult, IConfigService config);
}
```

### `RoslynFrontend`

The production implementation. Manages the interop bridge lifecycle and assembles the final
`FrontendResult`.

```dart
final class RoslynFrontend implements IRoslynFrontend {
  final IInteropBridge _bridge;
  final FrontendResultAssembler _assembler;

  const RoslynFrontend({
    required IInteropBridge bridge,
    FrontendResultAssembler? assembler,
  });

  @override
  Future<FrontendResult> process(LoadResult loadResult, IConfigService config);
}
```

### `IInteropBridge`

Abstracts the .NET worker process communication. Injected into `RoslynFrontend` so tests can
supply a fake without spawning a real .NET process.

```dart
abstract interface class IInteropBridge {
  /// Sends [request] to a free worker and returns the deserialized response.
  ///
  /// Throws [InteropException] if the worker process exits unexpectedly or
  /// returns a malformed response.
  Future<FrontendResult> invoke(InteropRequest request);

  /// Terminates all worker processes in the pool.
  Future<void> dispose();
}
```

### `PipeInteropBridge`

The production implementation of `IInteropBridge`. Manages a pool of `cs2dart_roslyn_worker`
processes and dispatches requests to free workers over stdin/stdout.

```dart
final class PipeInteropBridge implements IInteropBridge {
  /// Number of worker processes to maintain. Defaults to [Platform.numberOfProcessors],
  /// clamped to the range [1, 8].
  final int poolSize;

  /// Absolute path to the worker binary.
  /// Defaults to <packageRoot>/build/roslyn_worker/cs2dart_roslyn_worker[.exe].
  final String workerBinaryPath;

  PipeInteropBridge({int? poolSize, String? workerBinaryPath});

  @override
  Future<FrontendResult> invoke(InteropRequest request);

  @override
  Future<void> dispose();
}
```

**Pool lifecycle:**
1. On the first `invoke()` call, `PipeInteropBridge` spawns `poolSize` worker processes using
   `dart:io Process.start()`, capturing each process's stdin and stdout.
2. Each worker is tracked as either *free* or *busy*. A free worker is immediately assigned to
   an incoming `invoke()` call; if all workers are busy the call is queued.
3. When a worker finishes a request it is marked free and the next queued call (if any) is
   dispatched to it.
4. If a worker exits unexpectedly (non-zero exit code or stdout EOF before a response is
   received), its pending `invoke()` future completes with an `InteropException` containing the
   worker's captured stderr. A replacement worker is spawned to restore pool size.
5. `dispose()` sends EOF to each worker's stdin and waits for all processes to exit, then
   cancels any queued requests with an `InteropException`.

**Wire protocol (per request/response pair):**
```
Request  (Dart → worker stdin):
  [4 bytes, little-endian uint32]  byte length of the UTF-8 JSON payload
  [N bytes, UTF-8]                 JSON-encoded InteropRequest

Response (worker stdout → Dart):
  [4 bytes, little-endian uint32]  byte length of the UTF-8 JSON payload
  [N bytes, UTF-8]                 JSON-encoded FrontendResult
```

The worker writes all diagnostic/error text to stderr only. Stdout carries only the
length-prefixed JSON response. This separation allows `PipeInteropBridge` to capture stderr
independently for error reporting without interfering with the response stream.

### `WorkerBinaryLocator`

A small helper that resolves the worker binary path at runtime:

```dart
final class WorkerBinaryLocator {
  /// Returns the absolute path to the worker binary.
  ///
  /// Search order:
  ///   1. Explicit [override] path (if provided).
  ///   2. <packageRoot>/build/roslyn_worker/cs2dart_roslyn_worker[.exe]
  ///
  /// Throws [InteropException] if the binary does not exist at the resolved path.
  static String resolve({String? override});
}
```

### `InteropRequest`

The plain-data payload sent to the .NET worker:

```dart
final class InteropRequest {
  /// Serialized LoadResult projects (paths, compilation options, references).
  final List<ProjectEntryRequest> projects;

  /// Active configuration values relevant to the frontend.
  final FrontendConfig config;

  const InteropRequest({required this.projects, required this.config});
}

/// Configuration values extracted from IConfigService for the worker.
final class FrontendConfig {
  final String linqStrategy;          // "preserve_functional" | "lower_to_loops"
  final bool nullabilityEnabled;
  final Map<String, bool> experimentalFeatures;

  const FrontendConfig({
    required this.linqStrategy,
    required this.nullabilityEnabled,
    required this.experimentalFeatures,
  });
}
```

### `FrontendResultAssembler`

Dart-side post-processing after the interop response is received:

```dart
final class FrontendResultAssembler {
  /// Merges [workerResult] with [loadResult] diagnostics and sets Success.
  ///
  /// - Prepends all PL-prefixed diagnostics from [loadResult.diagnostics].
  /// - Sets [FrontendResult.success] based on absence of Error diagnostics.
  FrontendResult assemble(
    FrontendResult workerResult,
    LoadResult loadResult,
  );
}
```

---

## .NET Worker Project (`cs2dart_roslyn_worker`)

### Project Structure

```
cs2dart_roslyn_worker/
├── cs2dart_roslyn_worker.csproj   (.NET 8, net8.0, self-contained publish)
├── Program.cs                     (entry point: request loop)
├── WorkerRequestHandler.cs        (deserialize → ProjectProcessor → serialize)
├── ProjectProcessor.cs            (per-ProjectEntry normalization pipeline)
├── NormalizationPipeline/
│   ├── INormalizationPass.cs
│   ├── PartialMergingPass.cs
│   ├── LinqNormalizationPass.cs
│   ├── AsyncAnnotationPass.cs
│   ├── PatternMatchingPass.cs
│   ├── AutoPropertyPass.cs
│   ├── UsingLockCheckedPass.cs
│   ├── ForeachPass.cs
│   ├── IndexerPass.cs
│   ├── ExtensionMethodPass.cs
│   └── ExplicitInterfacePass.cs
├── Enrichment/
│   ├── TypeAnnotationEnricher.cs
│   ├── AttributeExtractor.cs
│   ├── DeclarationMetadataExtractor.cs
│   └── SymbolTableBuilder.cs
├── Models/
│   └── (C# mirror of the Dart plain-data models for JSON serialization)
└── Serialization/
    ├── InteropRequestDeserializer.cs
    └── FrontendResultSerializer.cs
```

### `cs2dart_roslyn_worker.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AllowUnsafeBlocks>false</AllowUnsafeBlocks>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.*" />
  </ItemGroup>
</Project>
```

### `Program.cs` — Request Loop

The worker runs a synchronous request loop on stdin/stdout. It does not use async I/O at the
top level to keep the protocol simple and avoid buffering surprises.

```csharp
// Pseudocode — actual implementation uses BinaryReader/BinaryWriter
while (true) {
    // 1. Read 4-byte LE length prefix from stdin.
    int length = ReadLittleEndianInt32(stdin);

    // 2. Read exactly `length` bytes of UTF-8 JSON.
    string json = ReadUtf8String(stdin, length);

    // 3. Deserialize to InteropRequest.
    var request = InteropRequestDeserializer.Deserialize(json);

    // 4. Process.
    var result = WorkerRequestHandler.Handle(request);

    // 5. Serialize FrontendResult to JSON.
    string responseJson = FrontendResultSerializer.Serialize(result);
    byte[] responseBytes = Encoding.UTF8.GetBytes(responseJson);

    // 6. Write 4-byte LE length prefix + JSON bytes to stdout.
    WriteLittleEndianInt32(stdout, responseBytes.Length);
    stdout.Write(responseBytes);
    stdout.Flush();
}
```

All exceptions are caught at the top level, written to stderr, and cause a non-zero exit.

### Build Integration

The Dart `build_runner` step invokes `dotnet publish` via a `Builder` defined in
`tool/build/roslyn_worker_builder.dart`:

```
dotnet publish cs2dart_roslyn_worker/cs2dart_roslyn_worker.csproj \
  -c Release \
  -r <current-RID>  \
  --self-contained true \
  -o build/roslyn_worker/
```

The runtime identifier (`<current-RID>`) is determined at build time from `Platform.operatingSystem`:
- `linux` → `linux-x64`
- `macos` → `osx-x64` (or `osx-arm64` on Apple Silicon)
- `windows` → `win-x64`

The builder declares `cs2dart_roslyn_worker/**` as inputs and
`build/roslyn_worker/cs2dart_roslyn_worker[.exe]` as output, so `build_runner` only re-runs
`dotnet publish` when the worker source changes.

---

## Data Models

### `FrontendResult`

The complete output of the `Roslyn_Frontend`:

```dart
final class FrontendResult {
  /// One Frontend_Unit per Project_Entry, in the same order as
  /// Load_Result.Projects (topological, leaf-first).
  final List<FrontendUnit> units;

  /// Aggregated diagnostics: PL diagnostics propagated from Load_Result,
  /// followed by RF-prefixed diagnostics from the frontend, followed by
  /// CS-prefixed Roslyn compiler diagnostics.
  final List<Diagnostic> diagnostics;

  /// True if and only if diagnostics contains no Error-severity entry.
  final bool success;

  const FrontendResult({
    required this.units,
    required this.diagnostics,
    required this.success,
  });
}
```

### `FrontendUnit`

The normalized, fully-annotated representation of one C# project:

```dart
final class FrontendUnit {
  /// The assembly name of the project.
  final String projectName;

  /// Output kind: Exe, Library, or WinExe.
  final OutputKind outputKind;

  /// Resolved target framework moniker, e.g. "net8.0".
  final String targetFramework;

  /// Resolved C# language version string, e.g. "12.0".
  final String langVersion;

  /// True when <Nullable>enable</Nullable> is set in the project file.
  final bool nullableEnabled;

  /// Resolved NuGet package references (propagated from ProjectEntry).
  final List<PackageReferenceEntry> packageReferences;

  /// One Normalized_SyntaxTree per source file, in alphabetical order
  /// by file path. Partial class merging may reduce the logical count
  /// of declaration nodes but does not reduce the tree count.
  final List<NormalizedSyntaxTree> normalizedTrees;

  const FrontendUnit({
    required this.projectName,
    required this.outputKind,
    required this.targetFramework,
    required this.langVersion,
    required this.nullableEnabled,
    required this.packageReferences,
    required this.normalizedTrees,
  });
}
```

### `NormalizedSyntaxTree`

A rewritten syntax tree (plain-data nodes, no Roslyn types) paired with a `SymbolTable`:

```dart
final class NormalizedSyntaxTree {
  /// Absolute path to the source file this tree was produced from.
  final String filePath;

  /// The root node of the rewritten, annotated syntax tree.
  /// Contains only plain-data node types — no Roslyn types.
  final SyntaxNode root;

  /// Maps every named-reference node in [root] to its resolved symbol.
  /// Key: node identity (stable integer ID assigned during normalization).
  /// Value: ResolvedSymbol record.
  final SymbolTable symbolTable;

  const NormalizedSyntaxTree({
    required this.filePath,
    required this.root,
    required this.symbolTable,
  });
}
```

### `SymbolTable`

A dictionary mapping node IDs to resolved symbols:

```dart
final class SymbolTable {
  /// Maps node identity (assigned during normalization) to its resolved symbol.
  final Map<int, ResolvedSymbol> entries;

  const SymbolTable({required this.entries});

  ResolvedSymbol? lookup(int nodeId) => entries[nodeId];
}
```

### `ResolvedSymbol`

A plain-data record representing a fully-resolved Roslyn symbol:

```dart
final class ResolvedSymbol {
  /// Fully-qualified name, e.g. "System.Collections.Generic.List<T>".
  final String fullyQualifiedName;

  /// The assembly that defines this symbol, e.g. "System.Collections".
  final String assemblyName;

  /// The kind of symbol.
  final SymbolKind kind;

  /// NuGet package ID when the symbol comes from an external package; null
  /// when the symbol is defined in the same compilation or the BCL.
  final String? sourcePackageId;

  /// Source location of the symbol's declaration; null for external symbols.
  final SourceLocation? sourceLocation;

  /// Compile-time constant value for const symbols; null otherwise.
  final Object? constantValue;

  const ResolvedSymbol({
    required this.fullyQualifiedName,
    required this.assemblyName,
    required this.kind,
    this.sourcePackageId,
    this.sourceLocation,
    this.constantValue,
  });
}

enum SymbolKind {
  type,
  method,
  field,
  property,
  event,
  local,
  parameter,
  unresolved,  // sentinel: Roslyn could not bind this reference
}
```

### `IR_Type`

The type annotation attached to every expression node in the `NormalizedSyntaxTree`. Expressed
as a sealed class hierarchy so the `IR_Builder` can pattern-match exhaustively:

```dart
sealed class IrType {}

/// A named type, e.g. int, string, List<T>.
final class NamedType extends IrType {
  final ResolvedSymbol symbol;
  final List<IrType> typeArguments;
  const NamedType({required this.symbol, this.typeArguments = const []});
}

/// A nullable wrapper: T? (both reference and value types).
final class NullableType extends IrType {
  final IrType inner;
  const NullableType({required this.inner});
}

/// A function type: (T1, T2) -> TReturn.
final class FunctionType extends IrType {
  final List<IrType> parameterTypes;
  final IrType returnType;
  const FunctionType({required this.parameterTypes, required this.returnType});
}

/// dynamic — emits a Warning diagnostic.
final class DynamicType extends IrType {
  const DynamicType();
}

/// Sentinel: SemanticModel returned null or error type.
final class UnresolvedType extends IrType {
  const UnresolvedType();
}
```

### Annotation and Marker Types

Annotations are attached to `SyntaxNode` instances as structured metadata. They are plain-data
records with no Roslyn types.

```dart
/// Attached to method/local-function nodes that carry the async modifier.
final class AsyncAnnotation {
  final bool isAsync;
  final bool isIterator;
  final bool isFireAndForget;   // async void
  final ResolvedSymbol? returnTypeSymbol;  // Task, Task<T>, ValueTask, etc.
  const AsyncAnnotation({
    required this.isAsync,
    this.isIterator = false,
    this.isFireAndForget = false,
    this.returnTypeSymbol,
  });
}

/// Attached to await expressions that had ConfigureAwait(false).
final class ConfigureAwaitAnnotation {
  final bool configureAwait;  // always false when present
  const ConfigureAwaitAnnotation({required this.configureAwait});
}

/// Attached to arithmetic operations inside checked/unchecked blocks.
final class OverflowCheckAnnotation {
  final bool checked;  // true = checked, false = unchecked
  const OverflowCheckAnnotation({required this.checked});
}

/// Attached to foreach loop nodes with the resolved element type.
final class ForeachAnnotation {
  final IrType elementType;
  const ForeachAnnotation({required this.elementType});
}

/// Attached to indexer get/set method declarations.
final class IndexerAnnotation {
  final bool isIndexer;
  const IndexerAnnotation({required this.isIndexer});
}

/// Attached to extension method declarations.
final class ExtensionAnnotation {
  final bool isExtension;
  final ResolvedSymbol extendedType;
  const ExtensionAnnotation({
    required this.isExtension,
    required this.extendedType,
  });
}

/// Attached to explicit interface implementation method declarations.
final class ExplicitInterfaceAnnotation {
  final ResolvedSymbol implementedInterface;
  const ExplicitInterfaceAnnotation({required this.implementedInterface});
}

/// Attached to nodes that cannot be normalized or lowered.
final class UnsupportedAnnotation {
  final String description;
  final String originalSourceSpan;
  const UnsupportedAnnotation({
    required this.description,
    required this.originalSourceSpan,
  });
}

/// Attached to declaration nodes with resolved modifier flags.
final class DeclarationModifiers {
  final Accessibility accessibility;
  final bool isStatic;
  final bool isAbstract;
  final bool isVirtual;
  final bool isOverride;
  final bool isSealed;
  final bool isReadonly;
  final bool isConst;
  final bool isExtern;
  final bool isNew;
  final bool isOperator;
  final bool isConversion;
  final bool isImplicit;
  final bool isExplicit;
  final bool isExtension;
  final bool isIndexer;
  const DeclarationModifiers({
    required this.accessibility,
    this.isStatic = false,
    this.isAbstract = false,
    this.isVirtual = false,
    this.isOverride = false,
    this.isSealed = false,
    this.isReadonly = false,
    this.isConst = false,
    this.isExtern = false,
    this.isNew = false,
    this.isOperator = false,
    this.isConversion = false,
    this.isImplicit = false,
    this.isExplicit = false,
    this.isExtension = false,
    this.isIndexer = false,
  });
}

enum Accessibility {
  public,
  internal,
  protected,
  protectedInternal,
  privateProtected,
  private,
}
```

### RF Diagnostic Codes

All diagnostics emitted by the `Roslyn_Frontend` use the `RF` prefix. No other pipeline
component uses this prefix.

| Code | Severity | Condition |
|---|---|---|
| `RF0001` | Warning | Unresolved symbol (binding error); `Kind = Unresolved` sentinel recorded |
| `RF0002` | Warning | Normalization rewrite could not be applied; `Unsupported` marker attached |
| `RF0003` | Warning | Unsupported construct encountered (non-fatal); `Unsupported` marker attached |
| `RF0004` | Error | Unsupported construct in a position that makes the declaration semantically incomplete |
| `RF0005` | Error | `unsafe` block encountered; cannot be approximated in Dart |
| `RF0006` | Warning | `goto` or labeled statement encountered; no Dart equivalent |
| `RF0007` | Warning | `dynamic`-typed expression encountered |
| `RF0008` | Warning | `SemanticModel.GetTypeInfo` returned null or error type; `UnresolvedType` marker attached |
| `RF0009` | Info | `async void` (fire-and-forget) method encountered |
| `RF0010` | Info | Unknown attribute encountered; attached as `UnknownAttribute` record |
| `RF0011` | Warning | Project skipped due to upstream `Error`-severity diagnostics in `Load_Result` |
| `RF0012` | Warning | Duplicate diagnostic suppressed (same source location and code) |

---

## Processing Pipeline and Data Flow

```
LoadResult
  │
  ├─ propagate PL diagnostics → FrontendResult.diagnostics
  │
  └─ for each ProjectEntry (topological order, leaf-first):
       │
       ├─ skip if project has Error diagnostics → emit RF0011 Warning
       │
       ├─ sort SyntaxTree paths alphabetically
       │
       └─ for each SyntaxTree (alphabetical by file path):
            │
            ├─ [cross-file] PartialMergingPass
            │    └─ load all partial parts simultaneously, merge, release
            │
            ├─ obtain SemanticModel via Compilation.GetSemanticModel(tree)
            │
            ├─ NormalizationPipeline (fixed pass order):
            │    1. LinqNormalizationPass
            │    2. AsyncAnnotationPass
            │    3. PatternMatchingPass
            │    4. AutoPropertyPass
            │    5. UsingLockCheckedPass
            │    6. ForeachPass
            │    7. IndexerPass
            │    8. ExtensionMethodPass
            │    9. ExplicitInterfacePass
            │
            ├─ TypeAnnotationEnricher
            │    └─ annotate every expression node with IR_Type
            │
            ├─ AttributeExtractor
            │    └─ attach structured attribute records to declarations
            │
            ├─ DeclarationMetadataExtractor
            │    └─ attach DeclarationModifiers to all declarations
            │
            ├─ SymbolTableBuilder
            │    └─ resolve all named references → SymbolTable entries
            │
            ├─ release SemanticModel reference
            │
            └─ emit NormalizedSyntaxTree { filePath, root, symbolTable }
       │
       ├─ release CSharpCompilation reference
       │
       └─ emit FrontendUnit
  │
  └─ assemble FrontendResult { units, diagnostics, success }
```

### Processing Order Guarantees

- Projects are processed in the order provided by `Load_Result.Projects` (topological,
  leaf-first). The `Roslyn_Frontend` does not reorder projects.
- Within a project, `SyntaxTree` objects are processed in alphabetical order by file path.
  This is the sole source of determinism for tree-level processing.
- Normalization passes run in the fixed order listed above. No pass may depend on the output
  of a later pass.
- The `SymbolTableBuilder` runs after all normalization passes so that it resolves symbols in
  the final, rewritten tree rather than the original tree.

---

## Normalization Passes

### Pass 0: Partial Class Merging (Cross-File)

**Trigger**: Any `SyntaxTree` in the project contains a `partial` class, struct, or interface
declaration.

**Algorithm**:
1. Scan all `SyntaxTree` paths in the project for `partial` type declarations.
2. Group partial parts by fully-qualified type name (obtained from `SemanticModel`).
3. For each group with more than one part, load all contributing trees simultaneously.
4. Merge all partial parts into a single `ClassDeclarationSyntax` node:
   - Concatenate member lists in alphabetical order by member name (tie-break: source order).
   - Merge attribute lists (deduplicating by attribute type).
   - Merge base lists (deduplicating by type symbol).
   - Retain the `partial` keyword on the merged node as an `IsMergedPartial = true` annotation.
5. Replace each original partial declaration in its source tree with either the merged node
   (for the alphabetically-first file) or an empty placeholder (for subsequent files).
6. Release all loaded trees except the one that hosts the merged node.

**Rationale**: Partial class merging is the only cross-file pass. It must run before all other
passes because subsequent passes operate on the merged declaration. Loading only the contributing
trees (not all trees in the project) satisfies the memory contract in Requirement 14.5.

---

### Pass 1: LINQ Normalization

**Trigger**: Any `QueryExpressionSyntax` node in the tree.

**Algorithm**:
1. Walk the tree bottom-up, visiting each `QueryExpressionSyntax`.
2. Rewrite to equivalent method-chain form using the standard LINQ translation rules:
   - `from x in xs` → source expression
   - `where pred` → `.Where(x => pred)`
   - `select proj` → `.Select(x => proj)`
   - `orderby key` → `.OrderBy(x => key)` / `.OrderByDescending(x => key)`
   - `group g by key` → `.GroupBy(x => key, x => g)`
   - `join y in ys on lk equals rk` → `.Join(ys, x => lk, y => rk, (x, y) => ...)`
   - `let v = expr` → `.Select(x => new { x, v = expr })` with range variable threading
3. Annotate each resulting method-chain call node with:
   - `ResolvedSymbol` for the `System.Linq.Enumerable` or `System.Linq.Queryable` method.
   - `elementInputType`: `IR_Type` of the input sequence element.
   - `resultType`: `IR_Type` of the call's return value.
4. Annotate each lambda argument with resolved parameter and return types.

**Config branch** (`IConfigService.linqStrategy`):
- `preserve_functional` (default): emit the method-chain form with type annotations.
- `lower_to_loops`: after rewriting to method-chain form, apply a second rewrite that converts
  the chain to equivalent `foreach` / local variable form. The loop-lowering rewrite is applied
  only to chains that consist entirely of `Where`, `Select`, `OrderBy`, `Take`, `Skip`, and
  `ToList`/`ToArray`. Chains containing `GroupBy`, `Join`, `Aggregate`, or `ToDictionary` are
  left in method-chain form with an `RF0002` Warning noting partial lowering.

---

### Pass 2: Async Annotation

**Trigger**: Any `MethodDeclarationSyntax` or `LocalFunctionStatementSyntax` with the `async`
modifier, or any method whose body contains `yield` statements.

**Algorithm**:
1. For each `async` method/local function:
   - Attach `AsyncAnnotation { isAsync: true }`.
   - Resolve the return type symbol (`Task`, `Task<T>`, `ValueTask`, `ValueTask<T>`) and store
     in `AsyncAnnotation.returnTypeSymbol`.
   - If return type is `void`, set `isFireAndForget = true` and emit `RF0009` Info.
2. For each method whose body contains `yield` statements and whose return type is
   `IEnumerable<T>`, `IAsyncEnumerable<T>`, or `IEnumerator<T>`:
   - Attach `AsyncAnnotation { isIterator: true }`.
3. For each `ConfigureAwait(false)` call expression:
   - Rewrite to the inner `await` expression.
   - Attach `ConfigureAwaitAnnotation { configureAwait: false }` to the rewritten `await` node.
4. `await` expressions that are not `ConfigureAwait` calls are preserved as-is.

**Rationale**: The `IR_Builder` needs `IsAsync` and `IsIterator` flags to emit correct Dart
`async`/`async*` methods. Preserving `await` expressions (rather than lowering to state machines)
keeps the normalized tree structurally close to the source, making the `IR_Builder`'s job simpler.

---

### Pass 3: Pattern Matching Normalization

**Trigger**: Any `SwitchExpressionSyntax`, `SwitchStatementSyntax` with pattern cases, or
`IsPatternExpressionSyntax` node.

**Algorithm**:
1. **Switch expressions** (`SwitchExpressionSyntax`): rewrite each arm to a canonical
   `SwitchExpressionArm { pattern, whenClause?, resultExpression }`.
2. **Switch statements** with pattern cases: rewrite each `case` to carry a structured `Pattern`
   node rather than a raw expression.
3. **Type patterns** (`case Foo f:`): normalize to `TypePattern { resolvedSymbol, variableName }`.
4. **Property patterns** (`case { X: 1, Y: 2 }:`): normalize to
   `PropertyPattern { [(propertySymbol, subPattern)] }`.
5. **Positional patterns** (`case (int x, string y):`): normalize to
   `PositionalPattern { [(position, subPattern)], deconstructSymbol }`.
6. **`is` expressions** (`x is Foo f`): normalize to
   `IsExpression { testedTypeSymbol, variableName? }`.
7. **Unsupported patterns** (list patterns, slice patterns, `or`/`and`/`not` combinators not
   yet in the supported set): substitute `UnsupportedPattern { sourceSpan }` and emit `RF0002`.

---

### Pass 4: Auto-Property Expansion

**Trigger**: Any `PropertyDeclarationSyntax` with auto-accessor bodies (no explicit body).

**Algorithm**:
1. For each auto-property `public int X { get; set; }`:
   - Synthesize a backing field: `private int _x;` (name: camelCase of property name, prefixed
     with `_`). Attach `IsSynthesizedBackingField = true` annotation.
   - Rewrite getter to: `get { return _x; }`.
   - Rewrite setter to: `set { _x = value; }`.
   - For init-only setters (`init`), rewrite to `set` with an `IsInitOnly = true` annotation.
2. For get-only auto-properties (`public int X { get; }`):
   - Synthesize a `readonly` backing field.
   - Rewrite getter to return the field.
   - No setter is emitted.

---

### Pass 5: Using / Lock / Checked Rewriting

**`using` statements and declarations**:
- `using (var r = expr) { body }` → `var r = expr; try { body } finally { r.Dispose(); }`
- `using var r = expr;` (C# 8 declaration form) → same `try/finally` pattern, scoped to the
  enclosing block.

**`lock` statements**:
- `lock (obj) { body }` →
  ```
  bool __lockTaken = false;
  try {
    Monitor.Enter(obj, ref __lockTaken);
    body
  } finally {
    if (__lockTaken) Monitor.Exit(obj);
  }
  ```

**`checked` / `unchecked` blocks**:
- Do not emit wrapper nodes.
- Walk all arithmetic operations (`+`, `-`, `*`, `/`, `<<`, explicit numeric casts) inside the
  block and attach `OverflowCheckAnnotation { checked: true/false }` to each.

---

### Pass 6: Foreach Expansion

**Trigger**: Any `ForEachStatementSyntax` node.

**Algorithm**:
1. Resolve the element type of the collection via `SemanticModel.GetTypeInfo`.
2. Attach `ForeachAnnotation { elementType }` to the `ForEachStatementSyntax` node.
3. The loop body and iteration variable are preserved as-is; only the annotation is added.

**Rationale**: The `IR_Builder` needs the resolved element type to emit a typed Dart `for-in`
loop. Preserving the `foreach` structure (rather than lowering to `GetEnumerator`/`MoveNext`)
keeps the normalized tree readable and maps cleanly to Dart's `for (var x in xs)` form.

---

### Pass 7: Indexer Normalization

**Trigger**: Any `IndexerDeclarationSyntax` node.

**Algorithm**:
1. Rewrite the indexer to explicit `get_Item` / `set_Item` method declarations.
2. Attach `IndexerAnnotation { isIndexer: true }` to each generated method.
3. The parameter list and accessor bodies are preserved.

---

### Pass 8: Extension Method Normalization

**Trigger**: Any `MethodDeclarationSyntax` inside a `static` class that has the `this` modifier
on its first parameter.

**Algorithm**:
1. Rewrite to a regular static method declaration (remove the `this` modifier from the first
   parameter).
2. Attach `ExtensionAnnotation { isExtension: true, extendedType: resolvedSymbol }` where
   `extendedType` is the resolved `ResolvedSymbol` of the first parameter's type.

---

### Pass 9: Explicit Interface Implementation Normalization

**Trigger**: Any `MethodDeclarationSyntax` or `PropertyDeclarationSyntax` with an explicit
interface specifier (e.g., `IFoo.Bar()`).

**Algorithm**:
1. Rewrite to a regular method/property declaration (remove the explicit interface qualifier
   from the name).
2. Attach `ExplicitInterfaceAnnotation { implementedInterface: resolvedSymbol }` where
   `implementedInterface` is the resolved `ResolvedSymbol` of the interface.

---

## Type Annotation Enrichment

After all normalization passes, the `TypeAnnotationEnricher` walks the rewritten tree and
annotates every expression node with its resolved `IR_Type`.

**Algorithm**:
1. Walk the tree in post-order (children before parents).
2. For each expression node, call `SemanticModel.GetTypeInfo(node).Type`.
3. Convert the Roslyn `ITypeSymbol` to an `IR_Type`:
   - Named types → `NamedType { symbol, typeArguments }`.
   - Nullable reference types (when `NullableEnabled`) → `NullableType { inner }`.
   - Nullable value types (`int?`, `Nullable<T>`) → `NullableType { inner }` always.
   - `dynamic` → `DynamicType`; emit `RF0007` Warning.
   - Null/error type → `UnresolvedType`; emit `RF0008` Warning.
4. For `var`-typed local variable declarations, replace the `var` keyword node with the
   inferred concrete type annotation.
5. For lambda expressions, annotate with `FunctionType { parameterTypes, returnType }`.
6. For `const` expressions, call `SemanticModel.GetConstantValue(node)` and store the result
   in the node's `constantValue` field.

---

## Attribute Extraction

The `AttributeExtractor` runs after type annotation enrichment and attaches structured attribute
records to all declaration nodes.

**Supported attributes** (extracted as structured records):

| Attribute | Structured fields |
|---|---|
| `[Obsolete]` | `message`, `isError` |
| `[Serializable]` | (no fields) |
| `[Flags]` | (no fields; enum only) |
| `[DllImport]` | `dllName`, `entryPoint`, `callingConvention`, `charSet` |
| `[StructLayout]` | `layoutKind`, `pack`, `size`, `charSet` |
| `[MethodImpl]` | `methodImplOptions` |
| `[CallerMemberName]` | (no fields) |
| `[CallerFilePath]` | (no fields) |
| `[CallerLineNumber]` | (no fields) |
| `[NotNull]` | (no fields) |
| `[MaybeNull]` | (no fields) |
| `[AllowNull]` | (no fields) |
| `[DisallowNull]` | (no fields) |

**Algorithm**:
1. For each declaration node, iterate `SemanticModel.GetDeclaredSymbol(node).GetAttributes()`.
2. Exclude any `AttributeData` whose `ApplicationSyntaxReference` is `null` (compiler-synthesized
   attributes such as `[CompilerGenerated]`, `[IteratorStateMachine]`). This exclusion is silent.
3. For each remaining `AttributeData`:
   - If the attribute's fully-qualified type name is in the supported set, extract constructor
     and named arguments and attach a typed structured record.
   - For `typeof(T)` constructor arguments, resolve `T` to its `ResolvedSymbol`.
   - If the attribute is not in the supported set, attach an `UnknownAttribute { fullyQualifiedName, rawArgumentText }` record and emit `RF0010` Info.
4. Every source-declared attribute (with non-null `ApplicationSyntaxReference`) must appear in
   the output — either as a structured record or as an `UnknownAttribute`. No attribute is
   silently discarded.

---

## Unsupported Construct Handling

When the `Roslyn_Frontend` encounters a C# construct it cannot normalize or lower, it applies
the following policy:

1. **Annotate**: attach `UnsupportedAnnotation { description, originalSourceSpan }` to the node.
2. **Emit diagnostic**: emit an `RF`-prefixed diagnostic (severity depends on construct):
   - `unsafe` blocks → `RF0005` Error (cannot be approximated in Dart).
   - `goto` / labeled statements → `RF0006` Warning.
   - All other unsupported constructs → `RF0003` Warning (or `RF0004` Error if the construct
     makes the containing declaration semantically incomplete).
3. **Continue**: do not abort the tree. Continue processing all remaining nodes.
4. **Preserve**: leave the original node in place with the `UnsupportedAnnotation` attached.
   The `IR_Builder` will see the `UnsupportedAnnotation` and emit a stub or skip the node.

**Unsupported construct list** (non-exhaustive):

| Construct | Diagnostic | Notes |
|---|---|---|
| `unsafe` blocks | RF0005 Error | Entire block annotated |
| `fixed` statements | RF0005 Error | Inside unsafe context |
| `stackalloc` | RF0005 Error | Pointer arithmetic |
| `__arglist` | RF0003 Warning | Variadic interop |
| `__makeref` / `__reftype` / `__refvalue` | RF0003 Warning | TypedReference |
| `goto` / labeled statements | RF0006 Warning | No Dart equivalent |
| Unsupported pattern combinators | RF0002 Warning | `or`, `and`, `not` (future) |

---

## Memory Management Strategy

The `Roslyn_Frontend` follows a strict per-file release policy to keep memory usage proportional
to the size of one file rather than the entire solution.

1. **SemanticModel release**: after completing all queries and annotations for a `SyntaxTree`,
   the reference to that tree's `SemanticModel` is set to `null` (or dropped from scope). The
   .NET GC can then collect it.
2. **CSharpCompilation release**: after all `SyntaxTree` objects within a project have been
   processed and their `NormalizedSyntaxTree` entries emitted, the reference to the
   `CSharpCompilation` is released.
3. **Partial class merging exception**: during the `PartialMergingPass`, only the trees that
   contribute to the same partial type are loaded simultaneously. After the merged declaration
   is produced, all contributing trees except the host tree are released.
4. **No Roslyn types in FrontendResult**: the `FrontendResult` contains only plain-data records.
   The .NET worker serializes the result to JSON before sending it to the Dart side, ensuring
   no Roslyn object crosses the interop boundary.

---

## Determinism Strategy

The `Roslyn_Frontend` achieves deterministic output through the following rules:

1. **Project order**: projects are processed in the order provided by `Load_Result.Projects`
   (topological, leaf-first). The frontend does not reorder projects.
2. **File order**: `SyntaxTree` objects within a project are processed in alphabetical order by
   absolute file path.
3. **Collection ordering**: all collections in `SymbolTable` entries and annotation lists are
   sorted in canonical order (alphabetical by fully-qualified name) when source order is not
   semantically significant.
4. **No environment-dependent data**: no timestamps, process IDs, random values, or
   environment-dependent data are embedded in any `FrontendResult` field.
5. **Partial merging order**: merged member lists are ordered alphabetically by member name,
   with source order as a tie-breaker within the same file.
6. **Diagnostic ordering**: diagnostics are ordered by source file path, then line number, then
   column, then diagnostic code. Duplicate diagnostics (same source location and code) are
   suppressed after the first occurrence (emit `RF0012` Warning for the suppression).

---

## Configuration Integration

The `Roslyn_Frontend` receives all configuration through `IConfigService`. It does not read
`transpiler.yaml` directly.

| Config accessor | Effect on frontend |
|---|---|
| `linqStrategy` | Controls LINQ normalization output (Pass 1) |
| `nullability` | Informs `NullableType` wrapping in type annotation enrichment |
| `experimentalFeatures['roslyn_frontend.<feature>']` | Enables experimental normalization passes |

All other `IConfigService` accessors are not consumed by the `Roslyn_Frontend`. When all
accessors return their default values, all default normalization rules are applied without error.

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a
system — essentially, a formal statement about what the system should do. Properties serve as the
bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Determinism

*For any* valid `LoadResult` input, invoking `process()` twice with the same input SHALL produce
`FrontendResult` values that are structurally and value-equal — same `success`, same
`diagnostics`, and same `normalizedTrees` content in every `FrontendUnit`.

**Validates: Requirements 11.1–11.5, 15.1**

---

### Property 2: Type Completeness

*For any* `NormalizedSyntaxTree` in a `FrontendResult`, every expression node in the tree SHALL
carry a non-null `IR_Type` annotation (either a concrete `NamedType`, `NullableType`,
`FunctionType`, `DynamicType`, or the `UnresolvedType` sentinel — but never absent).

**Validates: Requirements 7.1–7.8, 15.2**

---

### Property 3: Symbol Completeness

*For any* `NormalizedSyntaxTree` in a `FrontendResult`, every named-reference node (identifier,
member access, invocation, object creation, type reference) SHALL have a corresponding entry in
the `SymbolTable` — either a fully-resolved `ResolvedSymbol` or the `Kind = Unresolved` sentinel.

**Validates: Requirements 2.1–2.7, 15.3**

---

### Property 4: LINQ Query Syntax Elimination

*For any* `FrontendResult` produced from a `LoadResult` that contains LINQ query syntax
expressions, no `NormalizedSyntaxTree` in the result SHALL contain a `QueryExpressionSyntax`
node — all query syntax SHALL have been rewritten to method-chain form.

**Validates: Requirements 3.1, 6.1, 15.4**

---

### Property 5: Partial Class Merging

*For any* `FrontendResult` produced from a `LoadResult` that contains `partial` class
declarations, each logical type SHALL appear as exactly one declaration node in the
`NormalizedSyntaxTree` set for that project, regardless of how many partial parts existed in
the source.

**Validates: Requirements 3.2, 15.5**

---

### Property 6: Var Elimination

*For any* `FrontendResult`, no `NormalizedSyntaxTree` SHALL contain a `var`-typed local variable
declaration — every `var` declaration SHALL have been replaced with an explicit type annotation
derived from `SemanticModel` type inference.

**Validates: Requirements 7.2, 15.6**

---

### Property 7: Roslyn Isolation

*For any* `FrontendResult`, no field at any depth of the object graph SHALL be an instance of a
Roslyn type (`SyntaxNode`, `SemanticModel`, `ISymbol`, `ITypeSymbol`, `CSharpCompilation`, or
any type from `Microsoft.CodeAnalysis.*`). All data SHALL be expressed as plain-data records.

**Validates: Requirements 1.6, 14.3, 15.7**

---

### Property 8: Async Annotation Completeness

*For any* `FrontendResult` produced from a `LoadResult` that contains `async` method
declarations, every corresponding method node in the `NormalizedSyntaxTree` SHALL carry an
`AsyncAnnotation` with `isAsync = true`.

**Validates: Requirements 4.1–4.6, 15.8**

---

## Error Handling

| Condition | RF Code | Severity | Behaviour |
|---|---|---|---|
| Unresolved symbol (binding error) | RF0001 | Warning | Record `Kind = Unresolved` sentinel; continue processing |
| Normalization rewrite failed | RF0002 | Warning | Leave original node; attach `UnsupportedAnnotation`; continue |
| Unsupported construct (non-fatal) | RF0003 | Warning | Attach `UnsupportedAnnotation`; continue |
| Unsupported construct (fatal to declaration) | RF0004 | Error | Attach `UnsupportedAnnotation`; set `Success = false` |
| `unsafe` block | RF0005 | Error | Annotate entire block; set `Success = false` |
| `goto` / labeled statement | RF0006 | Warning | Attach `UnsupportedAnnotation`; continue |
| `dynamic`-typed expression | RF0007 | Warning | Attach `DynamicType`; continue |
| `SemanticModel.GetTypeInfo` null/error | RF0008 | Warning | Attach `UnresolvedType`; continue |
| `async void` method | RF0009 | Info | Attach `isFireAndForget = true`; continue |
| Unknown attribute | RF0010 | Info | Attach `UnknownAttribute`; continue |
| Project skipped (upstream errors) | RF0011 | Warning | Skip project; continue with others |
| Duplicate diagnostic suppressed | RF0012 | Warning | Suppress duplicate; continue |

All error paths produce a `FrontendResult` — the `Roslyn_Frontend` never throws. When any
`Error`-severity diagnostic is present, `FrontendResult.success` is set to `false` but the most
complete result possible is still returned (with `UnsupportedAnnotation` markers in place of
failed nodes).

---

## Testing Strategy

### Unit Tests (example-based)

- Verify `FrontendResult` field defaults and `success` flag logic.
- Verify `FrontendResultAssembler` correctly prepends PL diagnostics from `LoadResult`.
- Verify `FrontendResultAssembler` sets `success = false` when any Error diagnostic is present.
- Verify `InteropRequest` serialization round-trip (serialize → deserialize → equal).
- Verify `FrontendConfig` correctly extracts `linqStrategy` and `nullabilityEnabled` from
  `IConfigService`.
- Verify each normalization pass with a representative set of C# input patterns:
  - LINQ: `from x in xs where x > 0 select x * 2` → `.Where(x => x > 0).Select(x => x * 2)`
  - Async: `async Task<int> Foo()` → `AsyncAnnotation { isAsync: true, returnTypeSymbol: Task<int> }`
  - Auto-property: `public int X { get; set; }` → backing field + explicit getter/setter
  - `using` statement → `try/finally` with `Dispose()`
  - `lock` statement → `Monitor.Enter/Exit` with `try/finally`
  - `foreach` → `ForeachAnnotation { elementType }` attached
  - Indexer → `get_Item`/`set_Item` with `IndexerAnnotation`
  - Extension method → static method with `ExtensionAnnotation`
  - Explicit interface → regular method with `ExplicitInterfaceAnnotation`
- Verify `UnsupportedAnnotation` is attached and correct RF diagnostic is emitted for each
  unsupported construct (`unsafe`, `goto`, `fixed`, `stackalloc`).
- Verify attribute extraction for each supported attribute type.
- Verify `UnknownAttribute` is attached and `RF0010` Info is emitted for unsupported attributes.
- Verify `RF0012` Warning is emitted when a duplicate diagnostic is suppressed.
- Verify `RF0011` Warning is emitted when a project is skipped due to upstream errors.

### Property-Based Tests

Property-based tests use a property-based testing library (recommended:
[`propcheck`](https://pub.dev/packages/propcheck) or a custom generator harness). Each property
test runs a minimum of **100 iterations**.

Each test is tagged with a comment in the format:
`// Feature: cs-roslyn-frontend, Property <N>: <property_text>`

The interop layer is replaced with a `FakeInteropBridge` that returns pre-configured
`FrontendResult` values, allowing property tests to run without a .NET process.

| Property | Generator inputs | What is verified |
|---|---|---|
| P1 Determinism | Random `LoadResult` instances (varying project counts, file counts, source patterns) | Two `process()` calls → structurally equal `FrontendResult` |
| P2 Type completeness | Random normalized trees with various expression node kinds | Every expression node has a non-null `IR_Type` annotation |
| P3 Symbol completeness | Random trees with various named-reference node kinds | Every named-reference node has a `SymbolTable` entry |
| P4 LINQ query elimination | Random LINQ query expressions (varying clauses, nesting) | No `QueryExpressionSyntax` nodes in output |
| P5 Partial merging | Random partial class sets (1–N parts, varying member counts) | Exactly one declaration node per logical type in output |
| P6 Var elimination | Random `var`-typed declarations with various inferred types | No `var` keywords in output; all declarations have explicit types |
| P7 Roslyn isolation | Any valid `LoadResult` | No Roslyn types in `FrontendResult` object graph |
| P8 Async annotation completeness | Random async method declarations (Task, Task<T>, ValueTask, void) | Every async method node carries `AsyncAnnotation { isAsync: true }` |

### Integration Tests

A small set of integration tests run against real `.cs` fixture files with a real .NET worker
process:

- `test/fixtures/simple_console/` — verify basic normalization and symbol resolution.
- `test/fixtures/multi_project_solution/` — verify cross-project symbol resolution and
  topological ordering.
- `test/fixtures/nullable_enabled/` — verify `NullableType` wrapping when `NullableEnabled`.
- Inline LINQ fixture — verify query syntax rewriting to method-chain form.
- Inline `partial` class fixture — verify partial merging across two files.
- Inline `async`/`await` fixture — verify `AsyncAnnotation` and `ConfigureAwaitAnnotation`.
- Inline `unsafe` fixture — verify `RF0005` Error and `UnsupportedAnnotation` on the block.

Integration tests are tagged `@Tags(['integration'])` and excluded from the default test run.
They require a .NET 8 SDK installed and the `cs2dart_roslyn_worker` binary built.
