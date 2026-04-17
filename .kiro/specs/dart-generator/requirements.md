# Dart Code Generator — Requirements Document

## Introduction

The Dart Code Generator is the final code-producing stage of the cs2dart transpiler pipeline. It
accepts an `IR_Build_Result` from the IR_Builder and emits a complete, idiomatic Dart package for
each `IrCompilationUnit`. The generator must produce Dart code that is type-correct, passes
`dart analyze` with zero errors, and is formatted according to Dart style conventions. It reads
behavioral configuration from the `Mapping_Config` carried in the `IR_Build_Result` and must never
re-inspect Roslyn objects or C# source.

---

## Glossary

- **Dart_Generator**: The component described by this specification; consumes `IR_Build_Result` and emits `Gen_Result`.
- **IR_Build_Result**: The output of the IR_Builder. Contains `Units` (list of `IrCompilationUnit`), `Diagnostics`, `Success`, and `Config` (`Mapping_Config`). Full schema defined in the IR_Builder specification.
- **IrCompilationUnit**: One entry in `IR_Build_Result.Units`, representing one C# project. Carries the IR node tree, `OutputKind`, `TargetFramework`, `LangVersion`, `NullableEnabled`, `PackageReferences`, and `ProjectName`.
- **Gen_Result**: The output of the `Dart_Generator`. Contains `Packages` (list of `Dart_Package`), `Diagnostics` (aggregated `CG`-prefixed diagnostics), and `Success` (true when no `Error`-severity diagnostics are present).
- **Dart_Package**: The generated output for one `IrCompilationUnit`. Contains `ProjectName`, `OutputPath` (root directory), `Files` (list of `Gen_File`), and `PubspecYaml` (the generated `pubspec.yaml` content).
- **Gen_File**: A single generated Dart source file. Contains `RelativePath` (relative to the package `lib/` directory), `Content` (Dart source text), and `SourceIrNodes` (list of IR node references that contributed to this file, for diagnostics).
- **Dart_Visitor**: The internal IR tree walker that drives code emission; implements a switch-exhaustive visitor over all IR node types.
- **Type_Mapper**: The sub-component that translates IR_Types to Dart type annotations.
- **Package_Mapper**: The sub-component that translates `PackageReferences` to Dart pub dependencies using `Mapping_Config.package_mappings`.
- **Diagnostic**: A pipeline-wide structured record. `Severity` (`Error`, `Warning`, `Info`), `Code` (string `CG0001`–`CG9999`), `Message` (string), optional `Source` (generated file path), optional `Location` (`{ Line, Column }`). Full schema defined in the top-level transpiler specification.
- **Mapping_Config**: Configuration object from `IR_Build_Result.Config`. Relevant fields for this stage: `package_mappings`, `naming_conventions`, `nullability`, `async_behavior`, `experimental`. Full schema defined in the Project_Loader specification.
- **Naming_Convention**: The set of casing rules applied to identifiers during emission, sourced from `Mapping_Config.naming_conventions`.

---

## Requirements

### Requirement 1: Integration Contract with IR_Builder

**User Story:** As a pipeline integrator, I want a well-defined input and output contract for the
Dart_Generator, so that the IR stage and the code generation stage can evolve independently.

#### Acceptance Criteria

1. THE `Dart_Generator` SHALL accept an `IR_Build_Result` as its sole input and SHALL read `IR_Build_Result.Config` to obtain the `Mapping_Config`; it SHALL NOT accept raw IR nodes, `Compilation` objects, or Roslyn types as arguments.
2. THE `Dart_Generator` SHALL iterate `IR_Build_Result.Units` in the order provided and produce one `Dart_Package` per `IrCompilationUnit`, collecting them into `Gen_Result.Packages` in the same order.
3. THE `Dart_Generator` SHALL expose a single public entry point: `Gen_Result Generate(IR_Build_Result irResult)` (or language-equivalent), with no mutable global state.
4. WHEN `IR_Build_Result.Success` is `false`, THE `Dart_Generator` SHALL still attempt generation for all units that have no `Error`-severity diagnostics, emitting a `CG`-prefixed `Warning` for each unit skipped due to upstream errors.
5. THE `Dart_Generator` SHALL set `Gen_Result.Success = true` if and only if `Gen_Result.Diagnostics` contains no entry with `Severity = Error`.

---

### Requirement 2: Dart Package Structure

**User Story:** As a developer consuming the transpiler output, I want each generated Dart package
to follow the standard Dart package layout, so that it integrates immediately with `pub`, Flutter,
and Dart tooling without manual restructuring.

#### Acceptance Criteria

1. FOR EACH `IrCompilationUnit`, THE `Dart_Generator` SHALL produce a `Dart_Package` with the following directory structure: `pubspec.yaml` at the package root, all library source files under `lib/src/`, a barrel export file at `lib/<package_name>.dart`, and generated test stubs under `test/` when the source project contains test classes.
2. THE `Dart_Generator` SHALL derive the Dart package name from `IrCompilationUnit.ProjectName` by converting it to `snake_case` and stripping any `.` separators.
3. WHEN `IrCompilationUnit.OutputKind` is `Exe`, THE `Dart_Generator` SHALL additionally emit a `bin/<package_name>.dart` entry-point file containing a `main()` function that delegates to the transpiled entry-point class.
4. THE `Dart_Generator` SHALL map each C# source file to exactly one Dart source file under `lib/src/`, preserving the relative directory structure of the original project.
5. THE `Dart_Generator` SHALL emit a `pubspec.yaml` containing: `name`, `version` (defaulting to `0.1.0`), `environment.sdk` (derived from `IrCompilationUnit.TargetFramework` via a TFM-to-Dart-SDK version table), and `dependencies` populated by the `Package_Mapper`.

---

### Requirement 3: Type Mapping

**User Story:** As a Dart developer reviewing generated code, I want C# types translated to their
idiomatic Dart equivalents, so that the generated code uses native Dart types rather than C#-shaped
wrappers.

#### Acceptance Criteria

1. THE `Type_Mapper` SHALL translate IR `PrimitiveType` nodes to Dart built-in types according to the following table:

   | C# type   | Dart type  |
   |-----------|------------|
   | `int`     | `int`      |
   | `long`    | `int`      |
   | `short`   | `int`      |
   | `byte`    | `int`      |
   | `uint`, `ulong`, `ushort`, `sbyte` | `int` |
   | `float`   | `double`   |
   | `double`  | `double`   |
   | `decimal` | `double` (with `CG` `Warning` diagnostic) |
   | `bool`    | `bool`     |
   | `char`    | `String`   |
   | `string`  | `String`   |
   | `object`  | `Object`   |
   | `void`    | `void`     |

2. THE `Type_Mapper` SHALL translate IR `NullableType` nodes to Dart nullable type annotations (e.g., `String?`, `int?`) when `IrCompilationUnit.NullableEnabled` is `true`.
3. WHEN `IrCompilationUnit.NullableEnabled` is `false`, THE `Type_Mapper` SHALL emit all reference types as non-nullable and attach a `CG` `Info` diagnostic noting that nullable analysis was disabled for the source project.
4. THE `Type_Mapper` SHALL translate IR `GenericType` nodes to Dart generic types, mapping `List<T>` → `List<T>`, `Dictionary<K,V>` → `Map<K,V>`, `HashSet<T>` → `Set<T>`, `IEnumerable<T>` → `Iterable<T>`, `Task<T>` → `Future<T>`, and `IAsyncEnumerable<T>` → `Stream<T>`.
5. THE `Type_Mapper` SHALL translate IR `ArrayType` nodes to Dart `List<T>` types.
6. THE `Type_Mapper` SHALL translate IR `TupleType` nodes to Dart record types (e.g., `(int x, String y)`), preserving element names when present.
7. THE `Type_Mapper` SHALL translate IR `FunctionType` nodes to Dart `Function` typedef signatures.
8. WHEN the `Type_Mapper` encounters a `DynamicType` IR node, it SHALL emit `dynamic` and propagate the existing `IR`-prefixed warning diagnostic into `Gen_Result.Diagnostics`.
9. WHEN the `Type_Mapper` encounters a `NamedType` that has no known Dart equivalent and no entry in `Mapping_Config.package_mappings`, it SHALL emit the fully-qualified C# type name as a Dart identifier and attach a `CG` `Warning` diagnostic identifying the unmapped type.

---

### Requirement 4: Declaration Emission

**User Story:** As a Dart developer reviewing generated code, I want C# declarations emitted as
idiomatic Dart declarations, so that the generated code reads naturally and passes static analysis.

#### Acceptance Criteria

1. THE `Dart_Generator` SHALL emit IR `Class` nodes as Dart `class` declarations, preserving the class name after applying `Naming_Convention` casing rules.
2. THE `Dart_Generator` SHALL emit IR `Struct` nodes as Dart `final class` declarations with value-equality semantics implemented via `operator ==` and `hashCode` overrides.
3. THE `Dart_Generator` SHALL emit IR `Interface` nodes as Dart `abstract interface class` declarations.
4. THE `Dart_Generator` SHALL emit IR `Enum` nodes as Dart `enum` declarations, mapping each `EnumMember` to a Dart enum value and preserving explicit integer values via a `final int value` field and constructor.
5. THE `Dart_Generator` SHALL emit IR `Method` nodes as Dart methods, applying `Naming_Convention` casing to the method name and emitting `async` / `async*` modifiers when `IsAsync = true` or `IsIterator = true`.
6. THE `Dart_Generator` SHALL emit IR `Property` nodes as Dart `get` / `set` accessor pairs; auto-property backing fields SHALL be emitted as private Dart fields.
7. THE `Dart_Generator` SHALL emit IR `Field` nodes as Dart fields, using `final` for `readonly` or `const` fields and `static` for static fields.
8. THE `Dart_Generator` SHALL emit IR `Constructor` nodes as Dart constructors; static constructors (`IsStatic = true`) SHALL be emitted as Dart factory constructors named `_staticInit` with a `CG` `Warning` diagnostic noting the semantic difference.
9. THE `Dart_Generator` SHALL emit IR `Delegate` nodes as Dart `typedef` declarations with the corresponding `FunctionType` signature.
10. THE `Dart_Generator` SHALL emit IR `TypeParameter` nodes as Dart generic type parameters, mapping `ReferenceTypeConstraint` and `ValueTypeConstraint` to `Object` bounds and `BaseTypeConstraint` to the corresponding Dart type bound.
11. WHEN an IR `Method` node has `IsExtension = true`, THE `Dart_Generator` SHALL emit it as a method inside a Dart `extension` on the `ExtendedType`.
12. WHEN an IR `Method` node has `IsOperator = true`, THE `Dart_Generator` SHALL emit it as a Dart `operator` override where the `OperatorKind` has a Dart equivalent, and SHALL emit a regular named method with a `CG` `Warning` diagnostic for operator kinds with no Dart equivalent.

---

### Requirement 5: Statement Emission

**User Story:** As a Dart developer reviewing generated code, I want C# statements emitted as
idiomatic Dart statements, so that control flow is readable and correct.

#### Acceptance Criteria

1. THE `Dart_Generator` SHALL emit IR `Block` nodes as Dart `{ }` blocks.
2. THE `Dart_Generator` SHALL emit IR `IfStatement` nodes as Dart `if`/`else` statements.
3. THE `Dart_Generator` SHALL emit IR `WhileStatement` nodes as Dart `while` loops.
4. THE `Dart_Generator` SHALL emit IR `ForStatement` nodes as Dart `for` loops.
5. THE `Dart_Generator` SHALL emit IR `ForEachStatement` nodes as Dart `for ... in` loops, using the element IR_Type for the loop variable type annotation.
6. THE `Dart_Generator` SHALL emit IR `SwitchStatement` nodes as Dart `switch` statements; `SwitchCase` nodes with `Pattern` IR nodes SHALL be emitted as Dart pattern-matching cases.
7. THE `Dart_Generator` SHALL emit IR `TryCatchStatement` nodes as Dart `try`/`on`/`catch`/`finally` blocks, mapping the caught exception IR_Type to the Dart `on` clause type.
8. THE `Dart_Generator` SHALL emit IR `ThrowStatement` and `ThrowExpression` nodes as Dart `throw` expressions; `IsRethrow = true` SHALL be emitted as bare `rethrow`.
9. THE `Dart_Generator` SHALL emit IR `ReturnStatement` nodes as Dart `return` statements.
10. THE `Dart_Generator` SHALL emit IR `LocalDeclaration` nodes as Dart `var` or explicitly typed local variable declarations, using explicit types when `Mapping_Config.naming_conventions` specifies explicit typing.
11. THE `Dart_Generator` SHALL emit IR `YieldReturnStatement` nodes as Dart `yield` and `YieldBreakStatement` nodes as Dart `return` inside generator functions.
12. THE `Dart_Generator` SHALL emit IR `UnsupportedNode` placeholders as Dart `// UNSUPPORTED: <description>` comments and attach a `CG` `Error` diagnostic identifying the source location.

---

### Requirement 6: Expression Emission

**User Story:** As a Dart developer reviewing generated code, I want C# expressions emitted as
idiomatic Dart expressions with correct operator precedence and type annotations.

#### Acceptance Criteria

1. THE `Dart_Generator` SHALL emit IR `Literal` nodes as Dart literals, converting C# verbatim strings to Dart raw strings (`r'...'`) and C# interpolated strings (`InterpolatedString` nodes) to Dart string interpolation (`'${...}'`).
2. THE `Dart_Generator` SHALL emit IR `BinaryExpression` nodes using the corresponding Dart binary operators; `OverflowCheck = true` SHALL emit a `CG` `Warning` diagnostic noting that overflow checking is not enforced in Dart.
3. THE `Dart_Generator` SHALL emit IR `UnaryExpression` nodes using the corresponding Dart unary operators.
4. THE `Dart_Generator` SHALL emit IR `InvocationExpression` nodes as Dart method calls, applying `Naming_Convention` casing to the method name.
5. THE `Dart_Generator` SHALL emit IR `MemberAccessExpression` nodes as Dart member access (`object.member`).
6. THE `Dart_Generator` SHALL emit IR `ObjectCreationExpression` nodes as Dart constructor calls (`ClassName(...)`).
7. THE `Dart_Generator` SHALL emit IR `ArrayCreationExpression` nodes as Dart `List<T>.filled(...)` or list literal expressions.
8. THE `Dart_Generator` SHALL emit IR `LambdaExpression` nodes as Dart anonymous functions or arrow functions (`(params) => expr`).
9. THE `Dart_Generator` SHALL emit IR `AwaitExpression` nodes as Dart `await` expressions; `ConfigureAwait = false` SHALL be silently dropped with a `CG` `Info` diagnostic noting the omission.
10. THE `Dart_Generator` SHALL emit IR `NullCoalescingExpression` nodes as Dart `??` expressions.
11. THE `Dart_Generator` SHALL emit IR `NullConditionalExpression` nodes as Dart `?.` member access or `?[]` element access.
12. THE `Dart_Generator` SHALL emit IR `CastExpression` nodes as Dart `as` casts.
13. THE `Dart_Generator` SHALL emit IR `IsExpression` nodes as Dart `is` type-test expressions.
14. THE `Dart_Generator` SHALL emit IR `SwitchExpression` nodes as Dart switch expressions.
15. THE `Dart_Generator` SHALL emit IR `TupleExpression` nodes as Dart record literals.
16. THE `Dart_Generator` SHALL emit IR `ConditionalExpression` nodes as Dart ternary expressions (`condition ? then : else`).

---

### Requirement 7: Namespace and Library Mapping

**User Story:** As a Dart developer, I want C# namespaces mapped to Dart library structure, so that
the generated package has a coherent import graph that mirrors the original project's organisation.

#### Acceptance Criteria

1. THE `Dart_Generator` SHALL map each IR `Namespace` node to a Dart library path under `lib/src/`, converting the namespace segments to `snake_case` path components (e.g., `MyApp.Services` → `lib/src/my_app/services/`).
2. THE `Dart_Generator` SHALL emit a `part` / `part of` directive pair when multiple IR nodes from the same namespace are split across files, or SHALL consolidate them into a single file when the namespace contains fewer than a configurable threshold of declarations.
3. THE `Dart_Generator` SHALL emit `import` directives at the top of each generated file for every external IR_Symbol referenced within that file, using the Dart package URI scheme (`package:<name>/src/<path>.dart`).
4. THE `Dart_Generator` SHALL emit `dart:core`, `dart:async`, `dart:collection`, and `dart:convert` imports only when the generated file actually references types from those libraries.
5. THE `Dart_Generator` SHALL emit the barrel export file `lib/<package_name>.dart` containing `export` directives for every public `lib/src/` file in the package.

---

### Requirement 8: Async and Stream Mapping

**User Story:** As a Dart developer, I want C# async patterns mapped to idiomatic Dart async
constructs, so that the generated code integrates naturally with Dart's event loop.

#### Acceptance Criteria

1. THE `Dart_Generator` SHALL emit every IR `Method` with `IsAsync = true` as a Dart `async` method with return type `Future<T>` where `T` is derived from the IR return type by unwrapping `Task<T>` or `ValueTask<T>`.
2. THE `Dart_Generator` SHALL emit every IR `Method` with `IsAsync = true` and `IsIterator = true` as a Dart `async*` method with return type `Stream<T>`.
3. THE `Dart_Generator` SHALL emit IR `AwaitExpression` nodes inside `async` methods as Dart `await` expressions.
4. WHEN an `InvocationExpression` IR node has `IsFireAndForget = true` AND `AsyncConfig.wrapUnawaitedVoid` is `true`, THE `Dart_Generator` SHALL emit `unawaited(...)` from `dart:async` around the call and SHALL attach a `CG` `Info` diagnostic identifying the fire-and-forget site.
4a. WHEN an `InvocationExpression` IR node has `IsFireAndForget = true` AND `AsyncConfig.wrapUnawaitedVoid` is `false`, THE `Dart_Generator` SHALL emit the call as a plain expression statement without an `unawaited(...)` wrapper.
4b. WHEN an `InvocationExpression` IR node has `IsFireAndForget = false` and its return IR_Type is `Task`, `Task<T>`, `ValueTask`, or `ValueTask<T>` and it appears as a bare expression statement (not awaited, not assigned), THE `Dart_Generator` SHALL emit the call as a plain expression statement and SHALL attach a `CG` `Warning` diagnostic identifying the unawaited call, noting that the original C# source did not suppress CS4014 at this site.
5. THE `Dart_Generator` SHALL map `Task.WhenAll(...)` `InvocationExpression` nodes to `Future.wait([...])` and `Task.WhenAny(...)` to `Future.any([...])`.

---

### Requirement 9: NuGet Package Dependency Mapping

**User Story:** As a Dart developer, I want NuGet package references translated to Dart pub
dependencies in `pubspec.yaml`, so that the generated package compiles without manual dependency
resolution.

#### Acceptance Criteria

1. THE `Package_Mapper` SHALL translate each entry in `IrCompilationUnit.PackageReferences` to a Dart pub dependency using `Mapping_Config.package_mappings` as the primary lookup.
2. WHEN a NuGet package has no entry in `Mapping_Config.package_mappings`, THE `Package_Mapper` SHALL consult the built-in mapping table (Tier 1 known mappings from the top-level spec) before falling back to emitting a `CG` `Warning` diagnostic identifying the unmapped package.
3. THE `Dart_Generator` SHALL emit all resolved Dart dependencies in the `dependencies` section of `pubspec.yaml` with their mapped version constraints.
4. WHEN a NuGet package maps to a `dart:*` SDK library, THE `Package_Mapper` SHALL NOT emit it as a `pubspec.yaml` dependency but SHALL ensure the corresponding `import` directive is emitted in generated files that use it.
5. FOR ALL `PackageReferences` entries, THE `Package_Mapper` SHALL record the mapping decision (mapped, built-in, or unmapped) in `Gen_Result.Diagnostics` at `Info` severity so that the mapping report can be generated.

---

### Requirement 10: Naming Conventions

**User Story:** As a Dart developer, I want generated identifiers to follow Dart naming conventions,
so that the generated code passes `dart analyze` style checks and reads naturally.

#### Acceptance Criteria

1. THE `Dart_Generator` SHALL apply the following default Dart naming rules unless overridden by `Mapping_Config.naming_conventions`: class names in `UpperCamelCase`, method and field names in `lowerCamelCase`, constant names in `lowerCamelCase`, enum values in `lowerCamelCase`, library and file names in `snake_case`.
2. WHEN a C# identifier conflicts with a Dart reserved keyword, THE `Dart_Generator` SHALL append a `$` suffix to the identifier and attach a `CG` `Info` diagnostic identifying the rename.
3. WHEN two C# identifiers in the same scope produce the same Dart identifier after casing transformation, THE `Dart_Generator` SHALL disambiguate by appending a numeric suffix (`_2`, `_3`, etc.) and attach a `CG` `Warning` diagnostic.
4. THE `Dart_Generator` SHALL preserve the original C# identifier as a Dart doc comment annotation (`/// C# name: <original>`) on the generated declaration when the name was transformed.

---

### Requirement 11: Determinism

**User Story:** As a CI/CD pipeline operator, I want the Dart_Generator to produce identical output
for identical input on every run, so that build caches and golden-file tests remain stable.

#### Acceptance Criteria

1. THE `Dart_Generator` SHALL produce identical `Gen_Result` output for identical `IR_Build_Result` input regardless of execution environment, OS, or process ID.
2. THE `Dart_Generator` SHALL emit `import` directives in alphabetical order within each generated file.
3. THE `Dart_Generator` SHALL emit declarations within a file in the same order as the corresponding IR nodes appear in the `IrCompilationUnit`, which is topological order from the IR_Builder.
4. THE `Dart_Generator` SHALL NOT embed timestamps, process IDs, or environment-dependent values in any generated file.
5. FOR ALL valid `IR_Build_Result` inputs, running THE `Dart_Generator` twice SHALL produce `Gen_Result` values where every `Gen_File.Content` is byte-for-byte identical.

---

### Requirement 12: Diagnostics and Error Reporting

**User Story:** As a transpiler user, I want clear, actionable diagnostics when Dart code cannot be
generated for an IR node, so that I know exactly what to fix or what to expect in the generated output.

#### Acceptance Criteria

1. THE `Dart_Generator` SHALL emit a structured `Diagnostic` conforming to the pipeline-wide schema for every IR node it cannot emit as valid Dart.
2. THE `Dart_Generator` SHALL assign diagnostic codes in the range `CG0001`–`CG9999`; no other pipeline component SHALL use the `CG` prefix.
3. THE `Dart_Generator` SHALL NOT emit duplicate diagnostics for the same `Gen_File` path and diagnostic code.
4. THE `Dart_Generator` SHALL aggregate all diagnostics into `Gen_Result.Diagnostics` rather than writing to standard output or throwing exceptions.
5. WHEN a `CG` `Error` diagnostic is emitted for a declaration, THE `Dart_Generator` SHALL substitute a `// GENERATION ERROR: <CG-code> <message>` comment in place of the declaration and continue generating remaining declarations.
6. THE `Dart_Generator` SHALL propagate all `IR`-prefixed and `PL`-prefixed diagnostics from `IR_Build_Result.Diagnostics` into `Gen_Result.Diagnostics` unchanged, so that the final `Gen_Result` is the single authoritative diagnostic list for the entire pipeline run.

---

### Requirement 13: Output Formatting

**User Story:** As a Dart developer, I want generated files to be formatted according to `dart format`
rules, so that I do not need to run a formatter manually after transpilation.

#### Acceptance Criteria

1. THE `Dart_Generator` SHALL emit all generated Dart source files with consistent indentation of two spaces per nesting level, matching `dart format` defaults.
2. THE `Dart_Generator` SHALL emit a blank line between top-level declarations within a file.
3. THE `Dart_Generator` SHALL emit trailing commas in multi-line argument lists and parameter lists to produce `dart format`-stable output.
4. THE `Dart_Generator` SHALL limit generated line length to 80 characters where possible, wrapping long expressions at operator or argument boundaries.
5. THE `Dart_Generator` SHALL emit a `// Generated by cs2dart. Do not edit manually.` header comment as the first line of every generated file.

---

### Requirement 14: Correctness Properties for Testing

**User Story:** As a transpiler test engineer, I want well-defined correctness properties for the
Dart_Generator, so that I can write property-based tests that catch regressions across a wide range
of IR inputs.

#### Acceptance Criteria

1. FOR ALL valid `IR_Build_Result` inputs, running THE `Dart_Generator` twice SHALL produce `Gen_Result` values where every `Gen_File.Content` is identical (determinism property).
2. FOR ALL `IrCompilationUnit` inputs where `IR_Build_Result.Success` is `true`, THE `Dart_Generator` SHALL produce a `Dart_Package` where the count of `Gen_File` entries equals the count of distinct source file paths in the `IrCompilationUnit` IR tree (file count preservation property).
3. FOR ALL generated `Gen_File` entries, the count of top-level Dart declarations SHALL equal the count of top-level IR `Class`, `Struct`, `Interface`, `Enum`, and `Delegate` Declaration nodes mapped to that file (declaration count preservation property).
4. FOR ALL IR `Method` nodes with `IsAsync = true`, the corresponding generated Dart method SHALL contain the `async` or `async*` keyword (async fidelity property).
5. FOR ALL IR `NullableType` nodes emitted when `NullableEnabled = true`, the corresponding Dart type annotation SHALL contain a `?` suffix (nullability fidelity property).
6. FOR ALL `Gen_File` entries, the generated content SHALL be parseable by the Dart parser without syntax errors (syntactic validity property).
