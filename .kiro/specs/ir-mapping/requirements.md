# C# → Intermediate Representation (IR) — Requirements Document

## Introduction

This document specifies the requirements for the **C# → IR** pipeline stage of the C# → Dart transpiler.
This stage receives a fully resolved, semantically annotated Roslyn syntax tree and produces a
language-agnostic Intermediate Representation (IR) that downstream stages (optimizers, Dart code
generator) consume.

The IR is the semantic contract between the C# frontend and the Dart backend. It must capture
behavioral intent precisely enough that the Dart code generator can produce correct, idiomatic Dart
without any further knowledge of C# syntax or Roslyn APIs.

---

## Glossary

- **IR**: The language-agnostic Intermediate Representation produced by this stage.
- **IR_Builder**: The component that traverses the Roslyn semantic model and emits IR nodes.
- **IR_Node**: A single typed node in the IR tree (declaration, statement, expression, or type).
- **IR_Type**: A typed representation of a C# type within the IR (primitive, generic, nullable, etc.).
- **IR_Symbol**: A stable, fully-qualified identifier for a named entity (type, method, field, etc.).
- **Roslyn_Model**: The Roslyn `SemanticModel` and `SyntaxTree` pair provided as input to this stage.
- **Lowered_Form**: A simplified IR representation of a high-level C# construct (e.g., LINQ lowered to loops).
- **Pretty_Printer**: The component that serializes an IR tree to a canonical, human-readable text format.
- **Round_Trip**: The property that parsing a Pretty_Printer output reproduces an equivalent IR tree.
- **IR_Validator**: The component that checks structural and semantic invariants on a completed IR tree.
- **Semantic_Fidelity**: The guarantee that the IR preserves the observable behavior of the source C# program.
- **Determinism**: The guarantee that the same Roslyn_Model input always produces the same IR output.

---

## Requirements

### Requirement 1: IR Node Taxonomy

**User Story:** As a Dart code generator author, I want a well-defined, exhaustive set of IR node types,
so that I can write a complete, switch-exhaustive visitor without handling raw C# or Roslyn concepts.

#### Acceptance Criteria

1. THE IR_Builder SHALL represent every C# construct supported by the transpiler as exactly one IR_Node subtype.
2. THE IR SHALL organize nodes into four top-level categories: **Declarations**, **Statements**, **Expressions**, and **Types**.
3. THE IR SHALL include the following Declaration node types: `CompilationUnit`, `Namespace`, `Class`, `Struct`, `Interface`, `Enum`, `EnumMember`, `Method`, `Constructor`, `Destructor`, `Property`, `Field`, `Event`, `Delegate`, `TypeParameter`, `Parameter`, `LocalFunction`.
4. THE IR SHALL include the following Statement node types: `Block`, `ExpressionStatement`, `ReturnStatement`, `IfStatement`, `WhileStatement`, `ForStatement`, `ForEachStatement`, `SwitchStatement`, `SwitchCase`, `BreakStatement`, `ContinueStatement`, `ThrowStatement`, `TryCatchStatement`, `CatchClause`, `FinallyClause`, `LocalDeclaration`, `YieldReturnStatement`, `YieldBreakStatement`.
5. THE IR SHALL include the following Expression node types: `Literal`, `Identifier`, `BinaryExpression`, `UnaryExpression`, `AssignmentExpression`, `ConditionalExpression`, `InvocationExpression`, `MemberAccessExpression`, `ElementAccessExpression`, `ObjectCreationExpression`, `ArrayCreationExpression`, `CastExpression`, `IsExpression`, `AsExpression`, `LambdaExpression`, `AnonymousObjectCreation`, `TupleExpression`, `SwitchExpression`, `ThrowExpression`, `AwaitExpression`, `InterpolatedString`, `NullCoalescingExpression`, `NullConditionalExpression`.
6. THE IR SHALL include the following Type node types: `PrimitiveType`, `NamedType`, `GenericType`, `ArrayType`, `NullableType`, `TupleType`, `FunctionType`, `VoidType`, `DynamicType`.
7. IF a C# construct has no corresponding IR_Node subtype, THEN THE IR_Builder SHALL emit a diagnostic and substitute an `UnsupportedNode` placeholder that carries the original source span and a human-readable description.

---

### Requirement 2: IR Symbol Resolution

**User Story:** As a downstream code generator, I want every named reference in the IR to carry a
stable, fully-qualified symbol identity, so that I can resolve cross-file and cross-assembly references
without re-parsing C# source.

#### Acceptance Criteria

1. THE IR_Builder SHALL attach an IR_Symbol to every `Identifier`, `MemberAccessExpression`, `InvocationExpression`, `ObjectCreationExpression`, and type reference node.
2. THE IR_Symbol SHALL contain: a fully-qualified name, the declaring assembly name, the kind (type, method, field, property, event, local, parameter), and a nullable source location.
3. WHEN a symbol refers to a type defined within the compilation unit, THE IR_Symbol SHALL include a reference to the corresponding Declaration IR_Node.
4. WHEN a symbol refers to a type from an external assembly, THE IR_Symbol SHALL record the assembly name and fully-qualified CLR type name.
5. IF the Roslyn_Model cannot resolve a symbol, THEN THE IR_Builder SHALL emit an `UnresolvedSymbol` node with the original identifier text and source span, and SHALL continue processing remaining nodes.
6. THE IR_Builder SHALL resolve all overloaded method references to the specific overload selected by Roslyn, so that the IR contains no ambiguous method references.

---

### Requirement 3: Type Representation

**User Story:** As a Dart code generator author, I want every expression and declaration in the IR to
carry explicit, fully-resolved type information, so that I can emit correct Dart type annotations
without performing type inference myself.

#### Acceptance Criteria

1. THE IR_Builder SHALL attach an IR_Type to every Expression node, every Parameter node, every Field node, every Property node, and every LocalDeclaration node.
2. THE IR_Builder SHALL represent C# nullable reference types (e.g., `string?`) as `NullableType` wrapping the underlying IR_Type.
3. THE IR_Builder SHALL represent C# value-type nullables (e.g., `int?`) as `NullableType` wrapping the corresponding `PrimitiveType`.
4. THE IR_Builder SHALL represent open generic type parameters as `TypeParameter` nodes carrying their declared constraints.
5. THE IR_Builder SHALL represent closed generic types (e.g., `List<int>`) as `GenericType` nodes carrying the base `NamedType` and a list of resolved type argument IR_Types.
6. THE IR_Builder SHALL represent C# tuple types (e.g., `(int x, string y)`) as `TupleType` nodes carrying named element IR_Types.
7. THE IR_Builder SHALL represent delegate and lambda types as `FunctionType` nodes carrying parameter IR_Types and a return IR_Type.
8. WHEN a C# expression has type `dynamic`, THE IR_Builder SHALL emit a `DynamicType` node and attach a diagnostic warning.

---

### Requirement 4: Declaration Lowering

**User Story:** As a Dart code generator author, I want complex C# declaration patterns lowered to
simpler, normalized IR forms, so that I do not need to handle multiple syntactic representations of
the same semantic construct.

#### Acceptance Criteria

1. THE IR_Builder SHALL lower auto-properties (e.g., `public int X { get; set; }`) to a `Property` node with explicit getter and setter `Method` nodes and a backing `Field` node.
2. THE IR_Builder SHALL lower primary constructors (C# 12) to an explicit `Constructor` node with corresponding `Parameter` and `Field` nodes.
3. THE IR_Builder SHALL lower record types to a `Class` node (or `Struct` node for record structs) with synthesized equality members, `ToString`, and `Deconstruct` methods represented as explicit IR `Method` nodes.
4. THE IR_Builder SHALL lower C# `partial` classes by merging all partial declarations into a single `Class` IR_Node before emitting.
5. THE IR_Builder SHALL lower static constructors to a `Constructor` node with `IsStatic = true`.
6. THE IR_Builder SHALL lower indexers to a `Method` node with name `get_Item` or `set_Item` and an `IsIndexer = true` flag.
7. THE IR_Builder SHALL lower explicit interface implementations to `Method` nodes with an `ExplicitInterface` field referencing the implemented interface IR_Symbol.
8. THE IR_Builder SHALL lower extension methods to `Method` nodes with `IsExtension = true` and the extended type recorded in a `ExtendedType` field.

---

### Requirement 5: Statement Lowering

**User Story:** As a Dart code generator author, I want complex C# statement forms lowered to a
minimal, normalized set of IR statements, so that the code generator handles a small, well-defined
statement vocabulary.

#### Acceptance Criteria

1. THE IR_Builder SHALL lower `foreach` over arrays and `IEnumerable<T>` to a `ForEachStatement` IR node carrying the element IR_Type, the collection expression, and the loop body.
2. THE IR_Builder SHALL lower C# `using` statements and `using` declarations to a `TryCatchStatement` IR node with a `FinallyClause` that calls `Dispose()` on the resource.
3. THE IR_Builder SHALL lower C# `lock` statements to a `TryCatchStatement` IR node with `Monitor.Enter` and `Monitor.Exit` calls in the body and finally clause respectively.
4. THE IR_Builder SHALL lower `checked` and `unchecked` blocks by annotating contained arithmetic `BinaryExpression` nodes with an `OverflowCheck` flag rather than emitting wrapper nodes.
5. THE IR_Builder SHALL lower `goto` and labeled statements to a diagnostic `UnsupportedNode` with a message indicating that `goto` is not supported, and SHALL continue processing.
6. THE IR_Builder SHALL lower C# 8+ switch expressions to `SwitchExpression` IR nodes carrying a list of arm pairs (pattern IR_Node, result Expression IR_Node).
7. THE IR_Builder SHALL lower C# pattern matching constructs (type patterns, property patterns, positional patterns) to structured `Pattern` IR nodes attached to `SwitchCase` and `IsExpression` nodes.

---

### Requirement 6: LINQ Lowering

**User Story:** As a Dart code generator author, I want LINQ query expressions and method-chain LINQ
calls represented in the IR as explicit loop or functional-chain IR nodes, so that I can emit
idiomatic Dart collection operations without understanding LINQ semantics.

#### Acceptance Criteria

1. THE IR_Builder SHALL lower LINQ query syntax (e.g., `from x in xs where ... select ...`) to equivalent LINQ method-chain form before emitting IR nodes.
2. THE IR_Builder SHALL represent each LINQ method call (`Where`, `Select`, `OrderBy`, `GroupBy`, `Join`, `Aggregate`, etc.) as an `InvocationExpression` IR node with the method resolved to its `System.Linq.Enumerable` or `System.Linq.Queryable` IR_Symbol.
3. WHERE the transpiler configuration specifies `linq_strategy: lower_to_loops`, THE IR_Builder SHALL lower LINQ chains to equivalent `ForEachStatement` and `LocalDeclaration` IR nodes.
4. WHERE the transpiler configuration specifies `linq_strategy: preserve_functional`, THE IR_Builder SHALL preserve LINQ method-chain `InvocationExpression` nodes for the Dart code generator to map to Dart collection methods.
5. THE IR_Builder SHALL attach the element IR_Type and result IR_Type to every LINQ `InvocationExpression` node.

---

### Requirement 7: Async/Await Representation

**User Story:** As a Dart code generator author, I want async methods and await expressions
represented faithfully in the IR, so that I can emit correct Dart `async`/`await` code.

#### Acceptance Criteria

1. THE IR_Builder SHALL mark every `Method` and `LocalFunction` IR node with an `IsAsync` boolean flag.
2. THE IR_Builder SHALL represent every `await` expression as an `AwaitExpression` IR node carrying the awaited expression and the resolved result IR_Type.
3. THE IR_Builder SHALL represent `Task<T>` return types as `GenericType` nodes with base name `Task` and type argument `T`, preserving the distinction between `Task`, `Task<T>`, and `ValueTask<T>`.
4. THE IR_Builder SHALL represent `async IAsyncEnumerable<T>` methods with `IsAsync = true`, `IsIterator = true`, and return IR_Type `IAsyncEnumerable<T>`.
5. THE IR_Builder SHALL represent `ConfigureAwait(false)` calls as `AwaitExpression` nodes with a `ConfigureAwait = false` flag rather than as a generic `InvocationExpression`.

---

### Requirement 8: Exception Handling Representation

**User Story:** As a Dart code generator author, I want exception handling constructs represented
completely in the IR, so that I can emit correct Dart `try`/`catch`/`finally` blocks.

#### Acceptance Criteria

1. THE IR_Builder SHALL represent every `try`/`catch`/`finally` block as a `TryCatchStatement` IR node carrying zero or more `CatchClause` nodes and an optional `FinallyClause` node.
2. THE IR_Builder SHALL attach the caught exception IR_Type and an optional exception variable IR_Symbol to each `CatchClause` node.
3. THE IR_Builder SHALL represent exception filters (`catch (Exception e) when (condition)`) as a `CatchClause` node with a `WhenExpression` field.
4. THE IR_Builder SHALL represent `throw` statements as `ThrowStatement` IR nodes and `throw` expressions as `ThrowExpression` IR nodes, each carrying the thrown expression.
5. THE IR_Builder SHALL represent bare `throw` (rethrow) as a `ThrowStatement` with a null thrown expression and a `IsRethrow = true` flag.

---

### Requirement 9: Generics and Constraints

**User Story:** As a Dart code generator author, I want generic type parameters and their constraints
fully represented in the IR, so that I can emit correct Dart generic bounds.

#### Acceptance Criteria

1. THE IR_Builder SHALL represent every generic type parameter as a `TypeParameter` IR node carrying its name, variance (none, covariant, contravariant), and a list of constraint IR_Types.
2. THE IR_Builder SHALL represent `where T : class` as a `ReferenceTypeConstraint` on the `TypeParameter` node.
3. THE IR_Builder SHALL represent `where T : struct` as a `ValueTypeConstraint` on the `TypeParameter` node.
4. THE IR_Builder SHALL represent `where T : new()` as a `DefaultConstructorConstraint` on the `TypeParameter` node.
5. THE IR_Builder SHALL represent `where T : SomeBase` as a `BaseTypeConstraint` carrying the base IR_Type on the `TypeParameter` node.
6. THE IR_Builder SHALL represent `where T : notnull` as a `NotNullConstraint` on the `TypeParameter` node.
7. THE IR_Builder SHALL attach the list of `TypeParameter` IR nodes to every `Class`, `Struct`, `Interface`, `Method`, and `Delegate` IR node that declares type parameters.

---

### Requirement 10: Roslyn Frontend Integration Contract

**User Story:** As a pipeline integrator, I want a well-defined input contract for the IR_Builder,
so that the Roslyn frontend and the IR stage can evolve independently.

#### Acceptance Criteria

1. THE IR_Builder SHALL accept as input a Roslyn `Compilation` object that has been fully bound (no unresolved references) and a list of `SyntaxTree` objects belonging to that compilation.
2. THE IR_Builder SHALL not invoke Roslyn APIs that trigger re-parsing or re-binding; it SHALL read only from the already-computed `SemanticModel`.
3. THE IR_Builder SHALL process each `SyntaxTree` in a deterministic order (alphabetical by file path) to ensure Determinism.
4. WHEN the Roslyn `SemanticModel` reports binding errors for a node, THE IR_Builder SHALL emit an `UnresolvedSymbol` or `UnsupportedNode` placeholder and SHALL continue processing remaining nodes rather than aborting.
5. THE IR_Builder SHALL expose a single public entry point: `IrCompilationUnit Build(Compilation compilation)` (or language-equivalent), with no mutable global state.
6. THE IR_Builder SHALL complete processing of a single `SyntaxTree` without retaining references to Roslyn objects after that tree's IR subtree is emitted, to allow incremental memory release.

---

### Requirement 11: Semantic Fidelity

**User Story:** As a transpiler user, I want the IR to preserve the observable semantics of the
source C# program, so that the generated Dart code behaves identically to the original C# code
within the supported feature set.

#### Acceptance Criteria

1. THE IR_Builder SHALL preserve the declared accessibility of every declaration (public, internal, protected, private, protected internal, private protected) as an `Accessibility` enum field on the IR node.
2. THE IR_Builder SHALL preserve the `static`, `abstract`, `virtual`, `override`, `sealed`, `readonly`, `const`, and `extern` modifiers as boolean flags on the relevant IR nodes.
3. THE IR_Builder SHALL preserve the exact constant value of every `const` field and `enum` member as a typed literal in the IR.
4. THE IR_Builder SHALL preserve the inheritance chain: every `Class` IR node SHALL carry a nullable `BaseClass` IR_Type and a list of `ImplementedInterfaces` IR_Types.
5. THE IR_Builder SHALL preserve operator overloads as `Method` IR nodes with `IsOperator = true` and an `OperatorKind` enum field.
6. THE IR_Builder SHALL preserve implicit and explicit conversion operators as `Method` IR nodes with `IsConversion = true` and `IsImplicit` / `IsExplicit` flags.
7. THE IR_Builder SHALL preserve the evaluation order of arguments in `InvocationExpression` nodes by storing arguments as an ordered list.
8. WHEN a C# construct has defined but unsupported semantics (e.g., `unsafe` blocks, `fixed` statements), THE IR_Builder SHALL emit a diagnostic and substitute an `UnsupportedNode` rather than silently dropping the construct.

---

### Requirement 12: Determinism

**User Story:** As a CI/CD pipeline operator, I want the IR_Builder to produce identical output for
identical input on every run, so that build caches and golden-file tests remain stable.

#### Acceptance Criteria

1. THE IR_Builder SHALL produce identical IR trees for identical `Compilation` inputs regardless of the order in which `SemanticModel` queries are issued internally.
2. THE IR_Builder SHALL sort all collections within IR nodes (e.g., interface lists, attribute lists) in a canonical order (alphabetical by fully-qualified name) when the source order is not semantically significant.
3. THE IR_Builder SHALL not use hash-based data structures whose iteration order is non-deterministic (e.g., `Dictionary<K,V>` without sorted enumeration) when building ordered IR collections.
4. THE IR_Builder SHALL not embed timestamps, process IDs, or other environment-dependent values in IR nodes.
5. FOR ALL valid C# compilations, running THE IR_Builder twice on the same input SHALL produce IR trees that are structurally and value-equal.

---

### Requirement 13: IR Serialization and Pretty Printing

**User Story:** As a developer debugging the transpiler, I want to serialize and deserialize IR trees
to a stable text format, so that I can inspect IR output, write golden tests, and verify round-trip
correctness.

#### Acceptance Criteria

1. THE Pretty_Printer SHALL serialize any IR tree to a deterministic, human-readable text representation.
2. THE Pretty_Printer SHALL produce output where every IR_Node type, every field name, and every IR_Type is explicitly named (no implicit or positional encoding).
3. THE IR_Builder SHALL provide a parser that reads Pretty_Printer output and reconstructs an equivalent IR tree.
4. FOR ALL valid IR trees, parsing the Pretty_Printer output SHALL produce an IR tree that is structurally and value-equal to the original (round-trip property).
5. THE Pretty_Printer SHALL format IR trees consistently: one node per line, indented by nesting depth, with field names preceding values.
6. WHEN the Pretty_Printer encounters an `UnsupportedNode` or `UnresolvedSymbol`, THE Pretty_Printer SHALL include the diagnostic message and source span in the serialized output.

---

### Requirement 14: IR Validation

**User Story:** As a pipeline integrator, I want an IR validator that checks structural and semantic
invariants after the IR is built, so that downstream stages can assume a well-formed IR and report
errors early.

#### Acceptance Criteria

1. THE IR_Validator SHALL verify that every Expression node carries a non-null IR_Type.
2. THE IR_Validator SHALL verify that every Identifier and reference node carries a non-null IR_Symbol.
3. THE IR_Validator SHALL verify that every `Method` node with `IsAsync = true` has a return IR_Type of `Task`, `Task<T>`, `ValueTask`, `ValueTask<T>`, or `IAsyncEnumerable<T>`.
4. THE IR_Validator SHALL verify that every `Class` node that declares `IsAbstract = true` does not also declare `IsSealed = true`.
5. THE IR_Validator SHALL verify that every `TypeParameter` node referenced in a `GenericType` is declared in the enclosing generic declaration's type parameter list.
6. THE IR_Validator SHALL verify that every `CatchClause` node within a `TryCatchStatement` that has a `WhenExpression` has that expression typed as `bool`.
7. WHEN THE IR_Validator detects a violation, THE IR_Validator SHALL collect all violations and return them as a list of structured diagnostics rather than throwing on the first error.
8. THE IR_Validator SHALL complete validation of any IR tree in time proportional to the number of IR nodes in the tree.

---

### Requirement 15: Diagnostics and Error Reporting

**User Story:** As a transpiler user, I want clear, actionable diagnostics when C# constructs cannot
be represented in the IR, so that I know exactly what to fix or what to expect in the generated output.

#### Acceptance Criteria

1. THE IR_Builder SHALL emit a structured diagnostic for every `UnsupportedNode` and `UnresolvedSymbol` it produces.
2. EACH diagnostic SHALL contain: a severity level (Error, Warning, Info), a stable diagnostic code, a human-readable message, and the source file path and line/column span.
3. THE IR_Builder SHALL not emit duplicate diagnostics for the same source location and diagnostic code.
4. THE IR_Builder SHALL aggregate all diagnostics and return them alongside the IR tree rather than writing to standard output or throwing exceptions.
5. WHEN all diagnostics have severity Warning or Info (no Errors), THE IR_Builder SHALL return a complete IR tree alongside the diagnostics.
6. WHEN any diagnostic has severity Error, THE IR_Builder SHALL still return the most complete IR tree possible (with `UnsupportedNode` placeholders) alongside the error diagnostics.

---

### Requirement 16: Correctness Properties for Testing

**User Story:** As a transpiler test engineer, I want well-defined correctness properties for the
IR_Builder, so that I can write property-based tests that catch regressions across a wide range of
C# inputs.

#### Acceptance Criteria

1. FOR ALL valid C# compilations, THE IR_Builder SHALL produce an IR tree where the count of top-level Declaration nodes equals the count of top-level type declarations in the source (invariant: declaration count preservation).
2. FOR ALL valid C# compilations, running THE IR_Builder twice SHALL produce structurally equal IR trees (determinism property).
3. FOR ALL valid IR trees, THE Pretty_Printer output parsed by the IR parser SHALL produce a structurally equal IR tree (round-trip property).
4. FOR ALL valid IR trees, applying THE IR_Validator SHALL produce zero violations (well-formedness invariant for IR_Builder output).
5. FOR ALL C# method bodies, the count of `ReturnStatement` IR nodes in the lowered IR SHALL be greater than or equal to the count of `return` statements in the original source (lowering may introduce additional returns, but SHALL NOT remove any).
6. FOR ALL C# expressions, the IR_Type attached to the IR expression node SHALL be equal to the type reported by the Roslyn `SemanticModel` for the corresponding syntax node (type fidelity property).
7. FOR ALL C# `const` declarations, the literal value in the IR `Field` node SHALL equal the compile-time constant value reported by Roslyn (constant fidelity property).
