// Feature: transpiler-configuration
// Property-based tests for the Config_Service.
// Each test runs 100 iterations with deterministic seeds for reproducibility.

import 'dart:math';

import 'package:test/test.dart';

import 'package:cs2dart/src/config/config_builder.dart';
import 'package:cs2dart/src/config/config_parser.dart';
import 'package:cs2dart/src/config/config_service.dart';
import 'package:cs2dart/src/config/config_validator.dart';
import 'package:cs2dart/src/config/models/models.dart';
import 'package:cs2dart/src/config/config_object_serialization.dart';

import 'generators/config_generators.dart';

// ---------------------------------------------------------------------------
// forAll helper
// ---------------------------------------------------------------------------

/// Runs [property] for [iterations] deterministic seeds.
///
/// Each iteration creates a fresh [Random] seeded with the iteration index,
/// generates a value via [generator], and passes it to [property].
void forAll<T>(
  T Function(Random) generator,
  void Function(T) property, {
  int iterations = 100,
}) {
  for (var i = 0; i < iterations; i++) {
    final random = Random(i);
    final value = generator(random);
    property(value);
  }
}

// ---------------------------------------------------------------------------
// Pipeline helpers
// ---------------------------------------------------------------------------

/// Runs the full parse → validate → build pipeline on [content].
///
/// Returns the [ConfigObject] on success, or throws if parsing fails.
ConfigObject _buildFromYaml(String content) {
  final parsed = ConfigParser.parse(content, 'test.yaml');
  if (parsed.map == null) {
    throw StateError('Parse failed: ${parsed.error?.message}');
  }
  final validated = ConfigValidator.validate(parsed.map!, 'test.yaml');
  return ConfigBuilder.build(validated.cleaned);
}

/// Returns all diagnostics produced by the full parse → validate pipeline.
List<ConfigDiagnostic> _diagnosticsFromYaml(String content) {
  final parsed = ConfigParser.parse(content, 'test.yaml');
  if (parsed.error != null) return [parsed.error!];
  if (parsed.map == null) return [];
  final validated = ConfigValidator.validate(parsed.map!, 'test.yaml');
  return validated.diagnostics;
}

// ---------------------------------------------------------------------------
// Property 3 helper: map YAML key name → ConfigObject field value
// ---------------------------------------------------------------------------

/// Returns the value of the field in [obj] that corresponds to the given
/// top-level YAML [key].
dynamic _fieldForKey(ConfigObject obj, String key) {
  return switch (key) {
    'linq_strategy' => obj.linqStrategy,
    'nullability' => obj.nullability,
    'async_behavior' => obj.asyncBehavior,
    'namespace_mappings' => obj.namespaceMappings,
    'root_namespace' => obj.rootNamespace,
    'barrel_files' => obj.barrelFiles,
    'namespace_prefix_aliases' => obj.namespacePrefixAliases,
    'auto_resolve_conflicts' => obj.autoResolveConflicts,
    'event_strategy' => obj.eventStrategy,
    'event_mappings' => obj.eventMappings,
    'package_mappings' => obj.packageMappings,
    'sdk_path' => obj.sdkPath,
    'nuget_feeds' => obj.nugetFeedUrls,
    'library_mappings' => obj.libraryMappings,
    'struct_mappings' => obj.structMappings,
    'naming_conventions' => obj.namingConventions,
    'experimental' => obj.experimentalFeatures,
    _ => throw ArgumentError('Unknown key: $key'),
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Property 1: Config round-trip
  // Feature: transpiler-configuration, Property 1: Config round-trip
  // For any valid ConfigObject, toYamlMap() → serialize → parse →
  // ConfigBuilder.build SHALL produce a value-equal ConfigObject.
  // Validates: Requirements 2.6, 9.4
  // -------------------------------------------------------------------------
  test(
    'Property 1: Config round-trip — serialize then parse produces value-equal ConfigObject',
    () {
      forAll(validConfigObject, (original) {
        final map = original.toYamlMap();
        final content = mapToYamlString(map);
        final rebuilt = _buildFromYaml(content);
        expect(
          rebuilt,
          equals(original),
          reason: 'Round-trip failed for seed-generated ConfigObject',
        );
      });
    },
  );

  // -------------------------------------------------------------------------
  // Property 2: Parsing determinism
  // Feature: transpiler-configuration, Property 2: Parsing determinism
  // For any valid YAML content string, parsing twice SHALL produce
  // value-equal ConfigObject instances.
  // Validates: Requirement 11.2
  // -------------------------------------------------------------------------
  test(
    'Property 2: Parsing determinism — parsing same content twice yields equal ConfigObjects',
    () {
      forAll(validYamlContent, (content) {
        final first = _buildFromYaml(content);
        final second = _buildFromYaml(content);
        expect(
          first,
          equals(second),
          reason: 'Parsing the same YAML content twice produced different results',
        );
      });
    },
  );

  // -------------------------------------------------------------------------
  // Property 3: Default values for absent keys
  // Feature: transpiler-configuration, Property 3: Default values for absent keys
  // For any subset of recognized keys, a YAML omitting those keys SHALL
  // produce a ConfigObject where each omitted key's accessor returns the
  // documented default.
  // Validates: Requirements 11.3, 10.1, 10.2, 10.3
  // -------------------------------------------------------------------------
  test(
    'Property 3: Default values for absent keys — omitted keys return documented defaults',
    () {
      forAll(recognizedKeySubset, (omittedKeys) {
        // Start from the defaults map and remove the omitted keys.
        final baseMap = ConfigObject.defaults.toYamlMap();
        for (final key in omittedKeys) {
          baseMap.remove(key);
        }
        final content = mapToYamlString(baseMap);
        final config = _buildFromYaml(content);

        for (final key in omittedKeys) {
          final actual = _fieldForKey(config, key);
          final expected = _fieldForKey(ConfigObject.defaults, key);
          expect(
            actual,
            equals(expected),
            reason: 'Omitted key "$key" did not return its documented default',
          );
        }
      });
    },
  );

  // -------------------------------------------------------------------------
  // Property 4: Clean config produces no errors or warnings
  // Feature: transpiler-configuration, Property 4: Clean config produces no errors or warnings
  // For any valid ConfigObject, serializing and re-parsing SHALL produce
  // zero Error or Warning diagnostics.
  // Validates: Requirements 11.4, 11.5
  // -------------------------------------------------------------------------
  test(
    'Property 4: Clean config produces no errors or warnings',
    () {
      forAll(validConfigObject, (obj) {
        final content = mapToYamlString(obj.toYamlMap());
        final diagnostics = _diagnosticsFromYaml(content);
        final errorsOrWarnings = diagnostics.where(
          (d) =>
              d.severity == DiagnosticSeverity.error ||
              d.severity == DiagnosticSeverity.warning,
        );
        expect(
          errorsOrWarnings,
          isEmpty,
          reason: 'Valid config produced unexpected diagnostics: '
              '${errorsOrWarnings.map((d) => '${d.code}: ${d.message}').join(', ')}',
        );
      });
    },
  );

  // -------------------------------------------------------------------------
  // Property 5: No duplicate diagnostics
  // Feature: transpiler-configuration, Property 5: No duplicate diagnostics
  // For any YAML content, the diagnostics list SHALL contain no two entries
  // with the same (code, location) pair.
  // Validates: Requirement 7.3
  // -------------------------------------------------------------------------
  test(
    'Property 5: No duplicate diagnostics — (code, location) pairs are unique',
    () {
      forAll(validYamlContent, (content) {
        final diagnostics = _diagnosticsFromYaml(content);
        final seen = <(String, SourceLocation?)>{};
        for (final d in diagnostics) {
          final key = (d.code, d.location);
          expect(
            seen.contains(key),
            isFalse,
            reason: 'Duplicate diagnostic found: code=${d.code}, '
                'location=${d.location?.filePath}:${d.location?.line}',
          );
          seen.add(key);
        }
      });
    },
  );

  // -------------------------------------------------------------------------
  // Property 6: Invalid enum value produces CFG0004
  // Feature: transpiler-configuration, Property 6: Invalid enum value produces CFG0004
  // For any string not in {"lower_to_loops", "preserve_functional"}, a YAML
  // with that linq_strategy value SHALL produce a CFG0004 Error diagnostic.
  // Validates: Requirement 10.4
  // -------------------------------------------------------------------------
  test(
    'Property 6: Invalid enum value produces CFG0004 — unrecognized linq_strategy emits CFG0004 Error',
    () {
      forAll(invalidLinqStrategyValue, (badValue) {
        final content = 'linq_strategy: $badValue\n';
        final diagnostics = _diagnosticsFromYaml(content);
        final cfg0004Errors = diagnostics.where(
          (d) =>
              d.code == 'CFG0004' && d.severity == DiagnosticSeverity.error,
        );
        expect(
          cfg0004Errors,
          isNotEmpty,
          reason: 'Expected CFG0004 Error for linq_strategy value "$badValue"',
        );
      });
    },
  );

  // -------------------------------------------------------------------------
  // Property 7: Unrecognized top-level key produces CFG0010 Warning
  // Feature: transpiler-configuration, Property 7: Unrecognized top-level key produces CFG0010 Warning
  // For any string not in the recognized key set, a YAML containing that key
  // SHALL produce a CFG0010 Warning and no Error solely from the unknown key.
  // Validates: Requirement 2.5
  // -------------------------------------------------------------------------
  test(
    'Property 7: Unrecognized top-level key produces CFG0010 Warning',
    () {
      forAll(unknownTopLevelKey, (key) {
        final content = '$key: some_value\n';
        final diagnostics = _diagnosticsFromYaml(content);
        final cfg0010Warnings = diagnostics.where(
          (d) =>
              d.code == 'CFG0010' && d.severity == DiagnosticSeverity.warning,
        );
        expect(
          cfg0010Warnings,
          isNotEmpty,
          reason: 'Expected CFG0010 Warning for unknown key "$key"',
        );
        final hasErrors = diagnostics.any(
          (d) => d.severity == DiagnosticSeverity.error,
        );
        expect(
          hasErrors,
          isFalse,
          reason: 'Unknown key "$key" should not produce any Error diagnostics',
        );
      });
    },
  );

  // -------------------------------------------------------------------------
  // Property 8: Type safety of all accessors
  // Feature: transpiler-configuration, Property 8: Type safety of all accessors
  // For any valid ConfigObject, constructing a ConfigService and calling all
  // 18 accessors SHALL not throw and SHALL return non-null values of the
  // documented types (except nullable fields).
  // Validates: Requirement 11.1
  // -------------------------------------------------------------------------
  test(
    'Property 8: Type safety of all accessors — all 18 accessors return correct types without throwing',
    () {
      forAll(validConfigObject, (obj) {
        final service = ConfigService(obj);
        expect(
          () {
            // 17 config accessors + 1 config accessor = 18 total
            final linqStrategy = service.linqStrategy;
            final nullability = service.nullability;
            final asyncBehavior = service.asyncBehavior;
            final namespaceMappings = service.namespaceMappings;
            final rootNamespace = service.rootNamespace; // nullable
            final barrelFiles = service.barrelFiles;
            final namespacePrefixAliases = service.namespacePrefixAliases;
            final autoResolveConflicts = service.autoResolveConflicts;
            final eventStrategy = service.eventStrategy;
            final eventMappings = service.eventMappings;
            final packageMappings = service.packageMappings;
            final sdkPath = service.sdkPath; // nullable
            final nugetFeedUrls = service.nugetFeedUrls;
            final libraryMappings = service.libraryMappings;
            final structMappings = service.structMappings;
            final namingConventions = service.namingConventions;
            final experimentalFeatures = service.experimentalFeatures;
            final config = service.config;

            // Verify non-nullable accessors return non-null values
            expect(linqStrategy, isA<LinqStrategy>());
            expect(nullability, isA<NullabilityConfig>());
            expect(asyncBehavior, isA<AsyncConfig>());
            expect(namespaceMappings, isA<Map<String, String>>());
            expect(barrelFiles, isA<bool>());
            expect(namespacePrefixAliases, isA<Map<String, String>>());
            expect(autoResolveConflicts, isA<bool>());
            expect(eventStrategy, isA<EventStrategy>());
            expect(eventMappings, isA<Map<String, EventMappingOverride>>());
            expect(packageMappings, isA<Map<String, String>>());
            expect(nugetFeedUrls, isA<List<String>>());
            expect(libraryMappings, isA<Map<String, String>>());
            expect(structMappings, isA<Map<String, StructMappingOverride>>());
            expect(namingConventions, isA<NamingConventions>());
            expect(experimentalFeatures, isA<Map<String, bool>>());
            expect(config, isA<ConfigObject>());

            // Nullable accessors: just verify they don't throw
            // rootNamespace and sdkPath may be null — that's valid
            expect(rootNamespace, anyOf(isNull, isA<String>()));
            expect(sdkPath, anyOf(isNull, isA<String>()));
          },
          returnsNormally,
          reason: 'One or more ConfigService accessors threw unexpectedly',
        );
      });
    },
  );
}
