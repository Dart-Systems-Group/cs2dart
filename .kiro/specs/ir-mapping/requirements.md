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
- **Diagnostic**: A pipeline-wide structured record. Every `Diagnostic` contains: `Severity` (one of `Error`, `Warning`, `Info`), `Code` (string in format `<prefix><4-digit-number>`), `Message` (human-readable string), optional `Source` (file path), and optional `Location` (line and column). The IR_Builder uses the reserved prefix `IR` (codes `IR0001`–`IR9999`).
- **Load_Result**: The output of the `Project_Loader` consumed by the IR_Builder. Contains `Projects` (ordered list of `Project_Entry` items in topological order), `DependencyGraph`, `Diagnostics`, `Success`, and `Config`. Full schema is defined in the Project_Loader specification.
- **Project_Entry**: A record within `Load_Result` representing one loaded project. Carries `ProjectPath`, `ProjectName`, `TargetFramework`, `OutputKind`, `LangVersion`, `NullableEnabled`, `Compilation`, `PackageReferences`, and `Diagnostics`. Full schema is defined in the Project_Loader specification.
- **IR_Build_Result**: The output of the IR_Builder. Contains `Units` (list of `IrCompilationUnit`, one per `Project_Entry`), `Diagnostics` (aggregated `IR`-prefixed diagnostics), and `Success` (true when no `Error`-severity diagnostics are present).
- **Mapping_Config**: The configuration object parsed from `transpiler.yaml` by the `Project_Loader` and passed into the pipeline via `Load_Result.Config`. The `linq_strategy` field (one of `lower_to_loops` or `preserve_functional`) controls how the IR_Builder handles LINQ expressions. The full schema is defined in the Project_Loader specification.
- **Frontend_Result**: The output of the Roslyn_Frontend consumed by the IR_Builder. Contains `Units` (list of `Frontend_Unit`, one per `Project_Entry`), `Diagnostics`, and `Success`. Full schema defined in the Roslyn Frontend specification.
- **Frontend_Unit**: The normalized, fully-annotated representation of one C# project. Contains `ProjectName`, `OutputKind`, `TargetFramework`, `LangVersion`, `NullableEnabled`, `PackageReferences`, and `NormalizedTrees`. Full schema defined in the Roslyn Frontend specification.
- **Normalized_SyntaxTree**: A rewritten syntax tree paired with a `SymbolTable` that pre-resolves all named symbols. The IR_Builder reads from this structure rather than calling Roslyn APIs directly.
- **SymbolTable**: A dictionary mapping every `SyntaxNode` carrying a named reference to its `ResolvedSymbol` record, populated by the Roslyn_Frontend before handoff.
- **ResolvedSymbol**: A plain-data record (no Roslyn types) containing `FullyQualifiedName`, `AssemblyName`, `Kind`, `SourcePackageId` (nullable), `SourceLocation` (nullable), and `ConstantValue` (nullable). Full schema defined in the Roslyn Frontend specification.
- **Attribute_Node**: A Declaration IR node representing a single C# attribute application. Carries `FullyQualifiedName` (string), `ShortName` (string), `PositionalArguments` (ordered list of IR expression nodes), `NamedArguments` (ordered list of `{ Name: string, Value: IR expression node }` pairs), `Target` (one of the `Attribute_Target` enum values), and `SourceLocation`. Defined fully in Requirement 1.3.
- **Attribute_Target**: The syntactic location to which an attribute is applied. One of: `Class`, `Struct`, `Interface`, `Enum`, `EnumMember`, `Method`, `Constructor`, `Property`, `Field`, `Parameter`, `ReturnValue`, `Assembly`, `Module`.
- **Synthesized_Attribute**: A C# attribute injected by the compiler into the `SemanticModel` with no corresponding syntax in any source file, identified by `AttributeData.ApplicationSyntaxReference == null`. Examples: `[CompilerGenerated]` on async state-machine types, `[IteratorStateMachine]` on iterator methods. The Roslyn_Frontend excludes these at the extraction boundary (RF Requirement 10.6); they never appear in the `Normalized_SyntaxTree` and therefore never produce an `Attribute_Node` in the IR.

---

## Requirements

### Requirement 1: IR Node Taxonomy

**User Story:** As a Dart code generator author, I want a well-defined, exhaustive set of IR node types,
so that I can write a complete, switch-exhaustive visitor without handling raw C# or Roslyn concepts.

#### Acceptance Criteria

1. THE IR_Builder SHALL represent every C# construct supported by the transpiler as exactly one IR_Node subtype.
2. THE IR SHALL organize nodes into four top-level categories: **Declarations**, **Statements**, **Expressions**, and **Types**.
3. THE IR SHALL include the following Declaration node types: `CompilationUnit`, `Namespace`, `Class`, `Struct`, `Interface`, `Enum`, `EnumMember`, `Method`, `Constructor`, `Destructor`, `Property`, `Field`, `Event`, `Delegate`, `TypeParameter`, `Parameter`, `LocalFunction`, `Attribute_Node`.
   - `Attribute_Node` carries: `FullyQualifiedName` (string), `ShortName` (string), `PositionalArguments` (ordered list of IR expression nodes), `NamedArguments` (ordered list of `{ Name: string, Value: IR expression node }` pairs), `Target` (one of `Class`, `Struct`, `Interface`, `Enum`, `EnumMember`, `Method`, `Constructor`, `Property`, `Field`, `Parameter`, `ReturnValue`, `Assembly`, `Module`), and `SourceLocation`.
   - `Attribute_Node` instances are attached as a list on every Declaration node type that can carry C# attributes: `Class`, `Struct`, `Interface`, `Enum`, `EnumMember`, `Method`, `Constructor`, `Property`, `Field`, `Event`, `Delegate`, `Parameter`; and on `CompilationUnit` for assembly-level and module-level attributes.
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

1. THE IR_Builder SHALL attach an IR_Symbol to every `Identifier`, `MemberAccessExpression`, `InvocationExpression`, `ObjectCreationExpression`, and type reference node by reading the corresponding `ResolvedSymbol` entry from the `SymbolTable` in the `Normalized_SyntaxTree`.
2. THE IR_Symbol SHALL contain: a fully-qualified name, the declaring assembly name, the kind (type, method, field, property, event, local, parameter), a nullable source location, and a nullable `SourcePackageId` string — all sourced directly from the `ResolvedSymbol` record.
3. WHEN a symbol refers to a type defined within the compilation unit, THE IR_Symbol SHALL include a reference to the corresponding Declaration IR_Node.
4. WHEN a symbol refers to a type from an external assembly, THE IR_Symbol SHALL record the assembly name and fully-qualified CLR type name from the `ResolvedSymbol` record.
4a. WHEN a `ResolvedSymbol.SourcePackageId` is non-null, THE IR_Builder SHALL copy it to `IR_Symbol.SourcePackageId` so that the Dart code generator can resolve the correct import path without re-consulting the Mapping_Registry.
5. WHEN the `SymbolTable` entry for a node has `Kind = Unresolved` (set by the Roslyn_Frontend when binding failed), THE IR_Builder SHALL emit an `UnresolvedSymbol` node with the original identifier text and source span, and SHALL continue processing remaining nodes.
6. THE IR_Builder SHALL use the specific overload recorded in the `SymbolTable` for every method reference, so that the IR contains no ambiguous method references.

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
4. THE IR_Builder SHALL lower C# `partial` classes by merging all partial declarations into a single `Class` IR_Node before emitting. During this merge, THE IR_Builder SHALL union the `Attribute_Node` lists from every partial part onto the merged `Class` IR_Node and onto each merged member IR_Node, ordered by source file path (alphabetical ascending) then by line number (ascending) within a file, preserving every attribute application without deduplication (see Attribute → Annotation Mapping Requirement 12).
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
3. WHERE `IConfigService.linqStrategy` returns `lower_to_loops`, THE IR_Builder SHALL lower LINQ chains to equivalent `ForEachStatement` and `LocalDeclaration` IR nodes.
4. WHERE `IConfigService.linqStrategy` returns `preserve_functional`, THE IR_Builder SHALL preserve LINQ method-chain `InvocationExpression` nodes for the Dart code generator to map to Dart collection methods.
5. WHEN `IConfigService.linqStrategy` returns its Default_Value (i.e., no `linq_strategy` was set in `transpiler.yaml`), THE IR_Builder SHALL apply `preserve_functional` behaviour.
6. THE IR_Builder SHALL attach the element IR_Type and result IR_Type to every LINQ `InvocationExpression` node.

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
6. THE IR_Builder SHALL represent an explicit discard of a `Task`-returning call (i.e., `_ = SomeAsync()`) as an `InvocationExpression` node with `IsFireAndForget = true`; the enclosing `AssignmentExpression` to the discard identifier SHALL NOT be emitted as a separate IR node.
7. WHEN a `Task`-returning `InvocationExpression` appears as a bare expression statement with no `await`, no assignment, and no `#pragma warning disable CS4014` suppression active at that source location, THE IR_Builder SHALL emit the `InvocationExpression` with `IsFireAndForget = false` and SHALL attach an `IR` `Warning` diagnostic identifying the unawaited call site.

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

### Requirement 10: Frontend_Result Integration Contract

**User Story:** As a pipeline integrator, I want a well-defined input and output contract for the IR_Builder,
so that the Roslyn_Frontend and the IR stage can evolve independently, and the IR_Builder has no dependency on Roslyn.

#### Acceptance Criteria

1. THE IR_Builder SHALL accept a `Frontend_Result` as its sole input and SHALL NOT call any Roslyn API; all symbol resolution, type information, and attribute data SHALL be read from the `SymbolTable`, `ResolvedSymbol` records, and structured attribute data in the `Frontend_Result`.
2. THE IR_Builder SHALL iterate `Frontend_Result.Units` in the order provided (topological, leaf-first) and produce one `IrCompilationUnit` per `Frontend_Unit`, collecting them into `IR_Build_Result.Units` in the same order.
3. FOR EACH `Frontend_Unit`, THE IR_Builder SHALL read `Frontend_Unit.OutputKind`, `Frontend_Unit.TargetFramework`, `Frontend_Unit.LangVersion`, and `Frontend_Unit.NullableEnabled` and record them as metadata on the corresponding `IrCompilationUnit` so that the Dart code generator does not need to re-inspect the Roslyn `Compilation`.
4. THE IR_Builder SHALL read `Frontend_Unit.PackageReferences` and attach the list to the `IrCompilationUnit` so that the NuGet dependency handler can map packages to Dart equivalents without accessing the `Compilation` directly. Each entry in the attached list SHALL include the `Tier` and `DartMapping` fields populated by the NuGet_Handler prior to IR_Builder invocation (per NuGet Requirement 13.4).
5. THE IR_Builder SHALL NOT invoke any Roslyn API (`SemanticModel`, `SyntaxTree`, `ISymbol`, `CSharpCompilation`, or any type from `Microsoft.CodeAnalysis.*`); all data SHALL be read from the plain-data records in `Frontend_Result`.
6. THE IR_Builder SHALL process each `Normalized_SyntaxTree` within a `Frontend_Unit` in the order provided; the Roslyn_Frontend guarantees deterministic ordering (alphabetical by file path).
7. WHEN a `Normalized_SyntaxTree` node carries an `Unsupported` or `UnknownAttribute` marker from the Roslyn_Frontend, THE IR_Builder SHALL emit the corresponding `UnsupportedNode` or `UnresolvedSymbol` placeholder and continue processing remaining nodes rather than aborting.
8. THE IR_Builder SHALL expose a single public entry point: `IR_Build_Result Build(Frontend_Result frontendResult)` (or language-equivalent), with no mutable global state.
9. THE IR_Builder SHALL complete processing of a single `Normalized_SyntaxTree` without retaining references to its nodes after that tree's IR subtree is emitted, to allow incremental memory release.

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
2. THE IR_Builder SHALL sort all collections within IR nodes (e.g., interface lists, attribute lists) in a canonical order when the source order is not semantically significant. The canonical order is: primary sort by fully-qualified name (alphabetical, lexicographic); secondary sort by source file path (alphabetical, lexicographic); tertiary sort by line number (ascending). This three-level tie-breaker applies in particular to assembly-level and module-level `Attribute_Node` lists, where the same attribute type (e.g., `[assembly: InternalsVisibleTo(...)]`) may appear in multiple source files and the FQN alone does not produce a unique ordering. See also Attribute → Annotation Mapping Requirement 2.1, which states the same rule for `Attribute_Node` lists specifically.
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
3a. THE IR_Validator SHALL verify that every `InvocationExpression` node with `IsFireAndForget = true` has a return IR_Type of `Task`, `Task<T>`, `ValueTask`, or `ValueTask<T>` (fire-and-forget only applies to Task-returning calls).
4. THE IR_Validator SHALL verify that every `Class` node that declares `IsAbstract = true` does not also declare `IsSealed = true`.
5. THE IR_Validator SHALL verify that every `TypeParameter` node referenced in a `GenericType` is declared in the enclosing generic declaration's type parameter list.
6. THE IR_Validator SHALL verify that every `CatchClause` node within a `TryCatchStatement` that has a `WhenExpression` has that expression typed as `bool`.
7. WHEN THE IR_Validator detects a violation, THE IR_Validator SHALL collect all violations and return them as a list of structured diagnostics rather than throwing on the first error.
8. THE IR_Validator SHALL complete validation of any IR tree in time proportional to the number of IR nodes in the tree.
9. THE IR_Validator SHALL verify that every `IR_Symbol` whose `AssemblyName` matches a package ID in `IrCompilationUnit.PackageReferences` carries a non-null `SourcePackageId` equal to that package ID (package symbol completeness invariant).
10. THE IR_Validator SHALL verify that every `Attribute_Node` attached to an IR node has a non-null, non-empty `FullyQualifiedName` and a `Target` value that is consistent with the type of the IR node it is attached to (e.g., `Target = Assembly` or `Target = Module` only on `CompilationUnit`; `Target = Parameter` only on `Parameter` nodes; `Target = ReturnValue` only on `Method` nodes).

---

### Requirement 15: Diagnostics and Error Reporting

**User Story:** As a transpiler user, I want clear, actionable diagnostics when C# constructs cannot
be represented in the IR, so that I know exactly what to fix or what to expect in the generated output.

#### Acceptance Criteria

1. THE IR_Builder SHALL emit a structured `Diagnostic` conforming to the pipeline-wide schema for every `UnsupportedNode` and `UnresolvedSymbol` it produces.
2. THE IR_Builder SHALL assign diagnostic codes in the range `IR0001`–`IR9999`; no other pipeline component SHALL use the `IR` prefix.
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
8. FOR ALL `Frontend_Unit` inputs containing a `partial` class whose parts collectively carry `N` total `Attribute_Node` instances across all parts (on the class itself or on any member), the merged `Class` IR_Node and its member IR_Nodes SHALL together carry exactly `N` `Attribute_Node` instances — no attribute application from any partial part SHALL be dropped (partial merge attribute count preservation property). Because the Roslyn_Frontend excludes compiler-synthesized attributes at the extraction boundary per RF Requirement 10.6, `N` counts only source-declared attributes; synthesized attributes are not present in the `Normalized_SyntaxTree` and are not counted.
