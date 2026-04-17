# C# → Dart Struct Mapping — Requirements

## Glossary

- **Struct_Transpiler**: The transpiler subsystem responsible for converting C# struct declarations and usages into Dart.
- **Value_Type**: A C# type whose instances are copied on assignment, not referenced.
- **Dart_Value_Class**: A Dart class that emulates value-type semantics via immutability and value equality.
- **Readonly_Struct**: A C# struct declared with the `readonly` modifier, where all fields are implicitly `readonly`.
- **BCL_Struct**: A well-known struct from the .NET Base Class Library (e.g., `DateTime`, `Guid`, `TimeSpan`, `DateOnly`, `TimeOnly`).
- **Default_Value**: The zero-initialized value of a struct when no constructor is called.
- **Boxing**: The implicit conversion of a value type to `object` (or an interface type) in C#.
- **Unboxing**: The explicit cast from `object` back to a value type in C#.
- **IR**: The language-agnostic Intermediate Representation used between the Roslyn frontend and the Dart code generator.

---

## Requirement 1: Value Type Semantics

**User Story:** As a developer migrating a C# codebase, I want struct assignments to behave as copies in the generated Dart code, so that value-type semantics are preserved and mutations to one variable do not affect another.

### Acceptance Criteria

1. THE Struct_Transpiler SHALL emit each C# struct as an immutable Dart class with a `copyWith` method.
2. WHEN a C# struct is assigned to a new variable, THE Struct_Transpiler SHALL emit a `copyWith()` call (or equivalent copy constructor invocation) in the generated Dart code.
3. WHEN a C# struct is passed as a method argument, THE Struct_Transpiler SHALL emit a copy at the call site to preserve pass-by-value semantics.
4. THE Dart_Value_Class SHALL declare all fields as `final` to enforce immutability.
5. WHEN a C# struct field is mutated after assignment (e.g., `point.X = 5`), THE Struct_Transpiler SHALL emit a reassignment of the enclosing variable using `copyWith` rather than a direct field mutation.

---

## Requirement 2: Struct Fields and Methods

**User Story:** As a developer, I want struct fields and methods to be faithfully translated, so that the generated Dart class exposes the same data and behavior as the original C# struct.

### Acceptance Criteria

1. THE Struct_Transpiler SHALL translate each C# struct instance field to a `final` field on the generated Dart class.
2. THE Struct_Transpiler SHALL translate each C# struct instance method to an equivalent Dart instance method on the generated Dart class.
3. THE Struct_Transpiler SHALL translate each C# struct static method to a Dart `static` method on the generated Dart class.
4. THE Struct_Transpiler SHALL translate each C# struct property (get/set) to a Dart getter and, where a setter exists, emit a `copyWith`-based replacement rather than a mutable setter.
5. WHEN a C# struct contains `ref` or `out` parameters in its methods, THE Struct_Transpiler SHALL emit a diagnostic warning and apply the configured fallback strategy (wrapper object or record return type).

---

## Requirement 3: Readonly Structs

**User Story:** As a developer, I want `readonly struct` declarations to map cleanly to Dart, so that the immutability contract is preserved without extra runtime overhead.

### Acceptance Criteria

1. WHEN a C# struct is declared with the `readonly` modifier, THE Struct_Transpiler SHALL emit a Dart class where all fields are `final` and no `copyWith` mutation paths are generated for internal state.
2. THE Struct_Transpiler SHALL annotate the generated Dart class with a `// readonly struct` comment to preserve traceability.
3. WHEN a C# `readonly struct` method is annotated with `readonly` (C# 8 member-level readonly), THE Struct_Transpiler SHALL treat the method as non-mutating and emit it as a standard Dart instance method.

---

## Requirement 4: Struct Constructors

**User Story:** As a developer, I want struct constructors (including parameterless constructors introduced in C# 10) to be correctly translated, so that object initialization behaves the same in Dart.

### Acceptance Criteria

1. THE Struct_Transpiler SHALL translate each C# struct constructor to a Dart constructor with equivalent parameters and initialization logic.
2. WHEN a C# struct defines a parameterless constructor (C# 10+), THE Struct_Transpiler SHALL emit a corresponding no-argument Dart constructor that initializes all fields to the declared default values.
3. WHEN a C# struct has no explicit constructor, THE Struct_Transpiler SHALL emit a Dart constructor that initializes all fields to their type's default value (0, false, null, etc.).
4. THE Struct_Transpiler SHALL translate C# `this(...)` constructor chaining to Dart redirecting constructors where semantically equivalent.
5. WHEN a C# struct uses object initializer syntax (`new MyStruct { X = 1 }`), THE Struct_Transpiler SHALL emit the equivalent named-parameter Dart constructor call.

---

## Requirement 5: Default Values

**User Story:** As a developer, I want the zero-initialized default of a C# struct to be reproducible in Dart, so that code relying on `default(T)` or uninitialized struct fields behaves correctly.

### Acceptance Criteria

1. THE Struct_Transpiler SHALL emit a static `defaultValue` factory or constant on each generated Dart class that returns the zero-initialized equivalent of the C# struct's default.
2. WHEN `default(T)` or `new T()` is used in C# source for a struct type `T`, THE Struct_Transpiler SHALL replace it with a call to the generated `defaultValue` factory in Dart.
3. THE Struct_Transpiler SHALL map C# numeric field defaults (0, 0.0) to Dart `0` / `0.0`, boolean defaults to `false`, and reference-type fields to `null`.

---

## Requirement 6: Struct Interface Implementation

**User Story:** As a developer, I want structs that implement C# interfaces to generate Dart classes that implement the equivalent Dart abstract class or interface, so that polymorphic usage is preserved.

### Acceptance Criteria

1. WHEN a C# struct implements one or more interfaces, THE Struct_Transpiler SHALL emit `implements InterfaceName` on the generated Dart class for each translated interface.
2. THE Struct_Transpiler SHALL emit all interface-required members on the generated Dart class, consistent with Requirement 2.
3. WHEN a C# struct implements `IEquatable<T>`, THE Struct_Transpiler SHALL use the struct's `Equals` method body to generate the Dart `==` operator and `hashCode` override instead of the default field-based generation (see Requirement 9).
4. WHEN a C# struct implements `IComparable<T>`, THE Struct_Transpiler SHALL emit a `compareTo` method on the generated Dart class.

---

## Requirement 7: Nested Structs

**User Story:** As a developer, I want structs nested inside other types to be correctly scoped in the generated Dart output, so that naming and access rules are preserved.

### Acceptance Criteria

1. WHEN a C# struct is declared as a nested type inside a class or another struct, THE Struct_Transpiler SHALL emit the Dart class in the same file as the enclosing type, using a naming convention of `OuterType_InnerStruct` to avoid Dart's lack of nested class declarations.
2. THE Struct_Transpiler SHALL preserve the access modifier of the nested struct (public → public, private/internal → library-private with `_` prefix).
3. WHEN a nested struct is referenced from outside its enclosing type, THE Struct_Transpiler SHALL use the generated `OuterType_InnerStruct` name at all call sites.

---

## Requirement 8: Generic Structs

**User Story:** As a developer, I want generic C# structs to be translated to generic Dart classes, so that type-parameterized value types work correctly in the generated code.

### Acceptance Criteria

1. THE Struct_Transpiler SHALL translate each C# generic struct to a Dart generic class with equivalent type parameters.
2. WHEN a C# generic struct has type constraints (e.g., `where T : struct`, `where T : IComparable`), THE Struct_Transpiler SHALL emit the closest Dart type bound and add a `// constraint: <original>` comment where no direct Dart equivalent exists.
3. WHEN a C# generic struct is instantiated with a concrete type argument, THE Struct_Transpiler SHALL emit the corresponding Dart generic instantiation.
4. WHEN a C# generic struct uses `default(T)` for a type parameter, THE Struct_Transpiler SHALL emit `null` for nullable type parameters or a configurable sentinel value, and emit a diagnostic if the behavior is ambiguous.

---

## Requirement 9: Equality Semantics

**User Story:** As a developer, I want C# struct value equality to be preserved in Dart, so that equality checks and hash-based collections behave identically.

### Acceptance Criteria

1. THE Struct_Transpiler SHALL emit a `==` operator override on each generated Dart class that compares all fields by value.
2. THE Struct_Transpiler SHALL emit a `hashCode` override on each generated Dart class that combines the hash codes of all fields using a consistent algorithm (e.g., `Object.hash`).
3. WHEN a C# struct overrides `Equals(object)` or `GetHashCode()`, THE Struct_Transpiler SHALL translate the custom logic into the Dart `==` and `hashCode` overrides respectively.
4. THE Struct_Transpiler SHALL emit a `toString()` override that includes the struct type name and all field values, matching the default C# `ToString()` behavior for structs.
5. FOR ALL generated Dart_Value_Class instances `a` and `b` with identical field values, the generated `==` operator SHALL return `true` (value equality round-trip property).

---

## Requirement 10: Boxing and Unboxing

**User Story:** As a developer, I want boxing and unboxing of structs to be handled gracefully, so that code that passes structs as `object` or interface references does not silently break.

### Acceptance Criteria

1. WHEN a C# struct is implicitly boxed (assigned to `object`, `dynamic`, or an interface variable), THE Struct_Transpiler SHALL emit the Dart class instance directly, since Dart does not distinguish boxed and unboxed representations.
2. WHEN a C# explicit unboxing cast is encountered (e.g., `(MyStruct)obj`), THE Struct_Transpiler SHALL emit a Dart `as MyStruct` cast.
3. WHEN boxing occurs inside a generic context where `T` is constrained to `struct`, THE Struct_Transpiler SHALL emit a diagnostic noting that boxing semantics are approximated and the generated code should be reviewed.
4. THE Struct_Transpiler SHALL not emit unnecessary wrapper objects for boxing; the generated Dart class instance SHALL serve as both the boxed and unboxed representation.

---

## Requirement 11: BCL Struct Mappings

**User Story:** As a developer, I want common .NET BCL structs to map to well-known Dart equivalents, so that I don't have to manually replace standard types after transpilation.

### Acceptance Criteria

1. THE Struct_Transpiler SHALL map `System.DateTime` to Dart's `DateTime` class and translate common methods (`AddDays`, `AddHours`, `ToString(format)`, etc.) to their Dart equivalents.
2. THE Struct_Transpiler SHALL map `System.Guid` to a generated `Guid` Dart class (or a configured third-party package) that supports `Guid.NewGuid()`, `Guid.Empty`, `Guid.Parse(string)`, and `ToString()`.
3. THE Struct_Transpiler SHALL map `System.TimeSpan` to Dart's `Duration` class and translate common properties (`TotalSeconds`, `TotalMilliseconds`, `Days`, `Hours`, `Minutes`, `Seconds`) to their Dart equivalents.
4. THE Struct_Transpiler SHALL map `System.DateOnly` to Dart's `DateTime` (date-only usage) or a configured third-party equivalent, and emit a diagnostic noting the approximation.
5. THE Struct_Transpiler SHALL map `System.TimeOnly` to Dart's `Duration` or a configured third-party equivalent, and emit a diagnostic noting the approximation.
6. WHEN a BCL struct method or property has no direct Dart equivalent, THE Struct_Transpiler SHALL emit a `// TODO: no Dart equivalent for <member>` comment and a build-time diagnostic.
7. THE Struct_Transpiler SHALL allow BCL struct mappings to be overridden via `IConfigService.structMappings`.

---

## Requirement 12: Diagnostics and Round-Trip Fidelity

**User Story:** As a developer, I want the transpiler to report clear diagnostics for unsupported or approximated struct features, so that I can review and fix any semantic gaps after transpilation.

### Acceptance Criteria

1. WHEN a C# struct feature cannot be faithfully represented in Dart, THE Struct_Transpiler SHALL emit a named diagnostic (e.g., `CS2DART_STRUCT_001`) with a description, the source location, and a recommended remediation.
2. THE Struct_Transpiler SHALL produce deterministic output for struct transpilation: the same C# struct input SHALL always produce the same Dart output.
3. FOR ALL C# structs that are fully supported, the generated Dart class SHALL pass `dart analyze` with zero errors.
4. THE Struct_Transpiler SHALL track struct transpilation coverage in the feature support matrix, reporting the percentage of C# struct features with full, partial, or no Dart mapping.

---

## Requirement 13: Consume the Configuration Service

**User Story:** As a pipeline module author, I want the `Struct_Transpiler` to receive all configuration values through `IConfigService`, so that it is decoupled from YAML parsing and file I/O.

### Acceptance Criteria

1. THE Struct_Transpiler SHALL accept an `IConfigService` instance at construction time and SHALL use it as the sole source of all configuration values.
2. THE Struct_Transpiler SHALL NOT read or parse `transpiler.yaml` directly; all configuration access SHALL go through `IConfigService`.
3. WHEN `IConfigService.structMappings` contains an entry for a given C# struct name, THE Struct_Transpiler SHALL use the configured Dart type and member mappings instead of the defaults.
4. WHEN `IConfigService.namingConventions` specifies a non-default `classNameStyle`, THE Struct_Transpiler SHALL apply that style when generating Dart class names for structs.
5. WHEN all `IConfigService` accessors return their Default_Values, THE Struct_Transpiler SHALL apply all default struct mapping rules without error.
