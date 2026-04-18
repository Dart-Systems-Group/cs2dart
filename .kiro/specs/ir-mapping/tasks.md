# Implementation Plan: C# → IR Mapping

## Overview

Implement the IR stage of the cs2dart transpiler in Dart, building incrementally from data models
and interfaces through the IR_Builder, IR_Validator, and IR_Serializer, ending with a fully
integrated stage that the pipeline orchestrator can consume.

## Tasks

- [x] 1. Define IR node data models and core interfaces
  - Create `lib/src/ir/models/` with all IR node sealed class hierarchies:
    - `IrNode` base, `IrDeclarationNode`, `IrStatementNode`, `IrExpressionNode`, `IrType`
    - All Declaration nodes: `CompilationUnitNode`, `NamespaceNode`, `ClassNode`, `StructNode`,
      `InterfaceNode`, `EnumNode`, `EnumMemberNode`, `MethodNode`, `ConstructorNode`,
      `DestructorNode`, `PropertyNode`, `FieldNode`, `EventNode`, `DelegateNode`,
      `TypeParameterNode`, `ParameterNode`, `LocalFunctionNode`, `AttributeNode`
    - All Statement nodes: `BlockNode`, `ExpressionStatementNode`, `ReturnStatementNode`,
      `IfStatementNode`, `WhileStatementNode`, `ForStatementNode`, `ForEachStatementNode`,
      `SwitchStatementNode`, `SwitchCaseNode`, `BreakStatementNode`, `ContinueStatementNode`,
      `ThrowStatementNode`, `TryCatchStatementNode`, `CatchClauseNode`, `FinallyClauseNode`,
      `LocalDeclarationNode`, `YieldReturnStatementNode`, `YieldBreakStatementNode`
    - All Expression nodes: `LiteralNode`, `IdentifierNode`, `BinaryExpressionNode`,
      `UnaryExpressionNode`, `AssignmentExpressionNode`, `ConditionalExpressionNode`,
      `InvocationExpressionNode`, `MemberAccessExpressionNode`, `ElementAccessExpressionNode`,
      `ObjectCreationExpressionNode`, `ArrayCreationExpressionNode`, `CastExpressionNode`,
      `IsExpressionNode`, `AsExpressionNode`, `LambdaExpressionNode`,
      `AnonymousObjectCreationNode`, `TupleExpressionNode`, `SwitchExpressionNode`,
      `ThrowExpressionNode`, `AwaitExpressionNode`, `InterpolatedStringNode`,
      `NullCoalescingExpressionNode`, `NullConditionalExpressionNode`
    - All Type nodes: `PrimitiveType`, `NamedType`, `GenericType`, `ArrayType`, `NullableType`,
      `TupleType`, `FunctionType`, `VoidType`, `DynamicType`
    - `UnsupportedNode`, `UnresolvedSymbol` placeholder nodes
    - `IrSymbol`, `AttributeTarget` enum, `Accessibility` enum, `SymbolKind` enum
  - Create `lib/src/ir/models/ir_build_result.dart` with `IrBuildResult` and
    `IrCompilationUnit`
  - Create `lib/src/ir/interfaces/` with abstract interface classes:
    `IIrBuilder`, `IIrValidator`, `IIrSerializer`
  - Export all public symbols from `lib/src/ir/ir.dart`
  - _Requirements: 1.1–1.7, 2.1–2.2, 3.1, 10.1, 10.8_

- [x] 2. Implement `TypeResolver` and `SymbolResolver`
  - [x] 2.1 Implement `TypeResolver`
    - Create `lib/src/ir/type_resolver.dart`
    - Map `ResolvedSymbol` type information to `IrType` nodes:
      - Primitive CLR types → `PrimitiveType`
      - Nullable reference types (`string?`) → `NullableType(NamedType)`
      - Nullable value types (`int?`) → `NullableType(PrimitiveType)`
      - Open generic type parameters → `TypeParameter` with constraints
      - Closed generics (`List<int>`) → `GenericType(NamedType, [PrimitiveType])`
      - Tuple types → `TupleType` with named element types
      - Delegate/lambda types → `FunctionType` with parameter and return types
      - `dynamic` → `DynamicType` + emit `IR0010` Warning diagnostic
      - `void` → `VoidType`
    - _Requirements: 3.1–3.8_

  - [x] 2.2 Implement `SymbolResolver`
    - Create `lib/src/ir/symbol_resolver.dart`
    - Read `SymbolTable` entries from `Normalized_SyntaxTree` and produce `IrSymbol` nodes:
      - Copy `FullyQualifiedName`, `AssemblyName`, `Kind`, `SourceLocation`,
        `SourcePackageId` from `ResolvedSymbol`
      - For internal symbols: set `declarationNode` reference (resolved in a second pass)
      - For external symbols: record assembly name and FQN
      - For `Kind = Unresolved`: emit `UnresolvedSymbol` node + `IR0020` Warning
      - Use the specific overload recorded in `SymbolTable` for method references
    - _Requirements: 2.1–2.6_

  - [ ]* 2.3 Write unit tests for `TypeResolver` and `SymbolResolver`
    - Test each C# type maps to the correct `IrType` subtype
    - Test nullable reference and value-type nullables produce `NullableType`
    - Test `dynamic` produces `DynamicType` + Warning diagnostic
    - Test `Kind = Unresolved` produces `UnresolvedSymbol` + Warning diagnostic
    - Test `SourcePackageId` is copied to `IrSymbol.sourcePackageId`
    - _Requirements: 2.1–2.6, 3.1–3.8_

- [ ] 3. Implement `DeclarationVisitor`
  - [ ] 3.1 Implement core declaration traversal
    - Create `lib/src/ir/visitors/declaration_visitor.dart`
    - Traverse `Normalized_SyntaxTree` top-level declarations and emit IR declaration nodes
    - Attach `Accessibility`, modifier flags (`isStatic`, `isAbstract`, `isVirtual`,
      `isOverride`, `isSealed`, `isReadonly`, `isConst`, `isExtern`), and `AttributeNode` lists
    - Preserve inheritance chain: `baseClass` and `implementedInterfaces` on `ClassNode`
    - Attach `TypeParameterNode` lists to generic declarations
    - Preserve operator overloads as `MethodNode` with `isOperator = true` and `operatorKind`
    - Preserve conversion operators with `isConversion`, `isImplicit`/`isExplicit` flags
    - _Requirements: 1.3, 9.1–9.7, 11.1–11.6_

  - [ ] 3.2 Implement `LoweringEngine` for declaration lowering
    - Create `lib/src/ir/lowering/lowering_engine.dart`
    - Lower auto-properties to `PropertyNode` + getter/setter `MethodNode` + backing `FieldNode`
    - Lower primary constructors (C# 12) to explicit `ConstructorNode` + `ParameterNode` +
      `FieldNode` list
    - Lower record types to `ClassNode`/`StructNode` with synthesized equality, `ToString`,
      `Deconstruct` `MethodNode`s
    - Lower partial classes: merge all partial declarations into a single `ClassNode`; union
      `AttributeNode` lists ordered by FQN → file path → line number; no deduplication
    - Lower static constructors to `ConstructorNode` with `isStatic = true`
    - Lower indexers to `MethodNode` with `get_Item`/`set_Item` name and `isIndexer = true`
    - Lower explicit interface implementations to `MethodNode` with `explicitInterface` field
    - Lower extension methods to `MethodNode` with `isExtension = true` and `extendedType`
    - _Requirements: 4.1–4.8_

  - [ ]* 3.3 Write unit tests for `DeclarationVisitor` and `LoweringEngine`
    - Test auto-property lowering produces Property + getter + setter + backing field
    - Test record lowering produces synthesized equality, ToString, Deconstruct methods
    - Test partial class merge unions attribute lists without deduplication
    - Test partial merge attribute ordering: FQN → file path → line number
    - Test static constructor lowering sets `isStatic = true`
    - Test indexer lowering sets `isIndexer = true` and correct name
    - Test extension method lowering sets `isExtension = true` and `extendedType`
    - _Requirements: 4.1–4.8, 11.1–11.6_

- [ ] 4. Implement `StatementVisitor`
  - [ ] 4.1 Implement statement traversal and lowering
    - Create `lib/src/ir/visitors/statement_visitor.dart`
    - Emit all 18 statement node types from the taxonomy
    - Lower `foreach` to `ForEachStatementNode` with element `IrType` and collection expression
    - Lower `using` statements/declarations to `TryCatchStatementNode` with `FinallyClause`
      calling `Dispose()`
    - Lower `lock` statements to `TryCatchStatementNode` with `Monitor.Enter`/`Monitor.Exit`
    - Lower `checked`/`unchecked` blocks: annotate contained arithmetic `BinaryExpressionNode`s
      with `overflowCheck` flag; do not emit wrapper nodes
    - Lower `goto` and labeled statements to `UnsupportedNode` + `IR0002` Error; continue
    - Lower C# 8+ switch expressions to `SwitchExpressionNode` with arm pairs
    - Lower pattern matching constructs to structured `PatternNode`s on `SwitchCaseNode` and
      `IsExpressionNode`
    - _Requirements: 1.4, 5.1–5.7_

  - [ ]* 4.2 Write unit tests for `StatementVisitor`
    - Test `foreach` lowering produces `ForEachStatementNode` with correct element type
    - Test `using` lowering produces `TryCatchStatementNode` with `Dispose()` in finally
    - Test `lock` lowering produces `TryCatchStatementNode` with `Monitor.Enter`/`Monitor.Exit`
    - Test `checked` block annotates arithmetic nodes with `overflowCheck = true`
    - Test `goto` produces `UnsupportedNode` + Error diagnostic; processing continues
    - Test switch expression lowering produces `SwitchExpressionNode` with arm pairs
    - _Requirements: 5.1–5.7_

- [ ] 5. Implement `ExpressionVisitor` with LINQ and async/await support
  - [ ] 5.1 Implement core expression traversal
    - Create `lib/src/ir/visitors/expression_visitor.dart`
    - Emit all 24 expression node types from the taxonomy; attach `IrType` to every node
    - Preserve argument evaluation order in `InvocationExpressionNode` (ordered list)
    - Represent `ConfigureAwait(false)` as `AwaitExpressionNode` with `configureAwait = false`
    - Represent explicit discard of Task call (`_ = SomeAsync()`) as `InvocationExpressionNode`
      with `isFireAndForget = true`; do NOT emit the enclosing `AssignmentExpressionNode`
    - Detect unawaited bare Task calls (no await, no assignment, no CS4014 suppression):
      emit `isFireAndForget = false` + `IR0011` Warning
    - _Requirements: 1.5, 7.1–7.7, 11.7_

  - [ ] 5.2 Implement LINQ lowering
    - Create `lib/src/ir/lowering/linq_lowering.dart`
    - Normalize LINQ query syntax to LINQ method-chain form before emitting IR nodes
    - Read `linqStrategy` from `IConfigService`:
      - `lower_to_loops`: lower LINQ chains to `ForEachStatementNode` + `LocalDeclarationNode`
      - `preserve_functional` (or default): preserve as `InvocationExpressionNode` chains
    - Resolve each LINQ method to its `System.Linq.Enumerable`/`Queryable` `IrSymbol`
    - Attach element `IrType` and result `IrType` to every LINQ `InvocationExpressionNode`
    - _Requirements: 6.1–6.6_

  - [ ]* 5.3 Write unit tests for `ExpressionVisitor` and LINQ lowering
    - Test `await` expression produces `AwaitExpressionNode` with correct result type
    - Test `ConfigureAwait(false)` produces `AwaitExpressionNode` with `configureAwait = false`
    - Test explicit discard produces `InvocationExpressionNode` with `isFireAndForget = true`
    - Test unawaited bare Task call produces `isFireAndForget = false` + Warning diagnostic
    - Test LINQ query syntax is normalized to method-chain form
    - Test `lower_to_loops` strategy produces `ForEachStatementNode` chains
    - Test `preserve_functional` strategy preserves `InvocationExpressionNode` chains
    - Test default (no config) applies `preserve_functional`
    - _Requirements: 6.1–6.6, 7.1–7.7_

- [ ] 6. Implement `IR_Builder` coordinator
  - Create `lib/src/ir/ir_builder.dart` implementing `IIrBuilder`
  - Accept `IConfigService` at construction; store as sole config source
  - Iterate `Frontend_Result.units` in provided order; produce one `IrCompilationUnit` per unit
  - For each unit: read metadata (`outputKind`, `targetFramework`, `langVersion`,
    `nullableEnabled`, `packageReferences`) and record on `IrCompilationUnit`
  - Process each `Normalized_SyntaxTree` in alphabetical file path order using the visitor
    sub-components; release references to tree nodes after each tree's IR subtree is emitted
  - After all trees: run `LoweringEngine.mergePartialClasses` to produce final merged nodes
  - Propagate `Unsupported`/`UnknownAttribute` markers from Roslyn_Frontend as `UnsupportedNode`
    / `UnresolvedSymbol` placeholders; continue processing
  - Aggregate all diagnostics; set `success = (no Error-severity diagnostics)`
  - Expose single public entry point: `IrBuildResult build(FrontendResult frontendResult)`
  - No mutable global state; no Roslyn API calls
  - _Requirements: 10.1–10.9, 12.1–12.5, 15.1–15.6_

- [ ] 7. Implement `IR_Validator`
  - Create `lib/src/ir/ir_validator.dart` implementing `IIrValidator`
  - Walk the IR tree and collect all violations (never throw on first error):
    - Every `IrExpressionNode` has non-null `type` → `IR0030` Error if violated
    - Every `IdentifierNode` / reference node has non-null `irSymbol` → `IR0031` Error
    - Every `MethodNode` with `isAsync = true` has Task/ValueTask/IAsyncEnumerable return type
      → `IR0032` Error
    - Every `InvocationExpressionNode` with `isFireAndForget = true` has Task/ValueTask return
      type → `IR0038` Error
    - No `ClassNode` has both `isAbstract = true` and `isSealed = true` → `IR0033` Error
    - Every `TypeParameter` referenced in a `GenericType` is declared in the enclosing generic
      declaration → `IR0034` Error
    - Every `CatchClause` with `whenExpression` has that expression typed as `bool` → `IR0035`
    - Every `IrSymbol` whose `assemblyName` matches a package ID in `packageReferences` carries
      non-null `sourcePackageId` equal to that package ID → `IR0036` Error
    - Every `AttributeNode` has non-null non-empty `fullyQualifiedName` and a `target` value
      consistent with the type of the IR node it is attached to → `IR0037` Error
  - Complete validation in O(n) time proportional to node count
  - Return all violations as a list of `Diagnostic` records
  - _Requirements: 14.1–14.10_

- [ ]* 8. Write property-based tests
  - [ ]* 8.1 Write property test: every reference node carries a non-null IR_Symbol
    - **Property 1: Every reference node carries a non-null IR_Symbol**
    - **Validates: Requirements 2.1, 2.2**
    - For any valid `Frontend_Result`, all reference nodes in the IR have non-null `IrSymbol`
    - _Requirements: 2.1, 2.2_

  - [ ]* 8.2 Write property test: every typed node carries a non-null IR_Type
    - **Property 2: Every typed node carries a non-null IR_Type**
    - **Validates: Requirements 3.1, 14.1, 16.6**
    - For any valid `Frontend_Result`, all expression/parameter/field/property/local nodes have
      non-null `IrType`
    - _Requirements: 3.1, 14.1, 16.6_

  - [ ]* 8.3 Write property test: nullable type representation round-trip
    - **Property 3: Nullable type representation round-trip**
    - **Validates: Requirements 3.2, 3.3**
    - For any nullable type in source, IR_Type is `NullableType` wrapping the base type
    - _Requirements: 3.2, 3.3_

  - [ ]* 8.4 Write property test: type fidelity
    - **Property 4: Type fidelity**
    - **Validates: Requirements 3.4–3.7, 16.6**
    - For any expression, `IrType` matches the type from `ResolvedSymbol` in `SymbolTable`
    - _Requirements: 3.4, 3.5, 3.6, 3.7, 16.6_

  - [ ]* 8.5 Write property test: auto-property lowering structure
    - **Property 5: Auto-property lowering structure**
    - **Validates: Requirements 4.1**
    - For any auto-property, IR has `PropertyNode` + getter `MethodNode` + setter `MethodNode`
      + backing `FieldNode`
    - _Requirements: 4.1_

  - [ ]* 8.6 Write property test: partial class attribute count preservation
    - **Property 6: Partial class attribute count preservation**
    - **Validates: Requirements 4.4, 16.8**
    - For any partial class with N total attribute applications, merged IR has exactly N
      `AttributeNode` instances
    - _Requirements: 4.4, 16.8_

  - [ ]* 8.7 Write property test: serialization round-trip
    - **Property 7: Serialization round-trip**
    - **Validates: Requirements 13.3, 13.4, 16.3**
    - For any valid `IrCompilationUnit`, serialize then parse produces structurally equal unit
    - _Requirements: 13.3, 13.4, 16.3_

  - [ ]* 8.8 Write property test: IR_Builder output passes validation
    - **Property 8: IR_Builder output passes validation**
    - **Validates: Requirements 14.1–14.6, 14.9, 14.10, 16.4**
    - For any valid `Frontend_Result`, IR_Builder output passes IR_Validator with zero violations
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5, 14.6, 14.9, 14.10, 16.4_

  - [ ]* 8.9 Write property test: determinism
    - **Property 9: Determinism**
    - **Validates: Requirements 12.1, 12.5, 16.2**
    - For any valid `Frontend_Result`, running `IR_Builder.build` twice produces equal results
    - _Requirements: 12.1, 12.5, 16.2_

  - [ ]* 8.10 Write property test: declaration count preservation
    - **Property 10: Declaration count preservation**
    - **Validates: Requirements 16.1**
    - For any valid `Frontend_Result`, top-level IR declaration count equals source declaration
      count (after partial class merging)
    - _Requirements: 16.1_

  - [ ]* 8.11 Write property test: return statement count non-decreasing after lowering
    - **Property 11: Return statement count non-decreasing after lowering**
    - **Validates: Requirements 16.5**
    - For any method body, IR `ReturnStatementNode` count >= source `return` statement count
    - _Requirements: 16.5_

  - [ ]* 8.12 Write property test: constant fidelity
    - **Property 12: Constant fidelity**
    - **Validates: Requirements 11.3, 16.7**
    - For any `const` field or `enum` member, IR literal value equals `ResolvedSymbol.constantValue`
    - _Requirements: 11.3, 16.7_

  - [ ]* 8.13 Write property test: Success iff no Error-severity diagnostic
    - **Property 13: Success iff no Error-severity diagnostic**
    - **Validates: Requirements 15.5, 15.6**
    - For any `IrBuildResult`, `success == (no Error-severity diagnostics)`
    - _Requirements: 15.5, 15.6_

  - [ ]* 8.14 Write property test: IR diagnostic codes are in range IR0001–IR9999
    - **Property 14: IR diagnostic codes are in range IR0001–IR9999**
    - **Validates: Requirements 15.2**
    - For any `IrBuildResult`, all IR-prefixed diagnostic codes have numeric suffix in [1, 9999]
    - _Requirements: 15.2_

  - [ ]* 8.15 Write property test: no duplicate diagnostics for same location and code
    - **Property 15: No duplicate diagnostics for same location and code**
    - **Validates: Requirements 15.3**
    - For any `IrBuildResult`, no two diagnostics share the same code and source location
    - _Requirements: 15.3_

- [ ] 9. Implement `IR_Serializer`
  - Create `lib/src/ir/ir_serializer.dart` implementing `IIrSerializer`
  - Serialize any `IrCompilationUnit` to deterministic, pretty-printed JSON:
    - Use camelCase field names; omit null fields; preserve array order
    - Include every IR_Node type name, every field name, and every IR_Type explicitly
    - Include `UnsupportedNode` and `UnresolvedSymbol` with diagnostic message and source span
  - Implement `parse(String json)` that reconstructs an equivalent `IrCompilationUnit`
  - Throw `IrParseException` on malformed JSON or missing required fields
  - _Requirements: 13.1–13.6_

- [ ]* 10. Write unit tests for `IR_Serializer`
  - Test serialization of each IR_Node type produces expected JSON structure
  - Test `UnsupportedNode` serialization includes diagnostic message and source span
  - Test `parse` reconstructs a unit equal to the original for each node type
  - Test `parse` throws `IrParseException` on malformed JSON
  - Test null fields are omitted from JSON output
  - _Requirements: 13.1–13.6_

- [ ] 11. Implement `IR_Validator` unit tests
  - Test each validation rule independently with a minimal IR tree that violates only that rule
  - Test that all violations are collected (not just the first)
  - Test that a well-formed IR tree produces zero violations
  - Test `IR0032`: async method with non-Task return type
  - Test `IR0033`: abstract + sealed class
  - Test `IR0036`: package symbol missing `sourcePackageId`
  - Test `IR0037`: `AttributeNode` with `Target = Assembly` on a non-`CompilationUnit` node
  - Test `IR0038`: `isFireAndForget = true` on non-Task return type
  - _Requirements: 14.1–14.10_

- [ ] 12. Wire IR stage into the pipeline bootstrap
  - Register `IrBuilder`, `IrValidator`, `IrSerializer` in `lib/src/pipeline_bootstrap.dart`
  - Inject `IConfigService` into `IrBuilder` at construction time
  - Ensure `IrBuildResult` is passed to the next pipeline stage (Dart code generator)
  - _Requirements: 10.1, 10.8_

- [ ] 13. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass (excluding `@Tags(['integration'])` unless fixtures are available)
  - Ask the user if questions arise

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Property tests validate universal correctness properties (Properties 1–15 from the design)
- Unit tests validate specific examples and edge cases
- The IR_Builder has zero Roslyn API dependencies — all data comes from `Frontend_Result`
  plain-data records
