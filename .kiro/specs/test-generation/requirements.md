# Test Generation — Requirements Document

## Introduction

This document specifies the requirements for the **Test Generation** subsystem of the C# → Dart
transpiler. The subsystem is responsible for detecting C# test classes and test methods from the IR,
mapping xUnit / NUnit / MSTest constructs to `dart:test` equivalents, and emitting well-formed Dart
test files under the `test/` directory of each generated `Dart_Package`.

This spec fills the gap identified in Dart Generator Requirement 2.1, which states that the
`Dart_Generator` SHALL produce "generated test stubs under `test/` when the source project contains
test classes" but provides no further definition of what that means. All requirements here are
additive to the existing Dart Generator spec and must respect its pipeline contracts.

---

## Glossary

- **Test_Generator**: The subsystem described by this specification; responsible for detecting test
  IR nodes and emitting Dart test files.
- **IR_TestClass**: An IR `Class` node whose attribute list contains at least one recognized test
  framework marker attribute (see Requirement 1).
- **IR_TestMethod**: An IR `Method` node within an `IR_TestClass` whose attribute list contains at
  least one recognized test method marker attribute (see Requirement 2).
- **IR_TestAttribute**: An IR `Attribute` node attached to a `Class` or `Method` IR node that
  identifies it as a test fixture or test case in xUnit, NUnit, or MSTest.
- **Test_Framework**: The C# test framework inferred from the attributes present on an
  `IR_TestClass`; one of `xUnit`, `NUnit`, or `MSTest`.
- **Dart_Test_File**: A generated Dart source file under `test/` that contains `group(...)` and
  `test(...)` calls conforming to the `dart:test` / `test` pub package API.
- **Test_Group**: A Dart `group(...)` block corresponding to one `IR_TestClass`.
- **Test_Case**: A Dart `test(...)` block corresponding to one `IR_TestMethod`.
- **Parameterized_Test**: A test method that is executed multiple times with different data inputs
  (xUnit `[Theory]`/`[InlineData]`/`[MemberData]`/`[ClassData]`, NUnit `[TestCase]`/`[TestCaseSource]`,
  MSTest `[DataTestMethod]`/`[DataRow]`).
- **Lifecycle_Method**: A method that runs before or after tests at the method or class level
  (xUnit constructor/`IDisposable.Dispose`, NUnit `[SetUp]`/`[TearDown]`/`[OneTimeSetUp]`/
  `[OneTimeTearDown]`, MSTest `[TestInitialize]`/`[TestCleanup]`/`[ClassInitialize]`/
  `[ClassCleanup]`).
- **Assertion**: A call to a test framework assertion method (e.g., `Assert.Equal`, `Assert.Throws`,
  `Assert.IsTrue`) that is translated to a Dart `expect(...)` call with an appropriate matcher.
- **Dart_Matcher**: A `dart:test` matcher expression (e.g., `equals(x)`, `isTrue`, `throwsA(...)`)
  used as the second argument to `expect(...)`.
- **Test_Diagnostic**: A `CG`-prefixed structured diagnostic emitted by the `Test_Generator` when a
  test construct cannot be fully translated.
- **Gen_Result**: The output of the `Dart_Generator` as defined in the Dart Generator spec. The
  `Test_Generator` contributes `Gen_File` entries to the `Dart_Package.Files` list.
- **Mapping_Config**: The configuration object from `IR_Build_Result.Config`, consumed via
  `IConfigService`; the `Test_Generator` SHALL NOT read `transpiler.yaml` directly.

---

## Requirements

### Requirement 1: Test Class Detection

**User Story:** As a Dart developer receiving generated test files, I want the transpiler to
automatically detect C# test classes from the IR, so that every test class in the source project
produces a corresponding Dart test file without manual annotation.

#### Acceptance Criteria

1. THE `Test_Generator` SHALL identify an IR `Class` node as an `IR_TestClass` when its `Attributes`
   list contains at least one of the following attribute names (matched by simple name, ignoring
   namespace):
   - xUnit: no class-level attribute required; detection is deferred to method-level (see Requirement 2)
   - NUnit: `TestFixture`
   - MSTest: `TestClass`
2. THE `Test_Generator` SHALL identify an IR `Class` node as an `IR_TestClass` for xUnit when the
   class contains at least one `IR_TestMethod` (i.e., a method with `[Fact]` or `[Theory]`), even
   though xUnit does not require a class-level attribute.
3. THE `Test_Generator` SHALL NOT treat abstract IR `Class` nodes as `IR_TestClass` instances; abstract
   test base classes SHALL be recognized only when a concrete subclass inherits from them.
4. WHEN an IR `Class` node is identified as an `IR_TestClass`, THE `Test_Generator` SHALL record the
   inferred `Test_Framework` on the class for use in all downstream mapping decisions.
5. IF an IR `Class` node carries attributes from more than one test framework (e.g., both `[TestFixture]`
   and `[TestClass]`), THEN THE `Test_Generator` SHALL emit a `Test_Diagnostic` of severity `Warning`
   with code `CG1001` identifying the ambiguity and SHALL use the first recognized framework in
   attribute declaration order.
6. THE `Test_Generator` SHALL process only `IR_TestClass` nodes; non-test IR `Class` nodes SHALL be
   passed through to the standard `Dart_Generator` emission path unchanged.

---

### Requirement 2: Test Method Detection

**User Story:** As a Dart developer, I want every C# test method to be detected and mapped to a
Dart `test(...)` call, so that the full test suite is represented in the generated Dart files.

#### Acceptance Criteria

1. THE `Test_Generator` SHALL identify an IR `Method` node as an `IR_TestMethod` when its `Attributes`
   list contains at least one of the following attribute names:
   - xUnit: `Fact`, `Theory`
   - NUnit: `Test`, `TestCase`, `TestCaseSource`
   - MSTest: `TestMethod`, `DataTestMethod`
2. THE `Test_Generator` SHALL identify an IR `Method` node as a `Lifecycle_Method` when its
   `Attributes` list contains at least one of the following attribute names:
   - NUnit: `SetUp`, `TearDown`, `OneTimeSetUp`, `OneTimeTearDown`
   - MSTest: `TestInitialize`, `TestCleanup`, `ClassInitialize`, `ClassCleanup`
   - xUnit: no attribute; constructor methods with `IsConstructor = true` map to per-test setup,
     and methods implementing `IDisposable.Dispose` map to per-test teardown.
3. THE `Test_Generator` SHALL NOT emit a `test(...)` call for `Lifecycle_Method` nodes; they are
   mapped to `setUp`, `tearDown`, `setUpAll`, or `tearDownAll` calls (see Requirement 5).
4. WHEN an IR `Method` node carries both a test method attribute and a lifecycle attribute,
   THE `Test_Generator` SHALL emit a `Test_Diagnostic` of severity `Warning` with code `CG1002`
   and SHALL treat the method as a `Lifecycle_Method`, not an `IR_TestMethod`.
5. THE `Test_Generator` SHALL preserve the original C# method name as the Dart `test(...)` description
   string, converting `PascalCase` or `snake_case` names to a human-readable sentence by inserting
   spaces before uppercase letters (e.g., `CalculatesSum_WhenInputsArePositive` →
   `"Calculates Sum When Inputs Are Positive"`).
6. WHEN an `IR_TestMethod` has `IsAsync = true`, THE `Test_Generator` SHALL emit the test body as
   an `async` Dart closure: `test('...', () async { ... })`.

---

### Requirement 3: Test Framework Construct Mapping

**User Story:** As a Dart developer, I want C# test framework constructs mapped to their `dart:test`
equivalents, so that the generated test files are idiomatic and runnable without modification.

#### Acceptance Criteria

1. THE `Test_Generator` SHALL wrap each `IR_TestClass` in a single top-level `group('<ClassName>', () { ... })`
   call in the generated Dart test file.
2. THE `Test_Generator` SHALL emit each `IR_TestMethod` as a `test('<description>', () { ... })` call
   inside the enclosing `group(...)`.
3. THE `Test_Generator` SHALL emit `setUp(() { ... })` inside the `group(...)` for per-test setup
   (see Requirement 5 for lifecycle mapping details).
4. THE `Test_Generator` SHALL emit `tearDown(() { ... })` inside the `group(...)` for per-test
   teardown.
5. THE `Test_Generator` SHALL emit `setUpAll(() { ... })` inside the `group(...)` for one-time class
   setup.
6. THE `Test_Generator` SHALL emit `tearDownAll(() { ... })` inside the `group(...)` for one-time
   class teardown.
7. WHEN an `IR_TestClass` contains nested test classes (e.g., NUnit nested `[TestFixture]` classes),
   THE `Test_Generator` SHALL emit nested `group(...)` calls, one per nesting level.
8. THE `Test_Generator` SHALL emit `import 'package:test/test.dart';` as the first import in every
   generated Dart test file.
9. THE `Test_Generator` SHALL emit a `void main() { ... }` function at the top level of every
   generated Dart test file, with all `group(...)` calls inside `main()`.

---

### Requirement 4: Assertion and Matcher Mapping

**User Story:** As a Dart developer, I want C# assertion calls translated to `dart:test` `expect(...)`
calls with appropriate matchers, so that test assertions are semantically equivalent in the generated
Dart code.

#### Acceptance Criteria

1. THE `Test_Generator` SHALL translate the following xUnit / NUnit / MSTest assertion calls to
   `expect(actual, matcher)` calls according to this table:

   | C# Assertion | Dart `expect(actual, matcher)` |
   |---|---|
   | `Assert.Equal(expected, actual)` | `expect(actual, equals(expected))` |
   | `Assert.NotEqual(expected, actual)` | `expect(actual, isNot(equals(expected)))` |
   | `Assert.True(condition)` | `expect(condition, isTrue)` |
   | `Assert.False(condition)` | `expect(condition, isFalse)` |
   | `Assert.Null(value)` | `expect(value, isNull)` |
   | `Assert.NotNull(value)` | `expect(value, isNotNull)` |
   | `Assert.Same(expected, actual)` | `expect(actual, same(expected))` |
   | `Assert.NotSame(expected, actual)` | `expect(actual, isNot(same(expected)))` |
   | `Assert.Contains(expected, collection)` | `expect(collection, contains(expected))` |
   | `Assert.DoesNotContain(expected, collection)` | `expect(collection, isNot(contains(expected)))` |
   | `Assert.Empty(collection)` | `expect(collection, isEmpty)` |
   | `Assert.NotEmpty(collection)` | `expect(collection, isNotEmpty)` |
   | `Assert.Throws<T>(action)` | `expect(action, throwsA(isA<T>()))` |
   | `Assert.ThrowsAsync<T>(action)` | `expect(action(), throwsA(isA<T>()))` |
   | `Assert.IsType<T>(obj)` | `expect(obj, isA<T>())` |
   | `Assert.IsAssignableFrom<T>(obj)` | `expect(obj, isA<T>())` |
   | `Assert.InRange(value, low, high)` | `expect(value, inInclusiveRange(low, high))` |
   | `Assert.StartsWith(expected, actual)` | `expect(actual, startsWith(expected))` |
   | `Assert.EndsWith(expected, actual)` | `expect(actual, endsWith(expected))` |
   | `Assert.Matches(pattern, actual)` | `expect(actual, matches(pattern))` |
   | `Assert.IsTrue(condition)` (NUnit/MSTest) | `expect(condition, isTrue)` |
   | `Assert.IsFalse(condition)` (NUnit/MSTest) | `expect(condition, isFalse)` |
   | `Assert.IsNull(value)` (NUnit/MSTest) | `expect(value, isNull)` |
   | `Assert.IsNotNull(value)` (NUnit/MSTest) | `expect(value, isNotNull)` |
   | `Assert.AreEqual(expected, actual)` (NUnit/MSTest) | `expect(actual, equals(expected))` |
   | `Assert.AreNotEqual(expected, actual)` (NUnit/MSTest) | `expect(actual, isNot(equals(expected)))` |
   | `Assert.AreSame(expected, actual)` (NUnit/MSTest) | `expect(actual, same(expected))` |
   | `Assert.AreNotSame(expected, actual)` (NUnit/MSTest) | `expect(actual, isNot(same(expected)))` |
   | `Assert.That(actual, Is.EqualTo(expected))` (NUnit) | `expect(actual, equals(expected))` |
   | `Assert.That(actual, Is.Null)` (NUnit) | `expect(actual, isNull)` |
   | `Assert.That(actual, Is.Not.Null)` (NUnit) | `expect(actual, isNotNull)` |
   | `Assert.That(actual, Is.True)` (NUnit) | `expect(actual, isTrue)` |
   | `Assert.That(actual, Is.False)` (NUnit) | `expect(actual, isFalse)` |
   | `Assert.That(actual, Is.InstanceOf<T>())` (NUnit) | `expect(actual, isA<T>())` |
   | `Assert.That(actual, Is.Empty)` (NUnit) | `expect(actual, isEmpty)` |
   | `Assert.That(actual, Has.Count.EqualTo(n))` (NUnit) | `expect(actual, hasLength(n))` |
   | `Assert.That(actual, Contains.Item(x))` (NUnit) | `expect(actual, contains(x))` |
   | `Assert.Fail(message)` | `fail(message)` |

2. WHEN an assertion call is not in the mapping table above, THE `Test_Generator` SHALL emit a
   `// TODO: translate assertion: <original C# call>` comment in place of the `expect(...)` call
   and SHALL emit a `Test_Diagnostic` of severity `Warning` with code `CG1010`.
3. WHEN an assertion carries a custom failure message argument (e.g., `Assert.Equal(a, b, "message")`),
   THE `Test_Generator` SHALL emit `expect(actual, matcher, reason: 'message')`.
4. THE `Test_Generator` SHALL detect `Assert.Throws<T>` and `Assert.ThrowsAsync<T>` calls and emit
   the action as a zero-argument closure if it is not already a lambda in the IR.
5. WHEN an NUnit `Assert.That(actual, constraint)` call uses a constraint expression that has no
   direct `dart:test` matcher equivalent, THE `Test_Generator` SHALL emit a `// TODO` comment and
   a `Test_Diagnostic` of severity `Warning` with code `CG1011`.

---

### Requirement 5: Test Lifecycle Method Mapping

**User Story:** As a Dart developer, I want C# test lifecycle methods (setup and teardown) mapped to
the correct `dart:test` hooks, so that test initialization and cleanup logic runs at the right time.

#### Acceptance Criteria

1. THE `Test_Generator` SHALL map per-test setup methods to `setUp(() { ... })` according to this
   table:

   | C# Framework | Setup Attribute / Pattern | Dart Equivalent |
   |---|---|---|
   | xUnit | Constructor (`IsConstructor = true`) | `setUp(() { ... })` |
   | NUnit | `[SetUp]` | `setUp(() { ... })` |
   | MSTest | `[TestInitialize]` | `setUp(() { ... })` |

2. THE `Test_Generator` SHALL map per-test teardown methods to `tearDown(() { ... })` according to
   this table:

   | C# Framework | Teardown Attribute / Pattern | Dart Equivalent |
   |---|---|---|
   | xUnit | `IDisposable.Dispose` implementation | `tearDown(() { ... })` |
   | NUnit | `[TearDown]` | `tearDown(() { ... })` |
   | MSTest | `[TestCleanup]` | `tearDown(() { ... })` |

3. THE `Test_Generator` SHALL map one-time class-level setup methods to `setUpAll(() { ... })`
   according to this table:

   | C# Framework | One-Time Setup Attribute / Pattern | Dart Equivalent |
   |---|---|---|
   | xUnit | `IClassFixture<T>` constructor injection | `setUpAll(() { ... })` with a comment noting fixture injection is approximated |
   | NUnit | `[OneTimeSetUp]` | `setUpAll(() { ... })` |
   | MSTest | `[ClassInitialize]` | `setUpAll(() { ... })` |

4. THE `Test_Generator` SHALL map one-time class-level teardown methods to `tearDownAll(() { ... })`
   according to this table:

   | C# Framework | One-Time Teardown Attribute / Pattern | Dart Equivalent |
   |---|---|---|
   | xUnit | `IClassFixture<T>` dispose | `tearDownAll(() { ... })` with a comment noting fixture disposal is approximated |
   | NUnit | `[OneTimeTearDown]` | `tearDownAll(() { ... })` |
   | MSTest | `[ClassCleanup]` | `tearDownAll(() { ... })` |

5. WHEN a lifecycle method is `async` (`IsAsync = true`), THE `Test_Generator` SHALL emit the
   corresponding hook as an async closure: `setUp(() async { ... })`.
6. WHEN an `IR_TestClass` has multiple methods with the same lifecycle attribute (e.g., two
   `[SetUp]` methods in NUnit), THE `Test_Generator` SHALL emit a single `setUp(...)` that calls
   each method body in declaration order and SHALL emit a `Test_Diagnostic` of severity `Warning`
   with code `CG1020`.
7. WHEN an xUnit test class uses `IClassFixture<T>` constructor injection, THE `Test_Generator`
   SHALL emit a `// TODO: xUnit IClassFixture<T> injection approximated — review shared state`
   comment inside `setUpAll(...)` and SHALL emit a `Test_Diagnostic` of severity `Info` with code
   `CG1021`.

---

### Requirement 6: Parameterized Test Mapping

**User Story:** As a Dart developer, I want C# parameterized tests (xUnit `[Theory]`, NUnit
`[TestCase]`, MSTest `[DataRow]`) to be expanded into individual Dart `test(...)` calls, so that
each data row is independently runnable and reportable.

#### Acceptance Criteria

1. WHEN an `IR_TestMethod` carries xUnit `[InlineData(...)]` attributes, THE `Test_Generator` SHALL
   emit one `test(...)` call per `[InlineData]` attribute, appending the argument values to the
   test description (e.g., `test('Adds numbers (1, 2)', () { ... })`).
2. WHEN an `IR_TestMethod` carries NUnit `[TestCase(...)]` attributes, THE `Test_Generator` SHALL
   emit one `test(...)` call per `[TestCase]` attribute, using the same description-appending
   strategy as criterion 1.
3. WHEN an `IR_TestMethod` carries MSTest `[DataRow(...)]` attributes, THE `Test_Generator` SHALL
   emit one `test(...)` call per `[DataRow]` attribute, using the same description-appending
   strategy as criterion 1.
4. WHEN an `IR_TestMethod` carries xUnit `[MemberData(...)]` or `[ClassData(...)]` attributes, or
   NUnit `[TestCaseSource(...)]`, THE `Test_Generator` SHALL emit a single `test(...)` call with a
   `// TODO: data-driven test — source: <MemberName or TypeName>` comment inside the body and SHALL
   emit a `Test_Diagnostic` of severity `Warning` with code `CG1030`, because the data source
   cannot be statically resolved from the IR.
5. WHEN a `[TestCase]` or `[DataRow]` attribute carries a `TestName` or `DisplayName` named
   argument, THE `Test_Generator` SHALL use that value as the Dart `test(...)` description instead
   of the auto-generated one.
6. WHEN a `[TestCase]` attribute carries an `ExpectedException` named argument (NUnit), THE
   `Test_Generator` SHALL wrap the test body in `expect(() { ... }, throwsA(isA<ExceptionType>()))`.
7. FOR ALL parameterized test expansions, the count of emitted `test(...)` calls SHALL equal the
   count of inline data attributes on the `IR_TestMethod` (expansion count invariant).

---

### Requirement 7: Output File Structure

**User Story:** As a Dart developer, I want generated test files placed in a predictable location
under `test/`, mirroring the source project's directory structure, so that I can navigate between
source and test files easily.

#### Acceptance Criteria

1. THE `Test_Generator` SHALL emit one Dart test file per source file that contains at least one
   `IR_TestClass`, placing it under `test/` with the same relative path as the source file under
   `lib/src/`, replacing the `.dart` extension with `_test.dart`
   (e.g., `lib/src/services/calculator.dart` → `test/services/calculator_test.dart`).
2. WHEN a single source file contains multiple `IR_TestClass` nodes, THE `Test_Generator` SHALL
   emit all their `group(...)` calls into the same `_test.dart` file, in declaration order.
3. THE `Test_Generator` SHALL NOT emit a test file for source files that contain no `IR_TestClass`
   nodes.
4. THE `Test_Generator` SHALL add each generated `Dart_Test_File` as a `Gen_File` entry in the
   enclosing `Dart_Package.Files` list, with `RelativePath` set to the `test/`-relative path.
5. THE `Test_Generator` SHALL emit the `// Generated by cs2dart. Do not edit manually.` header
   comment as the first line of every generated Dart test file, consistent with Dart Generator
   Requirement 13.5.
6. WHEN the source project contains no `IR_TestClass` nodes, THE `Test_Generator` SHALL emit no
   files under `test/` and SHALL NOT add a `test/` directory entry to the `Dart_Package`.

---

### Requirement 8: pubspec.yaml dev_dependencies

**User Story:** As a Dart developer, I want the generated `pubspec.yaml` to include the `test`
package as a `dev_dependency` whenever the source project contains test classes, so that the
generated package compiles and runs tests without manual dependency editing.

#### Acceptance Criteria

1. WHEN an `IrCompilationUnit` contains at least one `IR_TestClass`, THE `Test_Generator` SHALL
   instruct the `Dart_Generator` to add a `dev_dependencies` section to `pubspec.yaml` containing
   `test: ^1.25.0`.
2. WHEN an `IrCompilationUnit` contains no `IR_TestClass` nodes, THE `Test_Generator` SHALL NOT
   add a `dev_dependencies` section or a `test` entry to `pubspec.yaml`.
3. WHEN `pubspec.yaml` already contains a `dev_dependencies` section (e.g., from other dev
   dependencies), THE `Test_Generator` SHALL merge the `test` entry into the existing section
   rather than creating a duplicate section.
4. THE `Test_Generator` SHALL NOT add the `test` package to the `dependencies` section; it SHALL
   appear only under `dev_dependencies`.
5. WHEN `IConfigService.packageMappings` contains an explicit mapping for the `test` package,
   THE `Test_Generator` SHALL use the mapped version constraint instead of the default `^1.25.0`.

---

### Requirement 9: Integration with the Dart Generator Pipeline

**User Story:** As a pipeline integrator, I want the Test_Generator to integrate cleanly into the
existing Dart Generator pipeline contract, so that test file generation does not require changes to
the IR_Builder or Project_Loader.

#### Acceptance Criteria

1. THE `Test_Generator` SHALL accept an `IR_Build_Result` as its sole input, consistent with the
   Dart Generator contract defined in Dart Generator Requirement 1.1.
2. THE `Test_Generator` SHALL be invoked by the `Dart_Generator` as a sub-step during the
   processing of each `IrCompilationUnit`; it SHALL NOT be a separate pipeline stage.
3. THE `Test_Generator` SHALL read configuration exclusively through the `IConfigService` instance
   carried in `IR_Build_Result.Config`; it SHALL NOT read `transpiler.yaml` directly.
4. THE `Test_Generator` SHALL contribute `Gen_File` entries to the `Dart_Package.Files` list
   produced by the `Dart_Generator`; it SHALL NOT produce a separate output object.
5. THE `Test_Generator` SHALL aggregate all `Test_Diagnostic` entries into `Gen_Result.Diagnostics`
   using the `CG`-prefixed code range `CG1000`–`CG1999`, which is reserved for test generation
   diagnostics within the broader `CG0001`–`CG9999` range.
6. THE `Test_Generator` SHALL reuse the existing `Type_Mapper` sub-component from the
   `Dart_Generator` for all C# → Dart type translations within test files.
7. THE `Test_Generator` SHALL reuse the existing `Naming_Convention` rules from `Mapping_Config`
   for all identifier transformations in generated test files.
8. WHEN `IR_Build_Result.Success` is `false`, THE `Test_Generator` SHALL follow the same skip
   logic as the `Dart_Generator` (Dart Generator Requirement 1.4): attempt generation for units
   with no `Error`-severity diagnostics and emit a `CG`-prefixed `Warning` for each skipped unit.

---

### Requirement 10: Diagnostic Codes and Error Handling

**User Story:** As a transpiler user, I want clear, actionable diagnostics when a test construct
cannot be fully translated, so that I know exactly what to review in the generated test files.

#### Acceptance Criteria

1. THE `Test_Generator` SHALL emit structured `Test_Diagnostic` records conforming to the
   pipeline-wide `Diagnostic` schema (Severity, Code, Message, optional Source, optional Location).
2. THE `Test_Generator` SHALL use diagnostic codes in the range `CG1000`–`CG1999`; the following
   codes are reserved:

   | Code | Severity | Condition |
   |---|---|---|
   | `CG1001` | Warning | Ambiguous test framework: multiple framework attributes on one class |
   | `CG1002` | Warning | Method carries both test and lifecycle attributes |
   | `CG1010` | Warning | Assertion call has no known `dart:test` mapping |
   | `CG1011` | Warning | NUnit `Assert.That` constraint has no known matcher equivalent |
   | `CG1020` | Warning | Multiple lifecycle methods with the same role in one class |
   | `CG1021` | Info | xUnit `IClassFixture<T>` injection approximated |
   | `CG1030` | Warning | Data-driven test with non-inline data source (cannot statically resolve) |
   | `CG1040` | Warning | Test method body contains unsupported IR node (`UnsupportedNode`) |
   | `CG1050` | Error | `IR_TestClass` references a type that cannot be resolved by `Type_Mapper` |
   | `CG1060` | Info | xUnit `[Collection]` attribute detected; collection-level fixtures are not supported and are dropped |

3. THE `Test_Generator` SHALL NOT emit duplicate diagnostics for the same source location and
   diagnostic code.
4. WHEN a `Test_Diagnostic` of severity `Error` is emitted for an `IR_TestMethod`, THE
   `Test_Generator` SHALL substitute a `test('...', () { /* GENERATION ERROR: <CG-code> <message> */ })` 
   stub and continue generating remaining test methods.
5. WHEN a `Test_Diagnostic` of severity `Error` is emitted for an `IR_TestClass`, THE
   `Test_Generator` SHALL substitute a `group('...', () { /* GENERATION ERROR: <CG-code> <message> */ })`
   stub and continue generating remaining test classes.
6. THE `Test_Generator` SHALL propagate all upstream `IR`-prefixed and `PL`-prefixed diagnostics
   from `IR_Build_Result.Diagnostics` into `Gen_Result.Diagnostics` unchanged, consistent with
   Dart Generator Requirement 12.6.

---

### Requirement 11: Correctness Properties for Property-Based Testing

**User Story:** As a transpiler test engineer, I want well-defined correctness properties for the
Test_Generator, so that I can write property-based tests that catch regressions across a wide range
of C# test class inputs.

#### Acceptance Criteria

1. FOR ALL valid `IrCompilationUnit` inputs containing at least one `IR_TestClass`, THE
   `Test_Generator` SHALL produce at least one `Gen_File` with a `RelativePath` ending in `_test.dart`
   (test file presence property).
2. FOR ALL valid `IrCompilationUnit` inputs containing no `IR_TestClass` nodes, THE `Test_Generator`
   SHALL produce zero `Gen_File` entries with a `RelativePath` starting with `test/`
   (no spurious test files property).
3. FOR ALL `IR_TestClass` nodes, the count of `test(...)` calls in the generated Dart test file
   SHALL be greater than or equal to the count of `IR_TestMethod` nodes in that class (test count
   lower bound property — parameterized tests may expand one method to multiple calls).
4. FOR ALL `IR_TestMethod` nodes with `[InlineData]`, `[TestCase]`, or `[DataRow]` attributes, the
   count of emitted `test(...)` calls for that method SHALL equal the count of inline data
   attributes (parameterized expansion count property).
5. FOR ALL valid `IrCompilationUnit` inputs, running THE `Test_Generator` twice on the same input
   SHALL produce identical `Gen_File` content (determinism property).
6. FOR ALL generated `Dart_Test_File` entries, the generated content SHALL be parseable by the Dart
   parser without syntax errors (syntactic validity property).
7. FOR ALL `IR_TestClass` nodes, the generated Dart test file SHALL contain exactly one top-level
   `group(...)` call per `IR_TestClass` in the file (one group per class property).
8. FOR ALL `IrCompilationUnit` inputs containing at least one `IR_TestClass`, the generated
   `pubspec.yaml` content SHALL contain a `dev_dependencies` section with a `test:` entry
   (dev_dependency presence property).
9. FOR ALL assertion `InvocationExpression` nodes that map to a known entry in the assertion
   mapping table (Requirement 4.1), the generated Dart SHALL contain an `expect(` call at the
   corresponding source location (assertion translation fidelity property).

