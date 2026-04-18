# Implementation Plan: Roslyn Frontend

## Overview

Implement the `Roslyn_Frontend` pipeline stage — the second stage of the cs2dart transpiler.
It consumes a `LoadResult` from the `Project_Loader` and emits a `FrontendResult` containing
fully-normalized, semantically-annotated syntax trees. All Roslyn API calls are delegated to a
companion .NET worker process (`cs2dart_roslyn_worker`) via a local-pipe JSON interop bridge;
the Dart side only handles serialization, deserialization, and post-processing assembly.

## Tasks

- [x] 1. Define data models
  - Create `lib/src/roslyn_frontend/models/` with all plain-data model classes:
    - `FrontendResult` (replaces the stub in `stage_results.dart`): `units`, `diagnostics`,
      `success`
    - `FrontendUnit`: `projectName`, `outputKind`, `targetFramework`, `langVersion`,
      `nullableEnabled`, `packageReferences`, `normalizedTrees`
    - `NormalizedSyntaxTree`: `filePath`, `root`, `symbolTable`
    - `SymbolTable`: `entries` (`Map<int, ResolvedSymbol>`), `lookup(int nodeId)`
    - `ResolvedSymbol`: `fullyQualifiedName`, `assemblyName`, `kind`, `sourcePackageId`,
      `sourceLocation`, `constantValue`
    - `SymbolKind` enum: `type`, `method`, `field`, `property`, `event`, `local`, `parameter`,
      `unresolved`
    - `IrType` sealed class hierarchy: `NamedType`, `NullableType`, `FunctionType`,
      `DynamicType`, `UnresolvedType`
    - Annotation types: `AsyncAnnotation`, `ConfigureAwaitAnnotation`,
      `OverflowCheckAnnotation`, `ForeachAnnotation`, `IndexerAnnotation`,
      `ExtensionAnnotation`, `ExplicitInterfaceAnnotation`, `UnsupportedAnnotation`,
      `DeclarationModifiers`, `Accessibility` enum
  - Export all public symbols from `lib/src/roslyn_frontend/roslyn_frontend.dart`
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.2, 7.1, 8.1, 8.2_

- [x] 2. Define interfaces
  - Create `lib/src/roslyn_frontend/interfaces/i_roslyn_frontend.dart` with the full
    `IRoslynFrontend` interface accepting `(LoadResult loadResult, IConfigService config)` —
    update the existing stub in `lib/src/orchestrator/interfaces/i_roslyn_frontend.dart` to
    re-export this definition
  - Create `lib/src/roslyn_frontend/interfaces/i_interop_bridge.dart` with `IInteropBridge`:
    `Future<FrontendResult> invoke(InteropRequest request)` and `Future<void> dispose()`
  - Create `lib/src/roslyn_frontend/models/interop_request.dart` with `InteropRequest`
    (`projects`, `config`) and `FrontendConfig` (`linqStrategy`, `nullabilityEnabled`,
    `experimentalFeatures`)
  - _Requirements: 1.1, 1.3, 13.1, 13.2_

- [x] 3. Implement `FrontendResultAssembler`
  - Create `lib/src/roslyn_frontend/frontend_result_assembler.dart`
  - Implement `FrontendResult assemble(FrontendResult workerResult, LoadResult loadResult)`:
    - Prepend all `PL`-prefixed diagnostics from `loadResult.diagnostics` unchanged
    - Append worker diagnostics after PL diagnostics
    - Set `success = true` iff no `Error`-severity diagnostic is present in the merged list
    - Deduplicate diagnostics with the same source location and code; emit `RF0012` Warning
      for each suppressed duplicate
  - _Requirements: 1.4, 1.5, 12.3, 12.4_

  - [ ]* 3.1 Write unit tests for `FrontendResultAssembler`
    - Test PL diagnostics are prepended before RF diagnostics
    - Test `success = false` when any Error diagnostic is present
    - Test `success = true` when only Warning/Info diagnostics are present
    - Test `RF0012` Warning is emitted when a duplicate diagnostic is suppressed
    - _Requirements: 1.4, 1.5, 12.3, 12.4_

- [x] 4. Implement `RoslynFrontend`
  - Create `lib/src/roslyn_frontend/roslyn_frontend.dart` implementing `IRoslynFrontend`
  - Constructor accepts `IInteropBridge bridge` and optional `FrontendResultAssembler assembler`
  - `process(LoadResult loadResult, IConfigService config)`:
    - Build `FrontendConfig` from `config` (`linqStrategy`, `nullabilityEnabled`,
      `experimentalFeatures`)
    - Build `InteropRequest` from `loadResult` projects and `FrontendConfig`
    - Call `_bridge.invoke(request)` to obtain the worker result
    - Call `_assembler.assemble(workerResult, loadResult)` to produce the final `FrontendResult`
    - Emit `RF0011` Warning for each `ProjectEntry` skipped due to upstream Error diagnostics
    - Never throw; wrap any `InteropException` as an `RF`-prefixed Error diagnostic and return
      a `FrontendResult` with `success = false`
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 12.4, 12.6, 13.1_

  - [ ]* 4.1 Write unit tests for `RoslynFrontend`
    - Test `process()` calls `IInteropBridge.invoke` with correctly-built `InteropRequest`
    - Test `RF0011` Warning is emitted for each project with upstream Error diagnostics
    - Test `InteropException` is caught and returned as an Error diagnostic (no re-throw)
    - Test `FrontendResultAssembler.assemble` is called with the worker result and `loadResult`
    - _Requirements: 1.1, 1.2, 1.3, 1.7, 12.4, 12.6_

- [x] 5. Implement `FakeInteropBridge` for testing
  - Create `test/roslyn_frontend/fakes/fake_interop_bridge.dart` implementing `IInteropBridge`
  - Accepts a pre-configured `FrontendResult` (or a callback) to return from `invoke()`
  - Records whether `invoke()` and `dispose()` were called and with what arguments
  - Supports configuring it to throw `InteropException` for error-path tests
  - _Requirements: (supports all property and unit tests)_

- [x] 6. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Implement `InteropRequest` serialization
  - Create `lib/src/roslyn_frontend/serialization/interop_request_serializer.dart`
  - Implement `Map<String, dynamic> toJson(InteropRequest request)` covering all fields of
    `InteropRequest`, `ProjectEntryRequest`, and `FrontendConfig`
  - Implement `InteropRequest fromJson(Map<String, dynamic> json)` for round-trip testing
  - _Requirements: 1.6, 13.1_

  - [ ]* 7.1 Write unit tests for `InteropRequest` serialization
    - Test `toJson` → `fromJson` round-trip produces a value-equal `InteropRequest`
    - Test `FrontendConfig` fields (`linqStrategy`, `nullabilityEnabled`,
      `experimentalFeatures`) are serialized correctly
    - _Requirements: 1.6, 13.1_

- [x] 8. Implement `FrontendResult` deserialization
  - Create `lib/src/roslyn_frontend/serialization/frontend_result_deserializer.dart`
  - Implement `FrontendResult fromJson(Map<String, dynamic> json)` covering all fields of
    `FrontendResult`, `FrontendUnit`, `NormalizedSyntaxTree`, `SymbolTable`, `ResolvedSymbol`,
    `IrType` hierarchy, and all annotation types
  - Ensure no Roslyn types appear in the deserialized object graph
  - Ask the user to make any updates to test/roslyn_frontend/serialization/frontend_result_deserializer_test.dart. Do not try to modify this file yourself.
  - _Requirements: 1.6, 14.3_

  - [ ]* 8.1 Write unit tests for `FrontendResult` deserialization
    - Test round-trip for a `FrontendResult` with all field types populated
    - Test `IrType` sealed subclasses deserialize to the correct runtime type
    - Test annotation types (`AsyncAnnotation`, `ForeachAnnotation`, etc.) deserialize correctly
    - _Requirements: 1.6, 14.3_

- [x] 9. Write property-based tests

  - [ ]* 9.1 Write property test for determinism — Property 1: Determinism
    - **Property 1: Determinism**
    - For any valid `LoadResult` input, invoking `process()` twice with the same input SHALL
      produce `FrontendResult` values that are structurally and value-equal
    - Use `FakeInteropBridge` returning a deterministic result for the same request
    - **Validates: Requirements 11.1–11.5, 15.1**

  - [ ]* 9.2 Write property test for type completeness — Property 2: Type Completeness
    - **Property 2: Type Completeness**
    - For any `NormalizedSyntaxTree` in a `FrontendResult`, every expression node SHALL carry
      a non-null `IrType` annotation (one of `NamedType`, `NullableType`, `FunctionType`,
      `DynamicType`, or `UnresolvedType` — never absent)
    - Generate random normalized trees with various expression node kinds
    - **Validates: Requirements 7.1–7.8, 15.2**

  - [ ]* 9.3 Write property test for symbol completeness — Property 3: Symbol Completeness
    - **Property 3: Symbol Completeness**
    - For any `NormalizedSyntaxTree`, every named-reference node SHALL have a corresponding
      entry in the `SymbolTable` — either a fully-resolved `ResolvedSymbol` or the
      `Kind = Unresolved` sentinel
    - Generate random trees with various named-reference node kinds
    - **Validates: Requirements 2.1–2.7, 15.3**

  - [ ]* 9.4 Write property test for LINQ query syntax elimination — Property 4: LINQ Query Syntax Elimination
    - **Property 4: LINQ Query Syntax Elimination**
    - For any `FrontendResult` produced from a `LoadResult` containing LINQ query syntax, no
      `NormalizedSyntaxTree` SHALL contain a `QueryExpressionSyntax` node
    - Generate random LINQ query expressions (varying clauses, nesting)
    - **Validates: Requirements 3.1, 6.1, 15.4**

  - [ ]* 9.5 Write property test for partial class merging — Property 5: Partial Class Merging
    - **Property 5: Partial Class Merging**
    - For any `FrontendResult` produced from a `LoadResult` containing `partial` class
      declarations, each logical type SHALL appear as exactly one declaration node in the
      `NormalizedSyntaxTree` set for that project
    - Generate random partial class sets (1–N parts, varying member counts)
    - **Validates: Requirements 3.2, 15.5**

  - [ ]* 9.6 Write property test for var elimination — Property 6: Var Elimination
    - **Property 6: Var Elimination**
    - For any `FrontendResult`, no `NormalizedSyntaxTree` SHALL contain a `var`-typed local
      variable declaration — every `var` SHALL have been replaced with an explicit type
      annotation
    - Generate random `var`-typed declarations with various inferred types
    - **Validates: Requirements 7.2, 15.6**

  - [ ]* 9.7 Write property test for Roslyn isolation — Property 7: Roslyn Isolation
    - **Property 7: Roslyn Isolation**
    - For any `FrontendResult`, no field at any depth of the object graph SHALL be an instance
      of a Roslyn type (`SyntaxNode`, `SemanticModel`, `ISymbol`, `ITypeSymbol`,
      `CSharpCompilation`, or any type from `Microsoft.CodeAnalysis.*`)
    - Use reflection to walk the object graph and assert no Roslyn types are present
    - **Validates: Requirements 1.6, 14.3, 15.7**

  - [ ]* 9.8 Write property test for async annotation completeness — Property 8: Async Annotation Completeness
    - **Property 8: Async Annotation Completeness**
    - For any `FrontendResult` produced from a `LoadResult` containing `async` method
      declarations, every corresponding method node SHALL carry an `AsyncAnnotation` with
      `isAsync = true`
    - Generate random async method declarations (Task, Task<T>, ValueTask, void)
    - **Validates: Requirements 4.1–4.6, 15.8**

- [ ] 10. Write unit tests for normalization passes

  - [ ]* 10.1 Write unit tests for LINQ normalization (Pass 1)
    - Test `from x in xs where x > 0 select x * 2` rewrites to `.Where(x => x > 0).Select(x => x * 2)`
    - Test `orderby`, `group by`, `join`, `let` clauses rewrite correctly
    - Test `linqStrategy = lower_to_loops` produces `foreach`/local-variable form for
      supported chains (`Where`, `Select`, `OrderBy`, `Take`, `Skip`, `ToList`/`ToArray`)
    - Test `GroupBy`/`Join` chains are left in method-chain form with `RF0002` Warning when
      `lower_to_loops` is active
    - Test each LINQ method-chain call node carries `ResolvedSymbol`, `elementInputType`,
      and `resultType` annotations
    - _Requirements: 3.1, 6.1, 6.2, 6.3, 6.4, 6.5_

  - [ ]* 10.2 Write unit tests for async annotation (Pass 2)
    - Test `async Task<int> Foo()` produces `AsyncAnnotation { isAsync: true, returnTypeSymbol: Task<int> }`
    - Test `async void Bar()` produces `isFireAndForget = true` and emits `RF0009` Info
    - Test iterator method with `yield` produces `AsyncAnnotation { isIterator: true }`
    - Test `ConfigureAwait(false)` is rewritten to plain `await` with `ConfigureAwaitAnnotation`
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_

  - [ ]* 10.3 Write unit tests for pattern matching normalization (Pass 3)
    - Test switch expression arms rewrite to canonical `SwitchExpressionArm` form
    - Test type pattern `case Foo f:` normalizes to `TypePattern { resolvedSymbol, variableName }`
    - Test property pattern `case { X: 1, Y: 2 }:` normalizes to `PropertyPattern`
    - Test positional pattern normalizes to `PositionalPattern` with `deconstructSymbol`
    - Test `is` expression normalizes to `IsExpression { testedTypeSymbol, variableName? }`
    - Test unsupported pattern combinators produce `UnsupportedPattern` and `RF0002` Warning
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7_

  - [ ]* 10.4 Write unit tests for auto-property expansion (Pass 4)
    - Test `public int X { get; set; }` produces backing field `_x` + explicit getter/setter
    - Test `IsSynthesizedBackingField = true` annotation is attached to the backing field
    - Test init-only setter `{ get; init; }` produces `IsInitOnly = true` annotation
    - Test get-only `{ get; }` produces a `readonly` backing field with no setter
    - _Requirements: 3.5_

  - [ ]* 10.5 Write unit tests for using/lock/checked rewriting (Pass 5)
    - Test `using (var r = expr) { body }` rewrites to `try/finally` with `r.Dispose()`
    - Test `using var r = expr;` (C# 8 declaration form) rewrites to same `try/finally` pattern
    - Test `lock (obj) { body }` rewrites to `Monitor.Enter/Exit` with `try/finally`
    - Test arithmetic operations inside `checked` block carry `OverflowCheckAnnotation { checked: true }`
    - Test arithmetic operations inside `unchecked` block carry `OverflowCheckAnnotation { checked: false }`
    - _Requirements: 3.6, 3.7, 3.8_

  - [ ]* 10.6 Write unit tests for foreach expansion (Pass 6)
    - Test `foreach (var x in xs)` attaches `ForeachAnnotation { elementType }` to the loop node
    - Test loop body and iteration variable are preserved unchanged
    - _Requirements: 3.9_

  - [ ]* 10.7 Write unit tests for indexer normalization (Pass 7)
    - Test indexer declaration rewrites to `get_Item`/`set_Item` method declarations
    - Test `IndexerAnnotation { isIndexer: true }` is attached to each generated method
    - _Requirements: 3.10_

  - [ ]* 10.8 Write unit tests for extension method normalization (Pass 8)
    - Test extension method rewrites to regular static method (no `this` modifier on first param)
    - Test `ExtensionAnnotation { isExtension: true, extendedType }` is attached
    - _Requirements: 3.12_

  - [ ]* 10.9 Write unit tests for explicit interface normalization (Pass 9)
    - Test `IFoo.Bar()` rewrites to regular method declaration
    - Test `ExplicitInterfaceAnnotation { implementedInterface }` is attached
    - _Requirements: 3.11_

- [ ] 11. Write unit tests for enrichment and extraction components

  - [ ]* 11.1 Write unit tests for type annotation enrichment
    - Test every expression node kind receives a non-null `IrType` annotation
    - Test `var` local variable declarations are replaced with the inferred concrete type
    - Test `dynamic`-typed expressions receive `DynamicType` and emit `RF0007` Warning
    - Test nullable reference types receive `NullableType` wrapper when `nullableEnabled = true`
    - Test nullable value types (`int?`) receive `NullableType` wrapper regardless of setting
    - Test `const` expressions carry their compile-time constant value
    - Test `SemanticModel.GetTypeInfo` null/error produces `UnresolvedType` and `RF0008` Warning
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8_

  - [ ]* 11.2 Write unit tests for attribute extraction
    - Test each supported attribute (`[Obsolete]`, `[Flags]`, `[DllImport]`, `[StructLayout]`,
      `[MethodImpl]`, `[CallerMemberName]`, `[NotNull]`, `[MaybeNull]`, etc.) is extracted as
      a structured record with correct field values
    - Test `typeof(T)` constructor arguments are resolved to `ResolvedSymbol`
    - Test unsupported attributes produce `UnknownAttribute` and emit `RF0010` Info
    - Test compiler-synthesized attributes (`ApplicationSyntaxReference == null`) are silently
      excluded
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6_

  - [ ]* 11.3 Write unit tests for declaration metadata extraction
    - Test each `Accessibility` level is correctly resolved for type and member declarations
    - Test boolean modifier flags (`IsStatic`, `IsAbstract`, `IsVirtual`, `IsOverride`,
      `IsSealed`, `IsReadonly`, `IsConst`, `IsExtern`, `IsNew`) are set correctly
    - Test `Class` declaration carries resolved base class and interface `ResolvedSymbol` entries
    - Test generic declarations carry `TypeParameter` nodes with constraints
    - Test `Method` declaration carries `IsOperator`, `IsConversion`, `IsExtension`,
      `IsIndexer` flags
    - Test `Parameter` nodes carry resolved type, default value, and `IsParams`/`IsRef`/
      `IsOut`/`IsIn` flags
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7_

- [-] 12. Write unit tests for unsupported construct handling
  - Test `unsafe` block produces `UnsupportedAnnotation` and emits `RF0005` Error
  - Test `fixed` statement produces `UnsupportedAnnotation` and emits `RF0005` Error
  - Test `stackalloc` produces `UnsupportedAnnotation` and emits `RF0005` Error
  - Test `goto` / labeled statement produces `UnsupportedAnnotation` and emits `RF0006` Warning
  - Test `__arglist` produces `UnsupportedAnnotation` and emits `RF0003` Warning
  - Test processing continues for all remaining nodes after an unsupported construct is marked
  - Test `RF0004` Error is emitted when an unsupported construct makes a declaration
    semantically incomplete
  - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_

- [~] 13. Write unit tests for diagnostics and error reporting
  - Test `RF`-prefixed diagnostic codes are in range `RF0001`–`RF9999`
  - Test duplicate diagnostics (same source location and code) are suppressed with `RF0012`
  - Test Roslyn `CS`-prefixed compiler diagnostics are propagated unchanged into
    `FrontendResult.diagnostics`
  - Test `FrontendResult.success = false` when any Error diagnostic is present
  - Test `FrontendResult.success = true` when only Warning/Info diagnostics are present
  - Test `RF0011` Warning is emitted for each project skipped due to upstream Error diagnostics
  - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 12.7_

- [~] 14. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 15. Write integration tests
  - [ ]* 15.1 Write integration test: simple console project
    - Use `test/fixtures/simple_console/` fixture with a real .NET worker process
    - Verify basic normalization, symbol resolution, and `FrontendUnit` metadata
    - Tag `@Tags(['integration'])`
    - _Requirements: 1.1, 1.2, 2.1, 2.2_

  - [ ]* 15.2 Write integration test: multi-project solution
    - Use `test/fixtures/multi_project_solution/` fixture
    - Verify cross-project symbol resolution and topological ordering of `FrontendUnit` list
    - Tag `@Tags(['integration'])`
    - _Requirements: 1.2, 11.2_

  - [ ]* 15.3 Write integration test: nullable enabled project
    - Use `test/fixtures/nullable_enabled/` fixture
    - Verify `NullableType` wrapping is applied to nullable reference type expressions
    - Tag `@Tags(['integration'])`
    - _Requirements: 7.5_

  - [ ]* 15.4 Write integration test: LINQ query syntax rewriting
    - Inline fixture with `from x in xs where x > 0 select x * 2`
    - Verify no `QueryExpressionSyntax` nodes in output; verify method-chain form with type
      annotations
    - Tag `@Tags(['integration'])`
    - _Requirements: 3.1, 6.1, 6.2_

  - [ ]* 15.5 Write integration test: partial class merging
    - Inline fixture with a type split across two files
    - Verify exactly one declaration node per logical type in the output
    - Tag `@Tags(['integration'])`
    - _Requirements: 3.2_

  - [ ]* 15.6 Write integration test: async/await normalization
    - Inline fixture with `async Task<int>`, `async void`, and `ConfigureAwait(false)` patterns
    - Verify `AsyncAnnotation`, `isFireAndForget`, and `ConfigureAwaitAnnotation` are attached
    - Tag `@Tags(['integration'])`
    - _Requirements: 4.1, 4.3, 4.6_

  - [ ]* 15.7 Write integration test: unsafe block
    - Inline fixture with an `unsafe` block
    - Verify `RF0005` Error diagnostic and `UnsupportedAnnotation` on the block
    - Tag `@Tags(['integration'])`
    - _Requirements: 9.6_

- [~] 16. Wire `RoslynFrontend` into the pipeline bootstrap
  - Register `RoslynFrontend` (with `IInteropBridge` and `FrontendResultAssembler` dependencies)
    in `lib/src/pipeline_bootstrap.dart` so the `Orchestrator` can resolve `IRoslynFrontend`
  - Update `lib/src/orchestrator/interfaces/i_roslyn_frontend.dart` to re-export the full
    interface from `lib/src/roslyn_frontend/interfaces/i_roslyn_frontend.dart`
  - Ensure `IConfigService` is passed through to `RoslynFrontend.process()` at call sites
  - _Requirements: 1.1, 1.3, 13.1_

- [~] 17. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass (excluding `@Tags(['integration'])` unless .NET 8 SDK and
    `cs2dart_roslyn_worker` binary are available), ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests (Properties 1–8) validate universal correctness properties from the design
- Unit tests validate specific examples and edge cases for each normalization pass
- Integration tests require a .NET 8 SDK and the `cs2dart_roslyn_worker` binary built; they
  are excluded from the default test run via `@Tags(['integration'])`
- The `FakeInteropBridge` (task 5) is the primary test double for all Dart-side tests; it
  avoids spawning a real .NET process
- The .NET worker (`cs2dart_roslyn_worker`) implementation is out of scope for this spec; the
  `IInteropBridge` abstraction allows the Dart side to be fully tested independently
- `FrontendResult` in `stage_results.dart` is a stub; task 1 replaces it with the full model
