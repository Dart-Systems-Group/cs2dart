import 'package:yaml/yaml.dart';

import 'models/models.dart';

/// Validates a raw [YamlMap] against the transpiler configuration schema.
///
/// Returns a [cleaned] map containing only recognized keys with valid
/// types/values, and a [diagnostics] list of all issues found.
///
/// Diagnostic codes emitted:
/// - `CFG0003` Error: type mismatch on a recognized key
/// - `CFG0004` Error: invalid enum value for `linq_strategy` or `event_strategy`
/// - `CFG0010` Warning: unrecognized top-level key
/// - `CFG0011` Warning: unrecognized key under `nullability`
/// - `CFG0012` Warning: unrecognized key under `async_behavior`
/// - `CFG0013` Warning: unrecognized key under `naming_conventions`
final class ConfigValidator {
  /// Recognized top-level keys and their expected Dart runtime types.
  static const _topLevelSchema = <String, _KeySpec>{
    'linq_strategy': _KeySpec(type: _ValueType.string, isEnum: true),
    'nullability': _KeySpec(type: _ValueType.map),
    'async_behavior': _KeySpec(type: _ValueType.map),
    'namespace_mappings': _KeySpec(type: _ValueType.map),
    'root_namespace': _KeySpec(type: _ValueType.string, nullable: true),
    'barrel_files': _KeySpec(type: _ValueType.bool),
    'namespace_prefix_aliases': _KeySpec(type: _ValueType.map),
    'auto_resolve_conflicts': _KeySpec(type: _ValueType.bool),
    'event_strategy': _KeySpec(type: _ValueType.string, isEnum: true),
    'event_mappings': _KeySpec(type: _ValueType.map),
    'package_mappings': _KeySpec(type: _ValueType.map),
    'sdk_path': _KeySpec(type: _ValueType.string, nullable: true),
    'nuget_feeds': _KeySpec(type: _ValueType.list),
    'library_mappings': _KeySpec(type: _ValueType.map),
    'struct_mappings': _KeySpec(type: _ValueType.map),
    'naming_conventions': _KeySpec(type: _ValueType.map),
    'experimental': _KeySpec(type: _ValueType.map),
  };

  static const _nullabilityKeys = {
    'treat_nullable_as_optional',
    'emit_null_asserts',
    'preserve_nullable_annotations',
  };

  static const _asyncBehaviorKeys = {
    'omit_configure_await',
    'map_value_task_to_future',
  };

  static const _namingConventionsKeys = {
    'class_name_style',
    'method_name_style',
    'field_name_style',
    'file_name_style',
    'private_prefix',
  };

  static const _validLinqStrategies = {'preserve_functional', 'lower_to_loops'};
  static const _validEventStrategies = {'stream', 'callback'};

  /// Validates [raw] against the schema.
  ///
  /// [sourcePath] is used to populate [SourceLocation] in diagnostics.
  /// Returns a record with:
  /// - [cleaned]: map of recognized keys with valid types/values only
  /// - [diagnostics]: all issues found during validation
  static ({Map<String, dynamic> cleaned, List<ConfigDiagnostic> diagnostics})
      validate(YamlMap raw, String sourcePath) {
    final diagnostics = <ConfigDiagnostic>[];
    final cleaned = <String, dynamic>{};

    // Deduplication set: (code, location) pairs already emitted.
    final seen = <(String, SourceLocation?)>{};

    void emit(ConfigDiagnostic d) {
      final key = (d.code, d.location);
      if (seen.contains(key)) return;
      seen.add(key);
      diagnostics.add(d);
    }

    for (final rawKey in raw.keys) {
      final key = rawKey.toString();
      final location = _locationFor(raw, rawKey, sourcePath);

      final spec = _topLevelSchema[key];
      if (spec == null) {
        // Unrecognized top-level key → CFG0010 Warning
        emit(ConfigDiagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'CFG0010',
          message: 'Unrecognized top-level key: "$key"',
          location: location,
        ));
        continue;
      }

      final value = raw[rawKey];

      // Null is allowed for nullable keys; skip type check.
      if (value == null && spec.nullable) {
        cleaned[key] = null;
        continue;
      }

      // Type check
      if (!spec.matches(value)) {
        emit(ConfigDiagnostic(
          severity: DiagnosticSeverity.error,
          code: 'CFG0003',
          message:
              'Type mismatch for key "$key": expected ${spec.typeName}, '
              'got ${value.runtimeType}',
          location: location,
        ));
        continue;
      }

      // Enum validation
      if (spec.isEnum) {
        final strVal = value as String;
        if (key == 'linq_strategy' && !_validLinqStrategies.contains(strVal)) {
          emit(ConfigDiagnostic(
            severity: DiagnosticSeverity.error,
            code: 'CFG0004',
            message:
                'Invalid value "$strVal" for "linq_strategy". '
                'Expected one of: ${_validLinqStrategies.join(', ')}',
            location: location,
          ));
          continue;
        }
        if (key == 'event_strategy' && !_validEventStrategies.contains(strVal)) {
          emit(ConfigDiagnostic(
            severity: DiagnosticSeverity.error,
            code: 'CFG0004',
            message:
                'Invalid value "$strVal" for "event_strategy". '
                'Expected one of: ${_validEventStrategies.join(', ')}',
            location: location,
          ));
          continue;
        }
      }

      // Section sub-validation
      if (key == 'nullability' && value is YamlMap) {
        _validateSection(
          value,
          _nullabilityKeys,
          'CFG0011',
          'nullability',
          sourcePath,
          emit,
        );
      } else if (key == 'async_behavior' && value is YamlMap) {
        _validateSection(
          value,
          _asyncBehaviorKeys,
          'CFG0012',
          'async_behavior',
          sourcePath,
          emit,
        );
      } else if (key == 'naming_conventions' && value is YamlMap) {
        _validateSection(
          value,
          _namingConventionsKeys,
          'CFG0013',
          'naming_conventions',
          sourcePath,
          emit,
        );
      }

      cleaned[key] = value;
    }

    return (cleaned: cleaned, diagnostics: diagnostics);
  }

  /// Validates keys within a named section map, emitting [warningCode] for
  /// any key not in [recognizedKeys].
  static void _validateSection(
    YamlMap section,
    Set<String> recognizedKeys,
    String warningCode,
    String sectionName,
    String sourcePath,
    void Function(ConfigDiagnostic) emit,
  ) {
    for (final rawKey in section.keys) {
      final key = rawKey.toString();
      if (!recognizedKeys.contains(key)) {
        final location = _locationFor(section, rawKey, sourcePath);
        emit(ConfigDiagnostic(
          severity: DiagnosticSeverity.warning,
          code: warningCode,
          message: 'Unrecognized key "$key" under "$sectionName"',
          location: location,
        ));
      }
    }
  }

  /// Attempts to extract a [SourceLocation] from the YAML node span.
  /// Falls back to line 0, column 0 if span info is unavailable.
  static SourceLocation _locationFor(
    YamlMap map,
    dynamic key,
    String sourcePath,
  ) {
    try {
      final node = map.nodes[key];
      if (node != null) {
        final span = node.span;
        return SourceLocation(
          filePath: sourcePath,
          line: span.start.line,
          column: span.start.column,
        );
      }
    } catch (_) {
      // Span info unavailable — fall through to default.
    }
    return SourceLocation(filePath: sourcePath, line: 0, column: 0);
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

enum _ValueType { string, bool, map, list }

class _KeySpec {
  final _ValueType type;
  final bool isEnum;
  final bool nullable;

  const _KeySpec({
    required this.type,
    this.isEnum = false,
    this.nullable = false,
  });

  bool matches(dynamic value) => switch (type) {
        _ValueType.string => value is String,
        _ValueType.bool => value is bool,
        _ValueType.map => value is YamlMap || value is Map,
        _ValueType.list => value is YamlList || value is List,
      };

  String get typeName => switch (type) {
        _ValueType.string => 'String',
        _ValueType.bool => 'bool',
        _ValueType.map => 'Map',
        _ValueType.list => 'List',
      };
}
