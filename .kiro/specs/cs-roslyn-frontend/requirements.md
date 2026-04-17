# Roslyn Frontend — Requirements Document

## Introduction

The Roslyn Frontend is the second stage of the cs2dart transpiler pipeline. It sits between the
Project_Loader and the IR_Builder, consuming the `Load_Result` produced by the Project_Loader and
emitting a `Frontend_Result` that the IR_Builder consumes. Its responsibilities are:

1. **Querying the Roslyn SemanticModel** — extracting fully-resolved type information, symbol
   bindings, and constant values from each `CSharpCompilation` in the `Load_Result`.
2. **Normalizing C# constructs** — rewriting syntactic sugar and multi-form constructs into a
   single canonical form so that the IR_Builder handles a minimal, well-defined vocabulary.
3. **Lowering complex language features** — transforming LINQ query syntax, async state machines,
   pattern matching, and other high-level constructs into simpler, semantically equivalent forms
   that map cleanly to IR nodes.

The Roslyn Frontend is the only pipeline stage that is permitted to call Roslyn APIs. All
downstream stages (IR_Builder, Dart_Generator, and subsystems) operate exclusively on the
`Frontend_Result` and must not hold or query Roslyn objects.

---

## Glossary

- **Roslyn_Frontend**: The component described by this specification.
- **Frontend_Result**: The output of the Roslyn_Frontend. Contains `Units` (list of
  `Frontend_Unit`, one per `Project_Entry`), `Diagnostics` (aggregated `RF`-prefixed diagnostics),
  and `Success` (true when no `Error`-severity diagnostics are present).
- **Frontend_Unit**: The normalized, fully-annotated representation of one C# project produced by
  the Roslyn_Frontend. Contains `ProjectName`, `OutputKind`, `TargetFramework`, `LangVersion`,
  `NullableEnabled`, `PackageReferences`, and `NormalizedTrees` (list of `Normalized_SyntaxTree`).
- **Normalized_SyntaxTree**: A rewritten Roslyn `SyntaxTree` paired with its `SemanticModel` and
  a `SymbolTable` that pre-resolves all named symbols referenced in the tree. The IR_Builder reads
  from this structure rather than calling Roslyn APIs directly.
- **SymbolTable**: A dictionary mapping every `SyntaxNode` in a `Normalized_SyntaxTree` that
  carries a named reference to its fully-resolved `ResolvedSymbol` record, populated by the
  Roslyn_Frontend before the `Frontend_Result` is handed off.
- **ResolvedSymbol**: A plain-data record (no Roslyn types) containing: `FullyQualifiedName`
  (string), `AssemblyName` (string), `Kind` (enum: Type, Method, Field, Property, Event, Local,
  Parameter), `SourcePackageId` (nullable string), `SourceLocation` (nullable file + line/column),
  and `ConstantValue` (nullable boxed value for `const` symbols).
- **Normalization**: The process of rewriting a `SyntaxTree` so that semantically equivalent but
  syntactically distinct C# constructs are represented in a single canonical form.
- **Lowering**: The process of transforming a high-level C# construct (e.g., a LINQ query
  expression, an async state machine, a pattern-matching switch) into a simpler, semantically
  equivalent form that the IR_Builder can map directly to IR nodes.
- **Canonical_Form**: The single syntactic representation chosen for a normalized construct (e.g.,
  LINQ query syntax is always rewritten to method-chain form).
- **SemanticModel**: The Roslyn `Microsoft.CodeAnalysis.SemanticModel` for a given `SyntaxTree`,
  providing type information, symbol resolution, and constant evaluation.
- **Diagnostic**: A pipeline-wide structured record. `Severity` (`Error`, `Warning`, `Info`),
  `Code` (string `RF0001`–`RF9999`), `Message` (string), optional `Source` (file path), optional
  `Location` (`{ Line, Column }`). Full schema defined in the top-level transpiler specification.
- **Load_Result**: The output of the `Project_Loader` consumed by the Roslyn_Frontend. Full schema
  defined in the Project_Loader specification.
- **IConfigService**: The configuration interface consumed by the Roslyn_Frontend. Full schema
  defined in the Transpiler Configuration specification.

---

## Requirements

### Requirement 1: Pipeline Integration Contract

**User Story:** As a pipeline integrator, I want a well-defined input and output contract for the
Roslyn_Frontend, so that the Project_Loader, Roslyn_Frontend, and IR_Builder can evolve
independently without coupling to Roslyn types.

#### Acceptance Criteria

1. THE Roslyn_Frontend SHALL accept a `Load_Result` as its sole input; it SHALL NOT accept raw
   `SyntaxTree`, `SemanticModel`, or `CSharpCompilation` objects as separate top-level arguments.
2. THE Roslyn_Frontend SHALL iterate `Load_Result.Projects` in the order provided (topological,
   leaf-first) and produce one `Frontend_Unit` per `Project_Entry`, collecting them into
   `Frontend_Result.Units` in the same order.
3. THE Roslyn_Frontend SHALL expose a single public entry point:
   `Frontend_Result Process(Load_Result loadResult)` (or language-equivalent), with no mutable
   global state.
4. THE Roslyn_Frontend SHALL set `Frontend_Result.Success = true` if and only if
   `Frontend_Result.Diagnostics` contains no entry with `Severity = Error`.
5. THE Roslyn_Frontend SHALL propagate all `PL`-prefixed diagnostics from `Load_Result.Diagnostics`
   into `Frontend_Result.Diagnostics` unchanged, so that the IR_Builder receives a single
   authoritative diagnostic list covering both loading and frontend processing.
6. THE IR_Builder SHALL accept a `Frontend_Result` as its sole input and SHALL NOT call any Roslyn
   API; all symbol resolution and type information SHALL be read from the `SymbolTable` and
   `ResolvedSymbol` records in the `Frontend_Result`.
7. WHEN `Load_Result.Success` is `false`, THE Roslyn_Frontend SHALL still attempt processing for
   all `Project_Entry` items that have no `Error`-severity diagnostics, emitting an `RF`-prefixed
   `Warning` for each unit skipped due to upstream errors.

---

### Requirement 2: SemanticModel Querying and Symbol Pre-Resolution

**User Story:** As an IR_Builder author, I want all Roslyn symbol lookups performed and cached
before the IR_Builder runs, so that the IR_Builder never calls Roslyn APIs and can be tested
without a Roslyn dependency.

#### Acceptance Criteria

1. FOR EACH `SyntaxTree` in a `Project_Entry.Compilation`, THE Roslyn_Frontend SHALL obtain the
   corresponding `SemanticModel` via `Compilation.GetSemanticModel(tree)` and query it to resolve
   every named reference in the tree.
2. THE Roslyn_Frontend SHALL populate a `SymbolTable` for each `Normalized_SyntaxTree` mapping
   every `SyntaxNode` that carries a named reference (identifiers, member accesses, invocations,
   object creations, type references) to its `ResolvedSymbol` record.
3. WHEN Roslyn resolves a symbol to a type defined within the same compilation, THE
   `ResolvedSymbol.SourcePackageId` SHALL be null and `ResolvedSymbol.AssemblyName` SHALL be the
   project's own assembly name.
4. WHEN Roslyn resolves a symbol to a type from an external assembly whose name matches a package
   in `Load_Result.PackageReferences`, THE Roslyn_Frontend SHALL set
   `ResolvedSymbol.SourcePackageId` to that package's ID.
5. WHEN Roslyn cannot resolve a symbol (binding error), THE Roslyn_Frontend SHALL record a sentinel
   `ResolvedSymbol` with `Kind = Unresolved` and the original identifier text, and SHALL emit an
   `RF`-prefixed `Warning` diagnostic; it SHALL NOT abort processing of the containing tree.
6. THE Roslyn_Frontend SHALL resolve all overloaded method references to the specific overload
   selected by Roslyn and record the resolved overload in the `SymbolTable`.
7. FOR ALL `const` symbols, THE Roslyn_Frontend SHALL evaluate and store the compile-time constant
   value in `ResolvedSymbol.ConstantValue` using Roslyn's `SemanticModel.GetConstantValue`.
8. THE Roslyn_Frontend SHALL complete all `SemanticModel` queries for a `SyntaxTree` before
   releasing the reference to that tree's `SemanticModel`, to allow incremental memory release.

---

### Requirement 3: Syntax Tree Normalization

**User Story:** As an IR_Builder author, I want every C# construct presented in a single canonical
syntactic form, so that the IR_Builder handles a minimal vocabulary without branching on equivalent
syntactic variants.

#### Acceptance Criteria

1. THE Roslyn_Frontend SHALL rewrite all LINQ query syntax expressions (e.g.,
   `from x in xs where ... select ...`) to equivalent LINQ method-chain form
   (`xs.Where(...).Select(...)`) before emitting the `Normalized_SyntaxTree`.
2. THE Roslyn_Frontend SHALL rewrite all C# `partial` class declarations by merging all partial
   parts of the same type into a single unified `ClassDeclarationSyntax` node in the
   `Normalized_SyntaxTree`.
3. THE Roslyn_Frontend SHALL rewrite primary constructor declarations (C# 12) to an explicit
   constructor body with corresponding parameter assignments to synthesized backing fields.
4. THE Roslyn_Frontend SHALL rewrite record type declarations to explicit class or struct
   declarations with synthesized equality members (`Equals`, `GetHashCode`, `==`, `!=`),
   `ToString`, and `Deconstruct` methods as explicit method nodes.
5. THE Roslyn_Frontend SHALL rewrite auto-property declarations (e.g., `public int X { get; set; }`)
   to explicit property declarations with a backing field, a getter body returning the field, and a
   setter body assigning the field.
6. THE Roslyn_Frontend SHALL rewrite `using` statements and `using` declarations to explicit
   `try`/`finally` blocks that call `Dispose()` on the resource in the `finally` clause.
7. THE Roslyn_Frontend SHALL rewrite `lock` statements to explicit `Monitor.Enter` /
   `Monitor.Exit` calls wrapped in a `try`/`finally` block.
8. THE Roslyn_Frontend SHALL rewrite `checked` and `unchecked` expression blocks by annotating
   each contained arithmetic operation with a synthetic `OverflowCheck` trivia marker rather than
   emitting wrapper nodes.
9. THE Roslyn_Frontend SHALL rewrite `foreach` loops to an explicit iterator form carrying the
   resolved element type annotation, so that the IR_Builder can emit a typed `ForEachStatement`
   without querying the `SemanticModel`.
10. THE Roslyn_Frontend SHALL rewrite indexer declarations to explicit `get_Item` / `set_Item`
    method declarations with an `IsIndexer` annotation.
11. THE Roslyn_Frontend SHALL rewrite explicit interface implementations to regular method
    declarations annotated with the implementing interface's `ResolvedSymbol`.
12. THE Roslyn_Frontend SHALL rewrite extension method declarations to regular static method
    declarations annotated with an `IsExtension` marker and the extended type's `ResolvedSymbol`.
13. WHEN a normalization rewrite cannot be applied due to an unsupported construct, THE
    Roslyn_Frontend SHALL leave the original node in place, annotate it with an `Unsupported`
    marker carrying a human-readable description, and emit an `RF`-prefixed `Warning` diagnostic.

---

### Requirement 4: Async State Machine Normalization

**User Story:** As an IR_Builder author, I want async methods and iterator methods presented in a
normalized form that makes their async/iterator nature explicit, so that I can emit correct Dart
`async`/`async*` methods without analyzing state machine patterns.

#### Acceptance Criteria

1. THE Roslyn_Frontend SHALL annotate every `MethodDeclarationSyntax` and
   `LocalFunctionStatementSyntax` node that carries the `async` modifier with an `IsAsync = true`
   marker in the `Normalized_SyntaxTree`.
2. THE Roslyn_Frontend SHALL annotate every method whose return type is `IEnumerable<T>`,
   `IAsyncEnumerable<T>`, or `IEnumerator<T>` and whose body contains `yield` statements with an
   `IsIterator = true` marker.
3. THE Roslyn_Frontend SHALL rewrite every `ConfigureAwait(false)` call expression to a plain
   `await` expression annotated with a `ConfigureAwait = false` marker, so that the IR_Builder
   does not need to pattern-match on the `ConfigureAwait` invocation.
4. THE Roslyn_Frontend SHALL preserve `await` expressions as-is in the `Normalized_SyntaxTree`;
   it SHALL NOT lower async state machines to explicit state machine classes.
5. THE Roslyn_Frontend SHALL annotate the return type of every `async` method with the resolved
   `Task`, `Task<T>`, `ValueTask`, or `ValueTask<T>` `ResolvedSymbol` so that the IR_Builder can
   emit the correct Dart `Future<T>` return type without re-querying the `SemanticModel`.
6. WHEN an `async` method's return type is `void` (fire-and-forget), THE Roslyn_Frontend SHALL
   annotate it with an `IsFireAndForget = true` marker and emit an `RF`-prefixed `Info` diagnostic.

---

### Requirement 5: Pattern Matching Normalization

**User Story:** As an IR_Builder author, I want C# pattern matching constructs normalized to a
structured form, so that I can emit correct Dart switch expressions and pattern-matching cases
without parsing raw C# pattern syntax.

#### Acceptance Criteria

1. THE Roslyn_Frontend SHALL rewrite C# 8+ switch expressions to a canonical `SwitchExpression`
   form where each arm carries: a `Pattern` node (typed, property, positional, or constant), an
   optional `WhenClause` expression, and a result expression.
2. THE Roslyn_Frontend SHALL rewrite `switch` statements with pattern-matching cases to a canonical
   form where each `case` carries a structured `Pattern` node rather than a raw expression.
3. THE Roslyn_Frontend SHALL normalize type patterns (`case Foo f:`) to a `TypePattern` node
   carrying the resolved `ResolvedSymbol` for `Foo` and the declared variable name.
4. THE Roslyn_Frontend SHALL normalize property patterns (`case { X: 1, Y: 2 }:`) to a
   `PropertyPattern` node carrying a list of `(PropertySymbol, SubPattern)` pairs.
5. THE Roslyn_Frontend SHALL normalize positional patterns (`case (int x, string y):`) to a
   `PositionalPattern` node carrying a list of `(Position, SubPattern)` pairs with resolved
   `Deconstruct` method symbol.
6. THE Roslyn_Frontend SHALL normalize `is` type-test expressions (e.g., `x is Foo f`) to an
   `IsExpression` node carrying the tested type's `ResolvedSymbol` and the optional binding
   variable name.
7. WHEN a pattern construct is not in the supported set, THE Roslyn_Frontend SHALL substitute an
   `UnsupportedPattern` node carrying the original source span and emit an `RF`-prefixed `Warning`.

---

### Requirement 6: LINQ Normalization

**User Story:** As an IR_Builder author, I want all LINQ expressions presented in method-chain form
with fully-resolved type annotations, so that I can emit idiomatic Dart collection operations
without understanding LINQ query syntax.

#### Acceptance Criteria

1. THE Roslyn_Frontend SHALL rewrite all LINQ query syntax expressions to equivalent LINQ
   method-chain form before emitting the `Normalized_SyntaxTree` (this is the canonical form
   defined in Requirement 3.1).
2. FOR EACH LINQ method-chain call (`Where`, `Select`, `OrderBy`, `GroupBy`, `Join`, `Aggregate`,
   `First`, `FirstOrDefault`, `Any`, `All`, `Count`, `Sum`, `Min`, `Max`, `Average`, `Distinct`,
   `Take`, `Skip`, `ToList`, `ToArray`, `ToDictionary`), THE Roslyn_Frontend SHALL annotate the
   call node with: the resolved `System.Linq.Enumerable` or `System.Linq.Queryable` `ResolvedSymbol`,
   the element IR_Type of the input sequence, and the result IR_Type of the call.
3. THE Roslyn_Frontend SHALL annotate every LINQ lambda argument with the resolved parameter type
   and return type so that the IR_Builder can emit typed Dart lambda expressions.
4. WHEN `IConfigService.linqStrategy` returns `lower_to_loops`, THE Roslyn_Frontend SHALL rewrite
   LINQ method chains to equivalent `foreach` / local variable forms in the `Normalized_SyntaxTree`
   before handing off to the IR_Builder.
5. WHEN `IConfigService.linqStrategy` returns `preserve_functional` (the default), THE
   Roslyn_Frontend SHALL preserve LINQ method-chain calls in the `Normalized_SyntaxTree` with the
   type annotations from criterion 2.
6. THE Roslyn_Frontend SHALL annotate `let` clauses in query syntax (before rewriting) with the
   resolved type of the introduced range variable, so that the rewritten method-chain form carries
   correct type information.

---

### Requirement 7: Type Annotation Enrichment

**User Story:** As an IR_Builder author, I want every expression, declaration, and local variable
in the normalized tree to carry an explicit, fully-resolved type annotation, so that I can emit
correct Dart type annotations without calling Roslyn APIs.

#### Acceptance Criteria

1. THE Roslyn_Frontend SHALL annotate every expression node in the `Normalized_SyntaxTree` with
   its resolved `IR_Type` equivalent, obtained from `SemanticModel.GetTypeInfo(node).Type`.
2. THE Roslyn_Frontend SHALL annotate every `var`-typed local variable declaration with the
   inferred concrete type, replacing the `var` keyword with the explicit type in the
   `Normalized_SyntaxTree`.
3. THE Roslyn_Frontend SHALL annotate every lambda expression with its resolved `FunctionType`,
   including parameter types and return type.
4. THE Roslyn_Frontend SHALL annotate every `dynamic`-typed expression with a `DynamicType` marker
   and emit an `RF`-prefixed `Warning` diagnostic.
5. THE Roslyn_Frontend SHALL annotate every nullable reference type expression (e.g., `string?`)
   with a `NullableType` wrapper when `Project_Entry.NullableEnabled` is `true`.
6. THE Roslyn_Frontend SHALL annotate every value-type nullable expression (e.g., `int?`) with a
   `NullableType` wrapper regardless of the `NullableEnabled` setting.
7. THE Roslyn_Frontend SHALL annotate every `const` expression with its compile-time constant value
   obtained from `SemanticModel.GetConstantValue(node)`.
8. WHEN `SemanticModel.GetTypeInfo` returns a null or error type for a node, THE Roslyn_Frontend
   SHALL annotate the node with an `UnresolvedType` marker and emit an `RF`-prefixed `Warning`.

---

### Requirement 8: Declaration Metadata Extraction

**User Story:** As an IR_Builder author, I want all declaration modifiers, accessibility levels,
and inheritance relationships extracted and attached to declaration nodes, so that I can emit
correct Dart declarations without re-parsing C# modifier keywords.

#### Acceptance Criteria

1. THE Roslyn_Frontend SHALL annotate every type and member declaration node with its resolved
   `Accessibility` (Public, Internal, Protected, ProtectedInternal, PrivateProtected, Private).
2. THE Roslyn_Frontend SHALL annotate every declaration node with boolean flags for each applicable
   modifier: `IsStatic`, `IsAbstract`, `IsVirtual`, `IsOverride`, `IsSealed`, `IsReadonly`,
   `IsConst`, `IsExtern`, `IsNew`.
3. THE Roslyn_Frontend SHALL annotate every `Class` declaration with its resolved base class
   `ResolvedSymbol` (nullable) and the list of implemented interface `ResolvedSymbol` entries.
4. THE Roslyn_Frontend SHALL annotate every generic declaration (`Class`, `Struct`, `Interface`,
   `Method`, `Delegate`) with its list of `TypeParameter` nodes, each carrying its name, variance,
   and resolved constraint `ResolvedSymbol` entries.
5. THE Roslyn_Frontend SHALL annotate every `Method` declaration with `IsOperator`,
   `IsConversion`, `IsImplicit`, `IsExplicit`, `IsExtension`, and `IsIndexer` flags derived from
   the Roslyn symbol.
6. THE Roslyn_Frontend SHALL annotate every `Event` declaration with `IsStatic`, `IsAbstract`,
   `IsVirtual`, `IsOverride`, and `ExplicitInterface` (nullable `ResolvedSymbol`) fields.
7. THE Roslyn_Frontend SHALL annotate every `Parameter` node with its resolved type, default value
   (if any), and `IsParams`, `IsRef`, `IsOut`, `IsIn` flags.
8. WHEN a declaration carries an attribute that is in the supported attribute set (see Requirement
   10), THE Roslyn_Frontend SHALL attach the resolved attribute data to the declaration node.

---

### Requirement 9: Unsupported Construct Handling

**User Story:** As a transpiler user, I want unsupported C# constructs to be clearly marked rather
than silently dropped, so that I can identify exactly what the transpiler cannot handle.

#### Acceptance Criteria

1. WHEN the Roslyn_Frontend encounters a C# construct that cannot be normalized or lowered (e.g.,
   `unsafe` blocks, `fixed` statements, `stackalloc`, `__arglist`, `__makeref`), it SHALL annotate
   the node with an `Unsupported` marker carrying a human-readable description and the original
   source span.
2. THE Roslyn_Frontend SHALL emit an `RF`-prefixed `Warning` diagnostic for every `Unsupported`
   marker it attaches, identifying the construct type and source location.
3. THE Roslyn_Frontend SHALL NOT emit an `Error`-severity diagnostic for unsupported constructs
   unless the construct is in a position where its absence would make the containing declaration
   semantically incomplete (e.g., an unsupported return type).
4. THE Roslyn_Frontend SHALL continue processing all remaining nodes in the tree after marking an
   unsupported construct; it SHALL NOT abort the tree.
5. WHEN `goto` or labeled statements are encountered, THE Roslyn_Frontend SHALL annotate them with
   an `Unsupported` marker and emit an `RF`-prefixed `Warning` noting that `goto` has no Dart
   equivalent.
6. WHEN `unsafe` blocks are encountered, THE Roslyn_Frontend SHALL annotate the entire block with
   an `Unsupported` marker and emit an `RF`-prefixed `Error` diagnostic, since unsafe code cannot
   be approximated in Dart.

---

### Requirement 10: Attribute Extraction

**User Story:** As an IR_Builder author, I want supported C# attributes extracted and attached to
declaration nodes as structured data, so that the Dart code generator can emit Dart annotations
without parsing attribute syntax.

#### Acceptance Criteria

1. THE Roslyn_Frontend SHALL extract and attach the following attributes as structured data on
   declaration nodes: `[Obsolete]`, `[Serializable]`, `[Flags]` (on enums), `[DllImport]`,
   `[StructLayout]`, `[MethodImpl]`, `[CallerMemberName]`, `[CallerFilePath]`,
   `[CallerLineNumber]`, `[NotNull]`, `[MaybeNull]`, `[AllowNull]`, `[DisallowNull]`.
2. FOR EACH extracted attribute, THE Roslyn_Frontend SHALL record: the attribute's fully-qualified
   type name, the resolved `ResolvedSymbol` for the attribute class, and all constructor and named
   arguments with their resolved values.
3. WHEN an attribute's constructor argument is a `typeof(T)` expression, THE Roslyn_Frontend SHALL
   resolve `T` to its `ResolvedSymbol` and store it rather than the raw syntax.
4. WHEN an attribute is not in the supported set, THE Roslyn_Frontend SHALL attach it as an
   `UnknownAttribute` record carrying the attribute's fully-qualified name and raw argument text,
   and SHALL emit an `RF`-prefixed `Info` diagnostic.
5. THE Roslyn_Frontend SHALL NOT discard any attribute silently; every attribute on every
   declaration SHALL appear in the `Normalized_SyntaxTree` either as a structured record or as an
   `UnknownAttribute`.

---

### Requirement 11: Determinism

**User Story:** As a CI/CD pipeline operator, I want the Roslyn_Frontend to produce identical
output for identical input on every run, so that build caches and golden-file tests remain stable.

#### Acceptance Criteria

1. THE Roslyn_Frontend SHALL produce an identical `Frontend_Result` for identical `Load_Result`
   input regardless of execution environment, OS, thread scheduling, or process ID.
2. THE Roslyn_Frontend SHALL process `SyntaxTree` objects within a `Project_Entry.Compilation` in
   deterministic order (alphabetical by file path).
3. THE Roslyn_Frontend SHALL sort all collections in `SymbolTable` entries and annotation lists in
   a canonical order (alphabetical by fully-qualified name) when source order is not semantically
   significant.
4. THE Roslyn_Frontend SHALL NOT embed timestamps, process IDs, random values, or other
   environment-dependent data in any `Frontend_Result` field.
5. FOR ALL valid `Load_Result` inputs, running THE Roslyn_Frontend twice SHALL produce
   `Frontend_Result` values that are structurally and value-equal.

---

### Requirement 12: Diagnostics and Error Reporting

**User Story:** As a transpiler user, I want clear, actionable diagnostics when C# constructs
cannot be normalized or resolved, so that I know exactly what to fix or what to expect downstream.

#### Acceptance Criteria

1. THE Roslyn_Frontend SHALL emit a structured `Diagnostic` conforming to the pipeline-wide schema
   for every normalization failure, unresolved symbol, and unsupported construct it encounters.
2. THE Roslyn_Frontend SHALL assign diagnostic codes in the range `RF0001`–`RF9999`; no other
   pipeline component SHALL use the `RF` prefix.
3. THE Roslyn_Frontend SHALL NOT emit duplicate diagnostics for the same source location and
   diagnostic code within a single run.
4. THE Roslyn_Frontend SHALL aggregate all diagnostics into `Frontend_Result.Diagnostics` rather
   than writing to standard output or throwing exceptions.
5. WHEN all diagnostics have severity `Warning` or `Info`, THE Roslyn_Frontend SHALL return a
   complete `Frontend_Result` with all trees normalized.
6. WHEN any diagnostic has severity `Error`, THE Roslyn_Frontend SHALL still return the most
   complete `Frontend_Result` possible (with `Unsupported` markers in place of failed nodes) and
   set `Frontend_Result.Success = false`.
7. THE Roslyn_Frontend SHALL propagate Roslyn `CS`-prefixed compiler diagnostics from each
   `Project_Entry.Compilation` into `Frontend_Result.Diagnostics` unchanged, preserving their
   original codes.

---

### Requirement 13: Configuration Service Integration

**User Story:** As a pipeline integrator, I want the Roslyn_Frontend to receive all configuration
values through `IConfigService`, so that LINQ strategy and other behavioral settings are applied
consistently without the frontend performing its own file I/O.

#### Acceptance Criteria

1. THE Roslyn_Frontend SHALL accept an `IConfigService` instance at construction time and SHALL use
   it as the sole source of all configuration values.
2. THE Roslyn_Frontend SHALL NOT read or parse `transpiler.yaml` directly; all configuration
   access SHALL go through `IConfigService`.
3. WHEN `IConfigService.linqStrategy` returns `lower_to_loops`, THE Roslyn_Frontend SHALL apply
   the loop-lowering rewrite defined in Requirement 6.4.
4. WHEN `IConfigService.linqStrategy` returns `preserve_functional` (the default), THE
   Roslyn_Frontend SHALL preserve LINQ method chains as defined in Requirement 6.5.
5. WHEN `IConfigService.experimentalFeatures` contains a key `roslyn_frontend.<feature>` set to
   `true`, THE Roslyn_Frontend SHALL enable the corresponding experimental normalization pass.
6. WHEN all `IConfigService` accessors return their Default_Values, THE Roslyn_Frontend SHALL
   apply all default normalization rules without error.

---

### Requirement 14: Memory and Performance Contract

**User Story:** As a transpiler operator processing large codebases, I want the Roslyn_Frontend to
release Roslyn objects promptly after processing each file, so that memory usage scales with the
size of one file rather than the entire solution.

#### Acceptance Criteria

1. THE Roslyn_Frontend SHALL release its reference to a `SemanticModel` after completing all
   queries and annotations for the corresponding `SyntaxTree`; it SHALL NOT retain `SemanticModel`
   references in the `Frontend_Result`.
2. THE Roslyn_Frontend SHALL release its reference to a `CSharpCompilation` after all
   `SyntaxTree` objects within it have been processed and their `Normalized_SyntaxTree` entries
   emitted into the `Frontend_Unit`.
3. THE `Frontend_Result` SHALL contain no Roslyn types (`SyntaxNode`, `SemanticModel`,
   `ISymbol`, `ITypeSymbol`, `CSharpCompilation`, or any type from
   `Microsoft.CodeAnalysis.*`); all data SHALL be expressed as plain-data records.
4. THE Roslyn_Frontend SHALL process one `SyntaxTree` at a time per project; it SHALL NOT load all
   trees into memory simultaneously unless required by a cross-file normalization pass (e.g.,
   `partial` class merging).
5. FOR the `partial` class merging pass, THE Roslyn_Frontend SHALL load only the trees that
   contribute to the same partial type simultaneously, releasing them after the merged declaration
   is produced.

---

### Requirement 15: Correctness Properties for Testing

**User Story:** As a transpiler test engineer, I want well-defined correctness properties for the
Roslyn_Frontend, so that I can write property-based tests that catch regressions across a wide
range of C# inputs.

#### Acceptance Criteria

1. FOR ALL valid `Load_Result` inputs, running THE Roslyn_Frontend twice SHALL produce
   `Frontend_Result` values that are structurally and value-equal (determinism property).
2. FOR ALL `Normalized_SyntaxTree` outputs, every expression node SHALL carry a non-null type
   annotation (type completeness property).
3. FOR ALL `Normalized_SyntaxTree` outputs, every named reference node SHALL have a corresponding
   entry in the `SymbolTable` (symbol completeness property).
4. FOR ALL LINQ query syntax inputs, the `Normalized_SyntaxTree` SHALL contain no
   `QueryExpressionSyntax` nodes — all query syntax SHALL have been rewritten to method-chain form
   (LINQ normalization property).
5. FOR ALL `partial` class inputs, the `Normalized_SyntaxTree` SHALL contain exactly one
   declaration node per logical type, regardless of how many partial parts existed in the source
   (partial merging property).
6. FOR ALL `var`-typed local variable declarations, the `Normalized_SyntaxTree` SHALL contain an
   explicit type annotation rather than `var` (var elimination property).
7. FOR ALL `Frontend_Result` values, the `Frontend_Result` SHALL contain no fields of any Roslyn
   type (Roslyn isolation property).
8. FOR ALL `async` method declarations in the input, the corresponding node in the
   `Normalized_SyntaxTree` SHALL carry an `IsAsync = true` annotation (async annotation
   completeness property).
