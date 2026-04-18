# Implementation Plan: Transpiler Configuration Service

## Overview

Implement the `Config_Service` for the C# → Dart transpiler in Dart. The service locates, parses, validates, and exposes `transpiler.yaml` to all pipeline modules via `IConfigService`. All I/O and validation happen eagerly at startup; accessors are pure getters thereafter.

## Tasks

- [x] 1. Define core data models and enums
  - Create `lib/src/config/models/` directory structure
  - Implement `DiagnosticSeverity` enum (`error`, `warning`, `info`)
  - Implement `LinqStrategy` enum (`preserveFunctional`, `lowerToLoops`) with YAML string mapping
  - Implement `EventStrategy` enum (`stream`) with YAML string mapping
  - Implement `CaseStyle` enum (`pascalCase`, `camelCase`, `snakeCase`, `screamingSnakeCase`) with YAML string mapping
  - Implement `SourceLocation` final class with `filePath`, `line`, `column` and value equality
  - Implement `ConfigDiagnostic` final class with `severity`, `code`, `message`, `location` and value equality
  - _Requirements: 2.2, 6.2, 7.1_

- [x] 2. Implement value objects and `ConfigObject`
  - [x] 2.1 Implement `NullabilityConfig`, `AsyncConfig`, `NamingConventions`, `EventMappingOverride`, `StructMappingOverride` with documented defaults and value equality (`==` / `hashCode`)
    - _Requirements: 4.1, 5.1, 6.1_
  - [x] 2.2 Implement `ConfigObject` final class with all 17 fields, `const` constructor with documented defaults, `ConfigObject.defaults` constant, and value equality
    - _Requirements: 2.2, 3.1, 3.5, 10.1_
  - [ ]* 2.3 Write unit tests for `ConfigObject` and value objects
    - Verify default constructor produces `ConfigObject.defaults`
    - Verify value equality for each value object type
    - _Requirements: 11.3, 4.1, 5.1, 6.1_

- [x] 3. Implement `IConfigService` interface and `ConfigService`
  - [x] 3.1 Define `IConfigService` abstract interface with all 18 pure getter accessors (17 config accessors + `config`)
    - _Requirements: 3.1, 3.2, 3.3_
  - [x] 3.2 Implement `ConfigService` final class that wraps `ConfigObject` and delegates all accessors
    - _Requirements: 3.1, 3.4_
  - [ ]* 3.3 Write unit tests for `ConfigService` accessor delegation
    - Verify each accessor returns the corresponding `ConfigObject` field value
    - _Requirements: 3.1, 3.2_

- [x] 4. Implement `ConfigParser`
  - [x] 4.1 Implement `ConfigParser.parse(content, sourcePath)` using the `yaml` package; return `YamlMap` on success or `CFG0002` `ConfigDiagnostic` on `YamlException` or non-map top-level document
    - _Requirements: 2.1, 2.3_
  - [ ]* 4.2 Write unit tests for `ConfigParser`
    - Test valid YAML returns a `YamlMap`
    - Test invalid YAML syntax emits `CFG0002` with correct line/column
    - Test non-mapping top-level document emits `CFG0002`
    - Test empty content returns empty `YamlMap`
    - _Requirements: 2.1, 2.3_

- [x] 5. Implement `ConfigValidator`
  - [x] 5.1 Implement top-level key validation: emit `CFG0010` Warning for unrecognized keys, `CFG0003` Error for type mismatches on recognized keys, `CFG0004` Error for invalid enum values (`linq_strategy`, `event_strategy`, `case_style` fields)
    - _Requirements: 2.4, 2.5, 10.4_
  - [x] 5.2 Implement section sub-validators for `nullability` (`CFG0011`), `async_behavior` (`CFG0012`), and `naming_conventions` (`CFG0013`) that emit Warning for unrecognized keys within each section
    - _Requirements: 4.3, 5.2, 6.3_
  - [x] 5.3 Implement deduplication: track `(code, location)` pairs in a `Set` and skip duplicate diagnostics before appending
    - _Requirements: 7.3_
  - [ ]* 5.4 Write unit tests for `ConfigValidator`
    - Test unrecognized top-level key emits `CFG0010` Warning and parsing continues
    - Test type mismatch on recognized key emits `CFG0003` Error
    - Test invalid `linq_strategy` value emits `CFG0004` Error
    - Test unrecognized key under `nullability` emits `CFG0011` Warning
    - Test unrecognized key under `async_behavior` emits `CFG0012` Warning
    - Test unrecognized key under `naming_conventions` emits `CFG0013` Warning
    - Test duplicate `(code, location)` pairs are deduplicated
    - _Requirements: 2.4, 2.5, 4.3, 5.2, 6.3, 7.3, 10.4_

- [x] 6. Implement `ConfigBuilder`
  - [x] 6.1 Implement `ConfigBuilder.build(validated)` that constructs a `ConfigObject` from the cleaned map, substituting `ConfigObject.defaults` values for all absent keys; handle nested section maps for `NullabilityConfig`, `AsyncConfig`, `NamingConventions`, `EventMappingOverride`, and `StructMappingOverride`
    - _Requirements: 2.2, 3.5, 4.1, 5.1, 6.1, 10.1, 10.2, 10.3_
  - [ ]* 6.2 Write unit tests for `ConfigBuilder`
    - Test empty map produces `ConfigObject.defaults`
    - Test `linq_strategy: lower_to_loops` maps to `LinqStrategy.lowerToLoops`
    - Test `linq_strategy: preserve_functional` maps to `LinqStrategy.preserveFunctional`
    - Test each section field is correctly mapped from YAML key to Dart field
    - Test `nuget_feeds` default is `["https://api.nuget.org/v3/index.json"]`
    - _Requirements: 3.5, 10.1, 10.2, 10.3_

- [x] 7. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Implement `ConfigObjectSerialization` extension and `ConfigLoadResult`
  - [x] 8.1 Implement `ConfigObjectSerialization` extension on `ConfigObject` with `toYamlMap()` that produces a `Map<String, dynamic>` covering all 17 fields with correct YAML key names (e.g., `async_behavior`, `package_mappings`, `nuget_feeds`, `experimental`)
    - _Requirements: 2.6, 9.4_
  - [x] 8.2 Implement `ConfigLoadResult` final class with `service` (`IConfigService?`), `config` (`ConfigObject?`), `diagnostics` (`List<ConfigDiagnostic>`), and `hasErrors` getter
    - _Requirements: 7.2, 7.4, 7.5, 9.1_
  - [ ]* 8.3 Write unit tests for `ConfigObjectSerialization`
    - Test `toYamlMap()` uses correct YAML key names for all fields
    - Test `toYamlMap()` on `ConfigObject.defaults` produces a map that round-trips to `ConfigObject.defaults`
    - _Requirements: 2.6, 9.4_

- [x] 9. Implement `ConfigLoader`
  - [x] 9.1 Implement `ConfigLoader.load({required entryPath, explicitConfigPath})` with the file discovery algorithm: explicit path check (emit `CFG0001` if missing), then walk from entry-point directory up to filesystem root, then fall back to defaults with `CFG0020` Info diagnostic
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_
  - [x] 9.2 Wire the full pipeline inside `ConfigLoader.load`: `ConfigParser.parse` → `ConfigValidator.validate` → `ConfigBuilder.build` → construct `ConfigService` → return `ConfigLoadResult`; set `service` to null when `hasErrors` is true
    - _Requirements: 7.2, 7.4, 7.5, 9.1, 9.3_
  - [ ]* 9.3 Write unit tests for `ConfigLoader`
    - Test explicit `--config` path that does not exist emits `CFG0001` and `service` is null
    - Test no `transpiler.yaml` found returns default `ConfigObject` and `CFG0020` Info
    - Test `transpiler.yaml` found in parent directory is loaded correctly
    - Test `ConfigLoadResult.service` is null when any Error diagnostic is present
    - Test `ConfigLoadResult.service` is non-null when only Warning/Info diagnostics present
    - Test `Load_Result.Config` equals the `ConfigObject` returned by `IConfigService.config`
    - _Requirements: 1.2, 1.3, 1.4, 1.5, 7.4, 7.5, 9.1, 9.2, 9.3_

- [x] 10. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 11. Implement property-based test generators
  - Create `test/config/generators/config_generators.dart`
  - Implement `validConfigObject()` — `Arbitrary<ConfigObject>` generating random valid `ConfigObject` instances covering all fields and enum variants
  - Implement `validYamlContent()` — `Arbitrary<String>` generating valid `transpiler.yaml` content strings from random `ConfigObject` instances via `toYamlMap()`
  - Implement `recognizedKeySubset()` — `Arbitrary<Set<String>>` generating random non-empty subsets of the 17 recognized top-level YAML keys
  - Implement `invalidLinqStrategyValue()` — `Arbitrary<String>` generating strings that are not `"lower_to_loops"` or `"preserve_functional"`
  - Implement `unknownTopLevelKey()` — `Arbitrary<String>` generating strings that are not recognized top-level keys
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

- [x] 12. Write property-based tests
  - Create `test/config/config_properties_test.dart`
  - [ ]* 12.1 Write property test for Property 1: Config round-trip
    - For any valid `ConfigObject`, `toYamlMap()` → serialize → parse → `ConfigBuilder.build` SHALL produce a value-equal `ConfigObject`
    - **Property 1: Config round-trip**
    - **Validates: Requirements 2.6, 9.4**
  - [ ]* 12.2 Write property test for Property 2: Parsing determinism
    - For any valid YAML content string, parsing twice SHALL produce value-equal `ConfigObject` instances
    - **Property 2: Parsing determinism**
    - **Validates: Requirement 11.2**
  - [ ]* 12.3 Write property test for Property 3: Default values for absent keys
    - For any subset of recognized keys, a YAML omitting those keys SHALL produce a `ConfigObject` where each omitted key's accessor returns the documented default
    - **Property 3: Default values for absent keys**
    - **Validates: Requirements 11.3, 10.1, 10.2, 10.3**
  - [ ]* 12.4 Write property test for Property 4: Clean config produces no errors or warnings
    - For any valid `ConfigObject`, serializing and re-parsing SHALL produce zero `Error` or `Warning` diagnostics
    - **Property 4: Clean config produces no errors or warnings**
    - **Validates: Requirements 11.4, 11.5**
  - [ ]* 12.5 Write property test for Property 5: No duplicate diagnostics
    - For any YAML content, the diagnostics list SHALL contain no two entries with the same `(code, location)` pair
    - **Property 5: No duplicate diagnostics**
    - **Validates: Requirement 7.3**
  - [ ]* 12.6 Write property test for Property 6: Invalid enum value produces CFG0004
    - For any string not in `{"lower_to_loops", "preserve_functional"}`, a YAML with that `linq_strategy` value SHALL produce a `CFG0004` Error diagnostic
    - **Property 6: Invalid enum value produces CFG0004**
    - **Validates: Requirement 10.4**
  - [ ]* 12.7 Write property test for Property 7: Unrecognized top-level key produces CFG0010 Warning
    - For any string not in the recognized key set, a YAML containing that key SHALL produce a `CFG0010` Warning and no Error solely from the unknown key
    - **Property 7: Unrecognized top-level key produces CFG0010 Warning**
    - **Validates: Requirement 2.5**
  - [ ]* 12.8 Write property test for Property 8: Type safety of all accessors
    - For any valid `ConfigObject`, constructing a `ConfigService` and calling all 18 accessors SHALL not throw and SHALL return non-null values of the documented types
    - **Property 8: Type safety of all accessors**
    - **Validates: Requirement 11.1**

- [x] 13. Register `IConfigService` in DI container
  - Add `IConfigService` singleton registration in the pipeline bootstrap function using `get_it` (or equivalent)
  - Ensure `ConfigLoader.load` is called before any pipeline module is constructed and `result.service` is registered only when `hasErrors` is false
  - _Requirements: 3.3, 3.4_

- [x] 14. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Property tests use `package:fast_check` or `package:glados`; each test runs a minimum of 100 iterations
- Each property test file includes a comment: `// Feature: transpiler-configuration, Property N: <property text>`
- `ConfigLoader` never throws — all errors are captured as `ConfigDiagnostic` entries in `ConfigLoadResult`
- The CLI layer (not `Config_Service`) is responsible for rendering diagnostics to the terminal
