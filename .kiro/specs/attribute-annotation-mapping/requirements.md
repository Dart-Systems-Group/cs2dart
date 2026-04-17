# Attribute → Annotation Mapping — Requirements Document

## Introduction

This document specifies the requirements for the **Attribute → Annotation Mapping** feature of the
C# → Dart transpiler. C# attributes are metadata decorators that appear on types, members,
parameters, return values, assemblies, and modules. They are critical to serialization frameworks
(Newtonsoft.Json, System.Text.Json), validation libraries (DataAnnotations), ORM tools (Entity
Framework), test frameworks (xUnit, NUnit, MSTest), and many other real-world .NET libraries.

The current pipeline silently drops all C# attributes, causing silent semantic divergence in the
generated Dart code. This feature closes that gap by:

1. **Extracting** every C# attribute in the Roslyn Frontend as structured plain-data records (never silently dropped), including full resolution of fully-qualified names and argument values.
2. **Promoting** the extracted attribute records into first-class `Attribute_Node` IR nodes in the IR_Builder, so downstream stages operate purely on IR.
3. Emitting known attributes as their Dart annotation equivalents in the Dart code generator.
4. Mapping package-level attributes via the existing `Mapping_Config` / NuGet handler integration.
5. Preserving unknown attributes as structured comments with `CG` `Warning` diagnostics.
6. Allowing users to define custom attribute mappings in `transpiler.yaml`.

This feature spans four pipeline stages: the **Roslyn_Frontend** (extraction), the **IR_Builder**
(promotion to IR nodes), the **Dart_Generator** (emission), and the **Config_Service** (custom
mapping configuration). Responsibility is strictly separated: the Roslyn_Frontend is the only stage
that calls Roslyn APIs and owns all attribute extraction; the IR_Builder reads the pre-extracted
structured data and promotes it into IR nodes without consulting Roslyn.

---

## Glossary

- **Attribute**: A C# metadata decorator applied to a declaration or parameter using `[AttributeName(...)]` syntax. Carries a name, zero or more positional constructor arguments, and zero or more named property-setter arguments.
- **Annotation**: A Dart metadata decorator applied to a declaration using `@annotationName(...)` syntax. Semantically equivalent to a C# attribute in the contexts this feature addresses.
- **Attribute_Node**: The new IR node type introduced by this feature. Carries the attribute's fully-qualified name, positional arguments (as ordered IR expression nodes), named arguments (as a map of string → IR expression node), the target kind, and the source location.
- **Attribute_Target**: The syntactic location to which an attribute is applied. One of: `Class`, `Struct`, `Interface`, `Enum`, `Method`, `Constructor`, `Property`, `Field`, `Parameter`, `ReturnValue`, `Assembly`, `Module`.
- **Attribute_Mapping**: A rule that maps a fully-qualified C# attribute name to a Dart annotation expression. Stored in `Mapping_Config.attribute_mappings`.
- **Attribute_Mapper**: The sub-component of the Dart_Generator responsible for resolving `Attribute_Node` instances to Dart annotation strings using the three-tier lookup.
- **Known_Mapping**: A built-in, hardcoded mapping from a well-known C# attribute to its Dart equivalent (e.g., `System.ObsoleteAttribute` → `@Deprecated(...)`).
- **Package_Mapping**: An attribute mapping derived from the NuGet package's `Attribute_Mapping` entry in `Mapping_Config.package_mappings` (e.g., `Newtonsoft.Json.JsonPropertyAttribute` → `@JsonKey(...)`).
- **Custom_Mapping**: A user-defined attribute mapping declared in the `attribute_mappings` section of `transpiler.yaml`.
- **Unmapped_Attribute**: An `Attribute_Node` for which no Known_Mapping, Package_Mapping, or Custom_Mapping exists. Emitted as a structured comment with a `CG` `Warning` diagnostic.
- **IR_Builder**: The pipeline stage that consumes `Frontend_Result` and promotes normalized, pre-extracted data into IR nodes. Extended by this feature to promote structured attribute records from the `Normalized_SyntaxTree` into `Attribute_Node` IR nodes. The IR_Builder SHALL NOT call any Roslyn API.
- **Dart_Generator**: The pipeline stage that emits Dart source from IR nodes. Extended by this feature to emit Dart annotations from `Attribute_Node` instances.
- **Config_Service**: The pipeline component that parses and exposes `transpiler.yaml`. Extended by this feature to expose the `attribute_mappings` section.
- **Mapping_Config**: The configuration object passed through the pipeline via `Load_Result.Config`. Extended by this feature with an `attribute_mappings` field.
- **Diagnostic**: A pipeline-wide structured record. Contains `Severity` (`Error`, `Warning`, `Info`), `Code` (string `<prefix><4-digits>`), `Message` (string), optional `Source` (file path), and optional `Location` (`{ Line, Column }`). Full schema defined in the top-level transpiler specification.

---

## Requirements

### Requirement 1: IR Attribute Node Promotion

**User Story:** As a Dart code generator author, I want every C# attribute represented as a typed
`Attribute_Node` in the IR, so that I can make informed emission decisions using only IR — without
consulting Roslyn, the `SemanticModel`, or raw C# syntax.

#### Acceptance Criteria

1. THE IR_Builder SHALL introduce an `Attribute_Node` IR node type in the Declarations category, carrying: `FullyQualifiedName` (string), `ShortName` (string), `PositionalArguments` (ordered list of IR expression nodes), `NamedArguments` (ordered list of `{ Name: string, Value: IR expression node }` pairs), `Target` (one of the `Attribute_Target` enum values), and `SourceLocation`.
2. THE IR_Builder SHALL attach a list of `Attribute_Node` instances to every IR node type that can carry C# attributes: `Class`, `Struct`, `Interface`, `Enum`, `EnumMember`, `Method`, `Constructor`, `Property`, `Field`, `Event`, `Delegate`, `Parameter`.
3. WHEN a declaration node in the `Normalized_SyntaxTree` carries one or more structured attribute records (placed there by the Roslyn_Frontend per RF Requirement 10), THE IR_Builder SHALL emit one `Attribute_Node` per record in the order the Roslyn_Frontend attached them; it SHALL NOT re-query Roslyn or re-parse attribute syntax.
4. THE IR_Builder SHALL populate `Attribute_Node.FullyQualifiedName` and all argument fields directly from the structured attribute record provided by the Roslyn_Frontend; it SHALL NOT call any Roslyn `SemanticModel` API to resolve attribute names or argument values.
5. THE IR_Builder SHALL promote assembly-level and module-level attribute records (attached to the compilation-unit node by the Roslyn_Frontend) as `Attribute_Node` instances on the `CompilationUnit` IR node, with `Target` set to `Assembly` or `Module` respectively.
6. THE IR_Builder SHALL promote return-value attribute records (attached to method nodes by the Roslyn_Frontend with a `ReturnValue` target marker) as `Attribute_Node` instances on the enclosing `Method` IR node with `Target = ReturnValue`.
7. WHEN a structured attribute record has `Kind = Unresolved` (set by the Roslyn_Frontend when it could not resolve the attribute's fully-qualified name per RF Requirement 10.4), THE IR_Builder SHALL set `Attribute_Node.FullyQualifiedName` to the unresolved short name, set `Target` to the syntactic target from the record, emit an `IR` `Warning` diagnostic identifying the unresolved attribute, and SHALL NOT drop the `Attribute_Node`.
8. THE IR_Builder SHALL promote every attribute argument — positional and named — from the structured attribute record into IR expression nodes using the same expression-promotion rules applied to all other IR expressions.
9. WHEN a structured attribute record contains an `UnsupportedNode` marker for an argument (placed by the Roslyn_Frontend when it could not lower the argument to a plain-data value per RF Requirement 10.2), THE IR_Builder SHALL substitute an `UnsupportedNode` placeholder for that argument and emit an `IR` `Warning` diagnostic; the `Attribute_Node` itself SHALL still be emitted.

---

### Requirement 2: IR Attribute Determinism and Serialization

**User Story:** As a developer debugging the transpiler, I want `Attribute_Node` instances to be
deterministically ordered and fully serializable, so that golden tests and round-trip checks remain
stable.

#### Acceptance Criteria

1. THE IR_Builder SHALL emit `Attribute_Node` lists in source-declaration order; WHEN source order is not deterministic (e.g., assembly-level attributes across multiple files), THE IR_Builder SHALL sort by `FullyQualifiedName` then by `SourceLocation` file path and line number.
2. THE Pretty_Printer SHALL serialize every `Attribute_Node` field — including all positional and named arguments — in its canonical output.
3. FOR ALL valid IR trees containing `Attribute_Node` instances, parsing the Pretty_Printer output SHALL produce an IR tree where every `Attribute_Node` is structurally and value-equal to the original (round-trip property).
4. THE IR_Validator SHALL verify that every `Attribute_Node` attached to an IR node has a non-null `FullyQualifiedName` and a valid `Target` value consistent with the type of the IR node it is attached to.
5. FOR ALL valid C# compilations, running THE IR_Builder twice SHALL produce IR trees with identical `Attribute_Node` lists (determinism property).

---

### Requirement 3: Three-Tier Attribute Mapping in the Dart Generator

**User Story:** As a Dart developer reviewing generated code, I want C# attributes translated to
their Dart annotation equivalents where a mapping exists, and preserved as structured comments
where no mapping exists, so that the generated code is both correct and transparent about gaps.
I also want to know when my custom mappings override built-in behavior, and when the same attribute
appears in more than one tier, so there are no silent surprises.

#### Acceptance Criteria

1. THE `Attribute_Mapper` SHALL resolve each `Attribute_Node` using a three-tier lookup in the following priority order: (1) Custom_Mapping from `Mapping_Config.attribute_mappings`, (2) Package_Mapping derived from the NuGet package entry in `Mapping_Config.package_mappings`, (3) Known_Mapping from the built-in table. The first tier that contains a match wins; lower tiers are not consulted.
2. WHEN a Known_Mapping, Package_Mapping, or Custom_Mapping is found, THE `Attribute_Mapper` SHALL emit the corresponding Dart annotation expression immediately before the annotated declaration.
3. WHEN no mapping is found for an `Attribute_Node`, THE `Attribute_Mapper` SHALL emit a `// UNMAPPED ATTRIBUTE: [<ShortName>(<args>)]` comment immediately before the annotated declaration and SHALL emit a `CG` `Warning` diagnostic carrying the `FullyQualifiedName`, the target declaration's source location, and a message indicating the attribute was not mapped.
4. THE `Attribute_Mapper` SHALL NOT silently drop any `Attribute_Node`; every node MUST result in either a Dart annotation or an unmapped comment.
5. WHEN an `Attribute_Node` has `Target = Assembly` or `Target = Module`, THE `Attribute_Mapper` SHALL emit the annotation or unmapped comment at the top of the generated barrel file (`lib/<package_name>.dart`), before any `export` directives.
6. WHEN an `Attribute_Node` has `Target = ReturnValue`, THE `Attribute_Mapper` SHALL emit the annotation or unmapped comment on the line immediately preceding the method's return type in the generated Dart method signature, using a `// RETURN VALUE ATTRIBUTE:` prefix for unmapped cases.
7. THE `Attribute_Mapper` SHALL process multiple attributes on the same declaration in the same order as the `Attribute_Node` list on the IR node (source-declaration order).
8. WHEN a Custom_Mapping entry matches an `Attribute_Node` whose `FullyQualifiedName` also appears in a Package_Mapping or Known_Mapping, THE `Attribute_Mapper` SHALL emit a `CG` `Info` diagnostic stating that the Custom_Mapping overrides the lower-tier mapping, identifying the winning tier, the shadowed tier, and the `FullyQualifiedName`. This diagnostic is informational only and SHALL NOT prevent emission.
9. WHEN a Package_Mapping entry (populated by the NuGet_Handler) matches an `Attribute_Node` whose `FullyQualifiedName` also appears in the Known_Mapping table, THE `Attribute_Mapper` SHALL emit a `CG` `Info` diagnostic stating that the Package_Mapping overrides the Known_Mapping, identifying both tiers and the `FullyQualifiedName`. This diagnostic is informational only and SHALL NOT prevent emission.
10. WHEN the same `FullyQualifiedName` appears in more than one tier (Custom, Package, or Known), THE `Attribute_Mapper` SHALL emit exactly one cross-tier collision diagnostic per unique `FullyQualifiedName` per pipeline run, regardless of how many `Attribute_Node` instances carry that name (no duplicate collision diagnostics).

---

### Requirement 4: Built-in Known Attribute Mappings

**User Story:** As a Dart developer, I want well-known C# attributes automatically translated to
their Dart equivalents without any configuration, so that common patterns like `[Obsolete]` and
`[JsonProperty]` just work out of the box.

> **Tier placement note:** The Known_Mapping table covers only BCL and language-level attributes
> that have no associated NuGet package. Attributes from packages that the NuGet_Handler already
> handles (e.g., `Newtonsoft.Json`, `System.Text.Json`, `xunit`, `NUnit`, `MSTest`) are
> intentionally absent from this table; their mappings live exclusively in the Package tier
> (Requirement 9). Placing the same attribute in both tiers would create a cross-tier collision
> (see Requirement 3.9) and is therefore avoided by design.

#### Acceptance Criteria

1. THE `Attribute_Mapper` SHALL include the following built-in Known_Mappings:

   | C# Attribute (fully qualified) | Dart Annotation | Notes |
   |---|---|---|
   | `System.ObsoleteAttribute` | `@Deprecated('<message>')` | `message` from first positional arg; default `'Deprecated'` if absent |
   | `System.SerializableAttribute` | `// UNMAPPED ATTRIBUTE: [Serializable]` + `CG` `Info` | No Dart equivalent; info-level only |
   | `System.FlagsAttribute` | `// UNMAPPED ATTRIBUTE: [Flags]` + `CG` `Info` | No Dart equivalent; info-level only |
   | `System.ComponentModel.DataAnnotations.RequiredAttribute` | `// UNMAPPED ATTRIBUTE: [Required]` + `CG` `Warning` | Requires `package:freezed` or user mapping; handled here because DataAnnotations is a BCL namespace with no separate NuGet package tier entry |

2. WHEN a Known_Mapping requires a Dart package import (e.g., `json_annotation`), THE `Attribute_Mapper` SHALL add the corresponding `import` directive to the generated file and SHALL add the package to `pubspec.yaml` `dependencies` if not already present.
3. THE built-in Known_Mapping table SHALL be versioned and documented; additions SHALL NOT be breaking changes.
4. WHEN a Known_Mapping maps to `@Deprecated`, THE `Attribute_Mapper` SHALL use the first positional argument of the `Attribute_Node` as the deprecation message string; IF no positional argument is present, THE `Attribute_Mapper` SHALL emit `@Deprecated('Deprecated')`.

---

### Requirement 5: Package-Level Attribute Mappings

**User Story:** As a pipeline integrator, I want attribute mappings for NuGet packages to be
derivable from the existing package mapping configuration, so that adding a new NuGet → Dart
package mapping automatically brings its attribute mappings along.

#### Acceptance Criteria

1. THE `Mapping_Config.package_mappings` schema SHALL be extended to allow each package entry to carry an optional `attribute_mappings` sub-map, where each key is a fully-qualified C# attribute name and each value is a Dart annotation template string.
2. WHEN the `Attribute_Mapper` resolves a Package_Mapping, it SHALL look up the `Attribute_Node.FullyQualifiedName` in the `attribute_mappings` sub-map of the matching package entry in `Mapping_Config.package_mappings`.
3. WHEN a Package_Mapping template string contains `{0}`, `{1}`, ... placeholders, THE `Attribute_Mapper` SHALL substitute them with the string representations of the `Attribute_Node.PositionalArguments` in order.
4. WHEN a Package_Mapping template string contains `{<name>}` placeholders, THE `Attribute_Mapper` SHALL substitute them with the string representation of the matching `Attribute_Node.NamedArguments` entry.
5. IF a placeholder references a positional or named argument that is absent from the `Attribute_Node`, THE `Attribute_Mapper` SHALL substitute an empty string and emit a `CG` `Warning` diagnostic identifying the missing argument.
6. THE `Attribute_Mapper` SHALL add any Dart package imports required by Package_Mapping annotations to the generated file and `pubspec.yaml`, using the same mechanism as Known_Mappings (Requirement 4.2).

---

### Requirement 6: Custom Attribute Mappings via `transpiler.yaml`

**User Story:** As a developer with internal C# attributes, I want to define custom attribute
mappings in `transpiler.yaml`, so that my organization's attributes are translated to Dart
annotations without modifying the transpiler source.

#### Acceptance Criteria

1. THE Config_Service SHALL recognize a top-level `attribute_mappings` section in `transpiler.yaml` containing a map of fully-qualified C# attribute names to Dart annotation template strings.
2. THE Config_Service SHALL expose the parsed custom mappings via `IConfigService.attributeMappings` returning `Map<String, AttributeMappingRule>`, where `AttributeMappingRule` carries: `dartTemplate` (string), optional `requiredImports` (list of Dart import URIs), and optional `requiredPackages` (list of pub package names with version constraints).
3. WHEN `attribute_mappings` is absent from `transpiler.yaml`, `IConfigService.attributeMappings` SHALL return an empty map.
4. IF an `attribute_mappings` entry has a value that is not a string or a valid `AttributeMappingRule` object, THE Config_Service SHALL emit a `CFG` `Error` diagnostic identifying the offending key and halt pipeline initialization.
5. THE `Attribute_Mapper` SHALL apply Custom_Mappings with higher priority than both Package_Mappings and Known_Mappings, allowing users to override built-in behavior.
6. WHEN a Custom_Mapping `requiredImports` list is non-empty, THE `Attribute_Mapper` SHALL add those import directives to every generated file that emits the mapped annotation.
7. WHEN a Custom_Mapping `requiredPackages` list is non-empty, THE `Attribute_Mapper` SHALL add those packages to `pubspec.yaml` `dependencies` with the specified version constraints.
8. FOR ALL valid `transpiler.yaml` files, parsing then serializing the `attribute_mappings` section then parsing again SHALL produce a value-equal `attributeMappings` map (round-trip property).

---

### Requirement 7: Attribute Argument Emission

**User Story:** As a Dart developer reviewing generated code, I want attribute arguments emitted
correctly as Dart annotation arguments, so that the generated annotations carry the same semantic
payload as the original C# attributes.

#### Acceptance Criteria

1. THE `Attribute_Mapper` SHALL emit positional arguments of a mapped attribute as positional arguments of the Dart annotation constructor, in the same order as `Attribute_Node.PositionalArguments`.
2. THE `Attribute_Mapper` SHALL emit named arguments of a mapped attribute as named arguments of the Dart annotation constructor, using the name from `Attribute_Node.NamedArguments`.
3. WHEN an argument value is a string literal, THE `Attribute_Mapper` SHALL emit it as a Dart single-quoted string literal.
4. WHEN an argument value is a numeric literal, THE `Attribute_Mapper` SHALL emit it as a Dart numeric literal of the appropriate type (`int` or `double`).
5. WHEN an argument value is a boolean literal, THE `Attribute_Mapper` SHALL emit `true` or `false`.
6. WHEN an argument value is a `typeof(T)` expression (C# `Type` argument), THE `Attribute_Mapper` SHALL emit the Dart type name using the same `Type_Mapper` rules applied to all other type references.
7. WHEN an argument value is an enum member access (e.g., `NamingPolicy.CamelCase`), THE `Attribute_Mapper` SHALL emit the Dart equivalent enum value if a mapping exists, or emit a `// UNMAPPED ENUM ARG: <value>` inline comment and a `CG` `Warning` diagnostic if no mapping exists.
8. WHEN an argument value is an `UnsupportedNode` placeholder (from IR_Builder Requirement 1.9), THE `Attribute_Mapper` SHALL emit a `/* UNSUPPORTED ARG */` inline comment in place of the argument value and propagate the existing `IR` `Warning` diagnostic.
9. WHEN a mapping template is used (Package_Mapping or Custom_Mapping), argument substitution SHALL take precedence over direct argument emission; the template string is the authoritative output for that annotation.

---

### Requirement 8: Attribute Target Filtering

**User Story:** As a Dart developer, I want attributes that have no meaningful Dart target to be
handled gracefully, so that the generated code does not contain syntactically invalid annotations.

#### Acceptance Criteria

1. WHEN an `Attribute_Node` has `Target = Assembly` or `Target = Module` and no mapping exists, THE `Attribute_Mapper` SHALL emit the unmapped comment at the top of the barrel file and SHALL NOT attempt to emit it on any individual declaration.
2. WHEN an `Attribute_Node` has `Target = ReturnValue` and the mapped Dart annotation is not valid on a Dart method return type, THE `Attribute_Mapper` SHALL emit the annotation as a comment with a `CG` `Warning` diagnostic noting the invalid target.
3. WHEN a Custom_Mapping or Package_Mapping specifies a `targetFilter` list of allowed `Attribute_Target` values, THE `Attribute_Mapper` SHALL only emit the annotation when the `Attribute_Node.Target` is in that list; for non-matching targets it SHALL emit the unmapped comment and a `CG` `Warning` diagnostic.
4. THE `Attribute_Mapper` SHALL never emit a Dart annotation in a syntactic position that would cause a `dart analyze` error; IF the only valid emission is a comment, it SHALL emit a comment.

---

### Requirement 9: Integration with the NuGet Handler

**User Story:** As a pipeline integrator, I want attribute mappings for NuGet packages to be
automatically available when the NuGet handler resolves a package, so that no manual configuration
is needed for well-known packages.

#### Acceptance Criteria

1. WHEN the NuGet_Handler resolves a package to a Dart equivalent and that package has a known attribute mapping table, THE NuGet_Handler SHALL populate the `attribute_mappings` sub-map of the corresponding `Mapping_Config.package_mappings` entry before the IR_Builder runs.
2. THE NuGet_Handler SHALL include built-in attribute mapping tables for the following packages: `Newtonsoft.Json`, `System.Text.Json` (BCL), `System.ComponentModel.DataAnnotations` (BCL), `Microsoft.EntityFrameworkCore` (partial), `xunit`, `NUnit`, `MSTest`.
3. WHEN a NuGet package has no built-in attribute mapping table and no user-supplied `attribute_mappings` sub-map, THE NuGet_Handler SHALL NOT emit any diagnostic for the missing attribute mappings; the `Attribute_Mapper` will handle unmapped attributes at generation time.
4. THE NuGet_Handler SHALL record in `Gen_Result.Diagnostics` at `Info` severity which packages contributed attribute mapping tables to `Mapping_Config`, so that the mapping report is complete.

---

### Requirement 10: Diagnostics

**User Story:** As a transpiler user, I want clear, actionable diagnostics for every attribute
mapping decision, so that I know exactly which attributes were mapped, which were not, and what
configuration I need to add to handle the gaps. I also want to be told when my custom mappings
override built-in behavior, or when the same attribute appears in more than one tier.

#### Acceptance Criteria

1. THE IR_Builder SHALL use diagnostic codes in the range `IR0001`–`IR9999` for all attribute-related IR diagnostics; no new prefix is introduced.
2. THE `Attribute_Mapper` SHALL use diagnostic codes in the range `CG0001`–`CG9999` for all attribute-related code generation diagnostics.
3. THE Config_Service SHALL use diagnostic codes in the range `CFG0001`–`CFG9999` for all `attribute_mappings` configuration diagnostics.
4. FOR EACH `Attribute_Node` that results in an Unmapped_Attribute comment, THE `Attribute_Mapper` SHALL emit exactly one `CG` `Warning` diagnostic carrying: the `FullyQualifiedName`, the target declaration name, the source file path, and a suggestion to add a Custom_Mapping in `transpiler.yaml`.
5. THE `Attribute_Mapper` SHALL NOT emit duplicate diagnostics for the same `FullyQualifiedName` and target declaration.
6. WHEN a Known_Mapping, Package_Mapping, or Custom_Mapping is successfully applied, THE `Attribute_Mapper` SHALL emit a `CG` `Info` diagnostic recording the mapping decision (from-attribute, to-annotation, mapping tier) so that the mapping report is complete.
7. THE `Attribute_Mapper` SHALL aggregate all diagnostics into `Gen_Result.Diagnostics` rather than writing to standard output or throwing exceptions.
8. WHEN a cross-tier collision is detected (the same `FullyQualifiedName` appears in more than one tier), THE `Attribute_Mapper` SHALL emit a `CG` `Info` diagnostic identifying: the `FullyQualifiedName`, the winning tier, the shadowed tier(s), and — when the winning tier is Custom — a note that the user's mapping is in effect. This diagnostic SHALL be emitted at most once per unique `FullyQualifiedName` per pipeline run.
9. THE `Attribute_Mapper` SHALL NOT emit a cross-tier collision diagnostic for `FullyQualifiedName` values that appear only in one tier; the diagnostic is only for genuine multi-tier overlaps.

---

### Requirement 11: Correctness Properties for Testing

**User Story:** As a transpiler test engineer, I want well-defined correctness properties for the
attribute mapping feature, so that I can write property-based tests that catch regressions across
a wide range of C# attribute inputs.

#### Acceptance Criteria

1. FOR ALL valid `Frontend_Result` inputs, the count of `Attribute_Node` instances in the IR SHALL equal the count of structured attribute records attached to declaration nodes in the `Normalized_SyntaxTree` by the Roslyn_Frontend (attribute count preservation property).
2. FOR ALL valid IR trees containing `Attribute_Node` instances, parsing the Pretty_Printer output SHALL produce an IR tree where every `Attribute_Node` is structurally and value-equal to the original (round-trip property).
3. FOR ALL `Attribute_Node` instances, THE `Attribute_Mapper` SHALL produce exactly one of: a Dart annotation string, or an unmapped comment string — never both and never neither (total mapping property).
4. FOR ALL `Attribute_Node` instances with a Known_Mapping, the generated Dart annotation SHALL be syntactically valid Dart (syntactic validity property).
5. FOR ALL `Attribute_Node` instances that result in an Unmapped_Attribute comment, exactly one `CG` `Warning` diagnostic SHALL be present in `Gen_Result.Diagnostics` for that node (diagnostic completeness property).
6. FOR ALL Custom_Mapping entries in `transpiler.yaml`, the `Attribute_Mapper` SHALL apply the Custom_Mapping in preference to any Known_Mapping or Package_Mapping for the same `FullyQualifiedName` (custom mapping priority property).
7. FOR ALL valid `transpiler.yaml` files containing an `attribute_mappings` section, parsing then serializing then parsing SHALL produce a value-equal `attributeMappings` map (config round-trip property).
8. FOR ALL `FullyQualifiedName` values that appear in more than one tier, exactly one cross-tier collision `CG` `Info` diagnostic SHALL be present in `Gen_Result.Diagnostics` per pipeline run, regardless of how many `Attribute_Node` instances carry that name (cross-tier collision deduplication property).
9. FOR ALL `FullyQualifiedName` values that appear in exactly one tier, no cross-tier collision diagnostic SHALL be present in `Gen_Result.Diagnostics` (no spurious collision diagnostic property).
