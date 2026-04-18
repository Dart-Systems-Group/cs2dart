# C# → Intermediate Representation (IR) — Design Document

## Overview

The C# → IR stage is the second pipeline stage of the cs2dart transpiler. It receives a
`Frontend_Result` from the Roslyn_Frontend — a collection of fully-resolved, semantically
annotated plain-data records — and produces an `IR_Build_Result` containing a language-agnostic
Intermediate Representation (IR) tree.

The IR is the semantic contract between the C# frontend and the Dart backend. It must capture
behavioral intent precisely enough that the Dart code generator can produce correct, idiomatic
Dart without any further knowledge of C# syntax or Roslyn APIs.

This stage has three primary components:

1. **IR_Builder** — traverses `Frontend_Result` plain-data records and emits IR nodes.
2. **IR_Validator** — checks structural and semantic invariants on a completed IR tree.
3. **IR_Serializer** — serializes IR trees to a canonical JSON representation with round-trip
   support.

The IR_Builder has **no dependency on Roslyn**. All symbol resolution, type information, and
attribute data are read from the `SymbolTable`, `ResolvedSymbol` records, and structured
attribute data in the `Frontend_Result`.

---

## Architecture

### Pipeline Position

```
Roslyn_Frontend
        │
        ▼  Frontend_Result
 ┌─────────────────────────────────────────────────────────────┐
 │                       IR Stage                              │
 │                                                             │
 │  ┌──────────────┐   ┌──────────────┐   ┌────────────────┐  │
 │  │  IR_Builder  │──▶│ IR_Validator │   │ IR_Serializer  │  │
 │  └──────┬───────┘   └──────┬───────┘   └───────┬────────┘  │
 │         │                  │                   │            │
 │         ▼                  ▼                   ▼            │
 │   IR_Build_Result    Validation           JSON / parse      │
 │   (IrCompilationUnit  Diagnostics         round-trip        │
 │    list + Diagnostics)                                      │
 └─────────────────────────────────────────────────────────────┘
        │
        ▼  IR_Build_Result
  Dart Code Generator
```

### Sub-Component Responsibilities

| Sub-Component | Responsibility | Diagnostic Prefix |
|---|---|---|
| `IR_Builder` | Traverse `Frontend_Result`; emit IR nodes; lower complex constructs | `IR` |
| `IR_Validator` | Check structural/semantic invariants on completed IR tree | `IR` |
| `IR_Serializer` | Serialize IR trees to deterministic JSON; parse JSON back to IR | — |

### IR_Builder Internal Structure

The IR_Builder is organized into focused visitor sub-components, each responsible for one
category of C# constructs:

```
IR_Builder
├── DeclarationVisitor   — classes, structs, interfaces, enums, methods, properties, fields
├── StatementVisitor     — blocks, control flow, loops, exception handling, lowering
├── ExpressionVisitor    — literals, identifiers, invocations, LINQ, async/await
├── TypeResolver         — maps ResolvedSymbol type info to IR_Type nodes
├── SymbolResolver       — maps SymbolTable entries to IR_Symbol nodes
├── LoweringEngine       — auto-properties, records, partial classes, using/lock/checked
└── DiagnosticCollector  — aggregates IR-prefixed diagnostics
```

---

## Components and Interfaces

### `IIrBuilder`

The public interface exposed to the pipeline orchestrator:

```dart
abstract interface class IIrBuilder {
  /// Builds an IR tree from [frontendResult].
  ///
  /// Returns an [IrBuildResult] that is always non-null.
  /// [IrBuildResult.success] is false when any Error-severity diagnostic is present.
  IrBuildResult build(FrontendResult frontendResult);
}
```

### `IIrValidator`

```dart
abstract interface class IIrValidator {
  /// Validates structural and semantic invariants on [unit].
  ///
  /// Returns a (possibly empty) list of IR-prefixed diagnostics.
  /// Never throws; collects all violations before returning.
  List<Diagnostic> validate(IrCompilationUnit unit);
}
```

### `IIrSerializer`

```dart
abstract interface class IIrSerializer {
  /// Serializes [unit] to a deterministic, pretty-printed JSON string.
  String serialize(IrCompilationUnit unit);

  /// Parses [json] and reconstructs an equivalent [IrCompilationUnit].
  ///
  /// Throws [IrParseException] if the JSON is malformed or missing required fields.
  IrCompilationUnit parse(String json);
}
```

---

## Data Models

### `IrBuildResult`

The complete output of the IR_Builder:

```dart
final class IrBuildResult {
  /// One IrCompilationUnit per Frontend_Unit, in the same topological order.
  final List<IrCompilationUnit> units;

  /// Aggregated IR-prefixed diagnostics from all units.
  final List<Diagnostic> diagnostics;

  /// True if and only if diagnostics contains no Error-severity entry.
  final bool success;
}
```

### `IrCompilationUnit`

One compiled project's IR:

```dart
final class IrCompilationUnit {
  final String projectName;
  final OutputKind outputKind;
  final String targetFramework;
  final String langVersion;
  final bool nullableEnabled;

  /// NuGet package references with Tier and DartMapping populated.
  final List<PackageReferenceEntry> packageReferences;

  /// Top-level declaration nodes (namespaces, top-level types).
  final List<IrDeclarationNode> declarations;

  /// Diagnostics scoped to this compilation unit.
  final List<Diagnostic> diagnostics;
}
```

### IR Node Hierarchy

All IR nodes share a common base:

```dart
sealed class IrNode {
  final SourceLocation? sourceLocation;
}
```

#### Declaration Nodes

```dart
sealed class IrDeclarationNode extends IrNode {}

final class CompilationUnitNode extends IrDeclarationNode {
  final List<AttributeNode> assemblyAttributes;
  final List<AttributeNode> moduleAttributes;
  final List<IrDeclarationNode> members;
}

final class NamespaceNode extends IrDeclarationNode {
  final String name;
  final List<IrDeclarationNode> members;
}

final class ClassNode extends IrDeclarationNode {
  final String name;
  final Accessibility accessibility;
  final bool isStatic, isAbstract, isSealed, isPartial;
  final IrType? baseClass;
  final List<IrType> implementedInterfaces;
  final List<TypeParameterNode> typeParameters;
  final List<AttributeNode> attributes;
  final List<IrDeclarationNode> members;
}

// StructNode, InterfaceNode, EnumNode, EnumMemberNode, MethodNode,
// ConstructorNode, DestructorNode, PropertyNode, FieldNode, EventNode,
// DelegateNode, TypeParameterNode, ParameterNode, LocalFunctionNode,
// AttributeNode — all follow the same pattern with their specific fields.
```

#### Statement Nodes

```dart
sealed class IrStatementNode extends IrNode {}

// BlockNode, ExpressionStatementNode, ReturnStatementNode, IfStatementNode,
// WhileStatementNode, ForStatementNode, ForEachStatementNode,
// SwitchStatementNode, SwitchCaseNode, BreakStatementNode,
// ContinueStatementNode, ThrowStatementNode, TryCatchStatementNode,
// CatchClauseNode, FinallyClauseNode, LocalDeclarationNode,
// YieldReturnStatementNode, YieldBreakStatementNode
```

#### Expression Nodes

```dart
sealed class IrExpressionNode extends IrNode {
  /// Every expression carries a resolved IR_Type. Non-null after IR_Builder.
  final IrType type;
}

// LiteralNode, IdentifierNode, BinaryExpressionNode, UnaryExpressionNode,
// AssignmentExpressionNode, ConditionalExpressionNode, InvocationExpressionNode,
// MemberAccessExpressionNode, ElementAccessExpressionNode,
// ObjectCreationExpressionNode, ArrayCreationExpressionNode, CastExpressionNode,
// IsExpressionNode, AsExpressionNode, LambdaExpressionNode,
// AnonymousObjectCreationNode, TupleExpressionNode, SwitchExpressionNode,
// ThrowExpressionNode, AwaitExpressionNode, InterpolatedStringNode,
// NullCoalescingExpressionNode, NullConditionalExpressionNode
```

#### Type Nodes

```dart
sealed class IrType {}

// PrimitiveType, NamedType, GenericType, ArrayType, NullableType,
// TupleType, FunctionType, VoidType, DynamicType
```

### `IrSymbol`

A stable, fully-qualified identifier for a named entity:

```dart
final class IrSymbol {
  final String fullyQualifiedName;
  final String assemblyName;
  final SymbolKind kind; // Type, Method, Field, Property, Event, Local, Parameter
  final SourceLocation? sourceLocation;
  final String? sourcePackageId;
  /// Non-null when the symbol refers to a type within the compilation unit.
  final IrDeclarationNode? declarationNode;
}
```

### `AttributeNode`

```dart
final class AttributeNode extends IrDeclarationNode {
  final String fullyQualifiedName;
  final String shortName;
  final List<IrExpressionNode> positionalArguments;
  final List<NamedArgument> namedArguments;
  final AttributeTarget target;
  // sourceLocation inherited from IrNode
}

enum AttributeTarget {
  classTarget, structTarget, interfaceTarget, enumTarget, enumMember,
  method, constructor, property, field, parameter, returnValue,
  assembly, module
}
```

### `UnsupportedNode` and `UnresolvedSymbol`

```dart
final class UnsupportedNode extends IrNode {
  final String description;
  final SourceLocation sourceSpan;
  final Diagnostic diagnostic;
}

final class UnresolvedSymbol extends IrExpressionNode {
  final String originalText;
  final SourceLocation sourceSpan;
}
```

---

## Processing Flow

### IR_Builder Processing Flow

```
1. Receive Frontend_Result
2. For each Frontend_Unit (in topological order provided):
   a. Create IrCompilationUnit with metadata from Frontend_Unit
   b. For each Normalized_SyntaxTree (in alphabetical file path order):
      i.  DeclarationVisitor traverses top-level declarations
      ii. For each declaration, SymbolResolver resolves IR_Symbols from SymbolTable
      iii. TypeResolver resolves IR_Types from ResolvedSymbol records
      iv. LoweringEngine applies lowering rules (auto-props, records, partial merge, etc.)
      v.  StatementVisitor and ExpressionVisitor handle bodies
      vi. DiagnosticCollector accumulates IR-prefixed diagnostics
   c. After all trees processed: merge partial class declarations
   d. Attach PackageReferences from Frontend_Unit
3. Collect all diagnostics; set success = (no Error-severity diagnostics)
4. Return IrBuildResult
```

### Lowering Rules Summary

| C# Construct | Lowered IR Form |
|---|---|
| Auto-property `{ get; set; }` | `PropertyNode` + getter `MethodNode` + setter `MethodNode` + backing `FieldNode` |
| Primary constructor (C# 12) | Explicit `ConstructorNode` + `ParameterNode` list + `FieldNode` list |
| Record type | `ClassNode` (or `StructNode`) + synthesized equality, `ToString`, `Deconstruct` `MethodNode`s |
| Partial class | Single merged `ClassNode` with unioned `AttributeNode` lists |
| Static constructor | `ConstructorNode` with `isStatic = true` |
| Indexer | `MethodNode` with name `get_Item`/`set_Item` and `isIndexer = true` |
| Explicit interface impl | `MethodNode` with `explicitInterface` field |
| Extension method | `MethodNode` with `isExtension = true` and `extendedType` field |
| `foreach` | `ForEachStatementNode` with element type and collection expression |
| `using` statement | `TryCatchStatementNode` with `FinallyClause` calling `Dispose()` |
| `lock` statement | `TryCatchStatementNode` with `Monitor.Enter`/`Monitor.Exit` |
| `checked`/`unchecked` | `OverflowCheck` flag on contained `BinaryExpressionNode`s |
| `goto` | `UnsupportedNode` + `IR`-prefixed Error diagnostic |
| LINQ query syntax | Normalized to LINQ method-chain form first |
| LINQ (lower_to_loops) | `ForEachStatementNode` + `LocalDeclarationNode` chains |
| LINQ (preserve_functional) | `InvocationExpressionNode` chains with LINQ IR_Symbols |
| `unsafe`/`fixed` | `UnsupportedNode` + `IR`-prefixed Error diagnostic |

### Partial Class Merge Order

When merging partial class declarations, `AttributeNode` lists are ordered:
1. Primary sort: fully-qualified attribute name (alphabetical, lexicographic)
2. Secondary sort: source file path (alphabetical, lexicographic)
3. Tertiary sort: line number (ascending)

No deduplication is performed — every attribute application is preserved.

### LINQ Strategy

The `linqStrategy` field from `Mapping_Config` controls LINQ lowering:

| Config Value | Behavior |
|---|---|
| `lower_to_loops` | Lower LINQ chains to `ForEachStatement` + `LocalDeclaration` nodes |
| `preserve_functional` | Preserve LINQ method-chain `InvocationExpression` nodes |
| *(not set / default)* | Apply `preserve_functional` behavior |

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a
system — essentially, a formal statement about what the system should do. Properties serve as the
bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Every reference node carries a non-null IR_Symbol

*For any* valid `Frontend_Result`, every `IdentifierNode`, `MemberAccessExpressionNode`,
`InvocationExpressionNode`, `ObjectCreationExpressionNode`, and type reference node in the
resulting IR tree SHALL carry a non-null `IrSymbol`.

**Validates: Requirements 2.1, 2.2**

---

### Property 2: Every typed node carries a non-null IR_Type

*For any* valid `Frontend_Result`, every `IrExpressionNode`, `ParameterNode`, `FieldNode`,
`PropertyNode`, and `LocalDeclarationNode` in the resulting IR tree SHALL carry a non-null
`IrType`.

**Validates: Requirements 3.1, 14.1, 16.6**

---

### Property 3: Nullable type representation round-trip

*For any* C# nullable type (reference or value-type nullable) in the source, the corresponding
`IrType` in the IR SHALL be a `NullableType` wrapping the underlying base `IrType`, and the
wrapped type SHALL be structurally equal to the `IrType` that would be produced for the
non-nullable version of the same type.

**Validates: Requirements 3.2, 3.3**

---

### Property 4: Type fidelity

*For any* C# expression in the source, the `IrType` attached to the corresponding
`IrExpressionNode` SHALL be structurally equal to the type derived from the `ResolvedSymbol`
record for that expression in the `SymbolTable`.

**Validates: Requirements 3.4, 3.5, 3.6, 3.7, 16.6**

---

### Property 5: Auto-property lowering structure

*For any* auto-property declaration in the source, the IR SHALL contain a `PropertyNode` with
at least one associated getter `MethodNode` (for readable properties), at least one setter
`MethodNode` (for writable properties), and a backing `FieldNode` — all with names and types
consistent with the original property declaration.

**Validates: Requirements 4.1**

---

### Property 6: Partial class attribute count preservation

*For any* `Frontend_Unit` containing a partial class whose parts collectively carry `N` total
`AttributeNode` instances across all parts (on the class itself or on any member), the merged
`ClassNode` and its member nodes SHALL together carry exactly `N` `AttributeNode` instances —
no attribute application from any partial part SHALL be dropped.

**Validates: Requirements 4.4, 16.8**

---

### Property 7: Serialization round-trip

*For any* valid `IrCompilationUnit`, serializing it to JSON with `IR_Serializer` and then
parsing the resulting JSON SHALL produce an `IrCompilationUnit` that is structurally and
value-equal to the original.

**Validates: Requirements 13.3, 13.4, 16.3**

---

### Property 8: IR_Builder output passes validation

*For any* valid `Frontend_Result`, the `IrCompilationUnit` values produced by `IR_Builder`
SHALL pass `IR_Validator` with zero violations.

**Validates: Requirements 14.1–14.6, 14.9, 14.10, 16.4**

---

### Property 9: Determinism

*For any* valid `Frontend_Result`, invoking `IR_Builder.build` twice on the same input SHALL
produce `IrBuildResult` values that are structurally and value-equal.

**Validates: Requirements 12.1, 12.5, 16.2**

---

### Property 10: Declaration count preservation

*For any* valid `Frontend_Result`, the count of top-level `IrDeclarationNode` items in the
resulting IR SHALL equal the count of top-level type declarations in the source (after partial
class merging).

**Validates: Requirements 16.1**

---

### Property 11: Return statement count non-decreasing after lowering

*For any* C# method body, the count of `ReturnStatementNode` nodes in the lowered IR SHALL be
greater than or equal to the count of `return` statements in the original source body.

**Validates: Requirements 16.5**

---

### Property 12: Constant fidelity

*For any* C# `const` field or `enum` member declaration, the literal value stored in the
corresponding `FieldNode` or `EnumMemberNode` in the IR SHALL equal the compile-time constant
value recorded in `ResolvedSymbol.constantValue` for that declaration.

**Validates: Requirements 11.3, 16.7**

---

### Property 13: Success iff no Error-severity diagnostic

*For any* `IrBuildResult`, `success` SHALL be `true` if and only if `diagnostics` contains no
entry with `severity == Error`.

**Validates: Requirements 15.5, 15.6**

---

### Property 14: IR diagnostic codes are in range IR0001–IR9999

*For any* `IrBuildResult`, every `Diagnostic` whose `code` starts with `"IR"` SHALL have a
numeric suffix in the range `[1, 9999]`, and no diagnostic with a non-`"IR"` prefix SHALL be
emitted by the IR_Builder.

**Validates: Requirements 15.2**

---

### Property 15: No duplicate diagnostics for same location and code

*For any* `IrBuildResult`, no two `Diagnostic` entries SHALL share the same `code` and
`location` (source file path + line + column).

**Validates: Requirements 15.3**

---

## Error Handling

### Unsupported Constructs

| Condition | Diagnostic | Behavior |
|---|---|---|
| C# construct with no IR_Node subtype | `IR0001` Error | Emit `UnsupportedNode` with source span; continue |
| `goto` / labeled statement | `IR0002` Error | Emit `UnsupportedNode`; continue |
| `unsafe` block or `fixed` statement | `IR0003` Error | Emit `UnsupportedNode`; continue |
| `dynamic` expression | `IR0010` Warning | Emit `DynamicType` node; continue |
| Unawaited `Task`-returning call | `IR0011` Warning | Set `isFireAndForget = false`; continue |

### Symbol Resolution Failures

| Condition | Diagnostic | Behavior |
|---|---|---|
| `SymbolTable` entry has `Kind = Unresolved` | `IR0020` Warning | Emit `UnresolvedSymbol` node; continue |
| `Unsupported` marker from Roslyn_Frontend | `IR0021` Warning | Emit `UnsupportedNode`; continue |
| `UnknownAttribute` marker from Roslyn_Frontend | `IR0022` Warning | Emit `UnsupportedNode`; continue |

### Validation Violations

| Condition | Diagnostic | Behavior |
|---|---|---|
| Expression node missing `IrType` | `IR0030` Error | Collect; continue validation |
| Reference node missing `IrSymbol` | `IR0031` Error | Collect; continue validation |
| Async method with non-Task return type | `IR0032` Error | Collect; continue validation |
| Abstract + Sealed class | `IR0033` Error | Collect; continue validation |
| TypeParameter not in enclosing declaration | `IR0034` Error | Collect; continue validation |
| CatchClause WhenExpression not bool | `IR0035` Error | Collect; continue validation |
| Package symbol missing SourcePackageId | `IR0036` Error | Collect; continue validation |
| AttributeNode with invalid Target for node type | `IR0037` Error | Collect; continue validation |
| FireAndForget on non-Task return type | `IR0038` Error | Collect; continue validation |

### General Principles

- The IR_Builder **never throws** on unsupported constructs; it always emits a diagnostic and
  substitutes a placeholder node.
- The IR_Validator **never throws**; it collects all violations and returns them as a list.
- When any Error-severity diagnostic is present, `IrBuildResult.success` is `false`, but the
  most complete IR tree possible (with `UnsupportedNode` placeholders) is still returned.
- Diagnostics are deduplicated by `(code, sourceLocation)` before being added to the result.

---

## Testing Strategy

### Dual Testing Approach

The IR stage is tested with both unit/example-based tests and property-based tests.

**Unit tests** cover:
- Specific lowering examples (auto-property, record, partial class, using, lock, LINQ)
- Error conditions with specific unsupported constructs (goto, unsafe)
- Symbol resolution with known `SymbolTable` fixtures
- Serialization of specific IR trees to expected JSON strings
- Validation of specific invalid IR trees (missing types, bad async return types)

**Property-based tests** cover:
- Universal invariants that hold across all valid inputs (Properties 1–15 above)
- Edge cases generated by the property framework (empty bodies, deeply nested generics,
  large partial classes, etc.)

### Property-Based Testing Library

Property-based tests use the Dart-native [propcheck](https://pub.dev/packages/propcheck) package.
Each property test runs a minimum of **100 iterations**.

Each property test is tagged with a comment referencing the design property:

```dart
// Feature: ir-mapping, Property 7: Serialization round-trip
test('serialization round-trip', () {
  propcheck.forAll(
    arbitraryIrCompilationUnit(),
    (unit) {
      final json = serializer.serialize(unit);
      final parsed = serializer.parse(json);
      expect(parsed, structurallyEquals(unit));
    },
    numRuns: 100,
  );
});
```

### Test Doubles

All sub-components are injected via constructor injection:

- **`FakeFrontendResult`**: builds `Frontend_Result` from in-memory C# snippet fixtures without
  invoking Roslyn.
- **`FakeSymbolTable`**: returns pre-populated `ResolvedSymbol` records for known identifiers.
- **`FakeConfigService`**: returns a fixed `Mapping_Config` with a specified `linqStrategy`.

### Generators for Property Tests

Property tests require generators for:

- `ArbitraryFrontendUnit` — generates `Frontend_Unit` records with random but valid
  `Normalized_SyntaxTree` structures (using a small grammar of supported C# constructs).
- `ArbitraryIrCompilationUnit` — generates well-formed `IrCompilationUnit` trees directly
  (for serialization round-trip tests).
- `ArbitraryPartialClass` — generates a partial class split across 2–5 files with random
  attribute applications, for testing the partial merge property.

### Integration Tests

A small set of integration tests run against real `Frontend_Result` fixtures produced from
the `test/fixtures/` C# projects:

- `test/fixtures/simple_console/` — verifies basic declaration and statement lowering
- `test/fixtures/multi_project_solution/` — verifies cross-project symbol resolution
- `test/fixtures/nullable_enabled/` — verifies nullable type representation

Integration tests are tagged `@Tags(['integration'])` and excluded from the default test run.
