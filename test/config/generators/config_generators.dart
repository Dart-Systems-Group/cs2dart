// Feature: transpiler-configuration
// Generators for property-based tests.
// These functions take a [Random] instance and return randomly generated values
// suitable for use in property-based tests.

import 'dart:math';

import 'package:cs2dart/src/config/models/models.dart';
import 'package:cs2dart/src/config/config_object_serialization.dart';

/// The set of all recognized top-level YAML keys in transpiler.yaml.
const Set<String> kRecognizedTopLevelKeys = {
  'linq_strategy',
  'nullability',
  'async_behavior',
  'namespace_mappings',
  'root_namespace',
  'barrel_files',
  'namespace_prefix_aliases',
  'auto_resolve_conflicts',
  'event_strategy',
  'event_mappings',
  'package_mappings',
  'sdk_path',
  'nuget_feeds',
  'library_mappings',
  'struct_mappings',
  'naming_conventions',
  'experimental',
};

/// Valid YAML values for [LinqStrategy].
const Set<String> kValidLinqStrategyValues = {
  'preserve_functional',
  'lower_to_loops',
};

// ---------------------------------------------------------------------------
// Primitive helpers
// ---------------------------------------------------------------------------

/// Generates a random alphanumeric string of [length] characters.
String _randomAlphanumeric(Random random, int length) {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return String.fromCharCodes(
    List.generate(length, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
  );
}

/// Generates a random alphanumeric string with length in [minLen, maxLen].
String _randomString(Random random, {int minLen = 3, int maxLen = 12}) {
  final length = minLen + random.nextInt(maxLen - minLen + 1);
  return _randomAlphanumeric(random, length);
}

/// Generates a random small map of String → String (0–3 entries).
Map<String, String> _randomStringMap(Random random) {
  final count = random.nextInt(3); // 0, 1, or 2 entries
  final map = <String, String>{};
  for (var i = 0; i < count; i++) {
    map[_randomString(random)] = _randomString(random);
  }
  return map;
}

// ---------------------------------------------------------------------------
// Public generators
// ---------------------------------------------------------------------------

/// Generates a random valid [ConfigObject] covering all fields and enum variants.
///
/// Requirements: 11.1, 11.3, 11.4, 11.5
ConfigObject validConfigObject(Random random) {
  return ConfigObject(
    linqStrategy: LinqStrategy.values[random.nextInt(LinqStrategy.values.length)],
    nullability: NullabilityConfig(
      treatNullableAsOptional: random.nextBool(),
      emitNullAsserts: random.nextBool(),
      preserveNullableAnnotations: random.nextBool(),
    ),
    asyncBehavior: AsyncConfig(
      omitConfigureAwait: random.nextBool(),
      mapValueTaskToFuture: random.nextBool(),
    ),
    namespaceMappings: _randomStringMap(random),
    rootNamespace: random.nextBool() ? _randomString(random) : null,
    barrelFiles: random.nextBool(),
    namespacePrefixAliases: _randomStringMap(random),
    autoResolveConflicts: random.nextBool(),
    eventStrategy: EventStrategy.values[random.nextInt(EventStrategy.values.length)],
    eventMappings: const {}, // keep simple
    packageMappings: _randomStringMap(random),
    sdkPath: random.nextBool() ? _randomString(random) : null,
    nugetFeedUrls: [
      'https://api.nuget.org/v3/index.json',
      if (random.nextBool()) 'https://pkgs.dev.azure.com/${_randomString(random)}/index.json',
    ],
    libraryMappings: _randomStringMap(random),
    structMappings: const {}, // keep simple
    namingConventions: NamingConventions(
      classNameStyle: CaseStyle.values[random.nextInt(CaseStyle.values.length)],
      methodNameStyle: CaseStyle.values[random.nextInt(CaseStyle.values.length)],
      fieldNameStyle: CaseStyle.values[random.nextInt(CaseStyle.values.length)],
      fileNameStyle: CaseStyle.values[random.nextInt(CaseStyle.values.length)],
      privatePrefix: random.nextBool() ? '_' : '__',
    ),
    experimentalFeatures: _randomBoolMap(random),
  );
}

/// Generates a random small map of String → bool (0–2 entries).
Map<String, bool> _randomBoolMap(Random random) {
  final count = random.nextInt(3); // 0, 1, or 2 entries
  final map = <String, bool>{};
  for (var i = 0; i < count; i++) {
    map[_randomString(random)] = random.nextBool();
  }
  return map;
}

/// Generates a valid `transpiler.yaml` content string from a random [ConfigObject].
///
/// Uses [ConfigObject.toYamlMap] to obtain the map and then serializes it to
/// a YAML string using a simple recursive serializer (no external package needed).
///
/// Requirements: 11.2, 11.4
String validYamlContent(Random random) {
  final obj = validConfigObject(random);
  final map = obj.toYamlMap();
  return mapToYamlString(map);
}

/// Generates a random non-empty subset of [kRecognizedTopLevelKeys].
///
/// Requirements: 11.3
Set<String> recognizedKeySubset(Random random) {
  final keys = kRecognizedTopLevelKeys.toList();
  // Shuffle and take between 1 and all keys
  keys.shuffle(random);
  final count = 1 + random.nextInt(keys.length);
  return keys.take(count).toSet();
}

/// Generates a string that is NOT a valid [LinqStrategy] YAML value.
///
/// The result is guaranteed to not be `"preserve_functional"` or `"lower_to_loops"`.
///
/// Requirements: 11.5 (via Property 6)
String invalidLinqStrategyValue(Random random) {
  String candidate;
  do {
    candidate = _randomString(random, minLen: 3, maxLen: 20);
  } while (kValidLinqStrategyValues.contains(candidate));
  return candidate;
}

/// Generates a string that is NOT a recognized top-level key.
///
/// The result is guaranteed to not be in [kRecognizedTopLevelKeys].
///
/// Requirements: 11.4 (via Property 7)
String unknownTopLevelKey(Random random) {
  String candidate;
  do {
    candidate = _randomString(random, minLen: 3, maxLen: 20);
  } while (kRecognizedTopLevelKeys.contains(candidate));
  return candidate;
}

// ---------------------------------------------------------------------------
// YAML serialization helper
// ---------------------------------------------------------------------------

/// Converts a [Map<String, dynamic>] to a YAML string.
///
/// Handles nested maps, lists, booleans, strings, and null values.
/// This is a minimal implementation sufficient for round-trip testing of
/// [ConfigObject.toYamlMap] output.
String mapToYamlString(Map<String, dynamic> map, {int indent = 0}) {
  final buffer = StringBuffer();
  final prefix = '  ' * indent;
  for (final entry in map.entries) {
    final value = entry.value;
    if (value == null) {
      // Skip null values — absent keys use defaults
      continue;
    } else if (value is Map<String, dynamic>) {
      if (value.isEmpty) {
        buffer.writeln('$prefix${entry.key}: {}');
      } else {
        buffer.writeln('$prefix${entry.key}:');
        buffer.write(mapToYamlString(value, indent: indent + 1));
      }
    } else if (value is Map) {
      // Handle Map<String, String> etc.
      final typed = value.cast<String, dynamic>();
      if (typed.isEmpty) {
        buffer.writeln('$prefix${entry.key}: {}');
      } else {
        buffer.writeln('$prefix${entry.key}:');
        buffer.write(mapToYamlString(typed, indent: indent + 1));
      }
    } else if (value is List) {
      if (value.isEmpty) {
        buffer.writeln('$prefix${entry.key}: []');
      } else {
        buffer.writeln('$prefix${entry.key}:');
        for (final item in value) {
          buffer.writeln('$prefix  - ${_yamlScalar(item)}');
        }
      }
    } else {
      buffer.writeln('$prefix${entry.key}: ${_yamlScalar(value)}');
    }
  }
  return buffer.toString();
}

/// Formats a scalar value for YAML output.
String _yamlScalar(dynamic value) {
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) return value.toString();
  if (value is String) {
    // Quote strings that could be misinterpreted by YAML parsers
    if (_needsQuoting(value)) {
      return '"${value.replaceAll('"', '\\"')}"';
    }
    return value;
  }
  return value.toString();
}

/// Returns true if a string value needs YAML quoting.
bool _needsQuoting(String value) {
  if (value.isEmpty) return true;
  // Quote if it looks like a YAML special value or contains special chars
  const specialValues = {'true', 'false', 'null', 'yes', 'no', 'on', 'off'};
  if (specialValues.contains(value.toLowerCase())) return true;
  // Quote if it starts with special YAML characters
  if (RegExp(r'^[{}\[\]#&*!|>''"%@`]').hasMatch(value)) return true;
  // Quote if it contains a colon followed by a space (YAML key indicator)
  if (value.contains(': ')) return true;
  // Quote if it looks like a number (integer or float) — YAML would parse it as num
  if (RegExp(r'^-?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$').hasMatch(value)) return true;
  // Quote if it looks like a YAML integer with leading zeros or hex/octal
  if (RegExp(r'^0[xXoObB]').hasMatch(value)) return true;
  return false;
}
