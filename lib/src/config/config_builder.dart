import 'package:yaml/yaml.dart';

import 'models/async_config.dart';
import 'models/case_style.dart';
import 'models/config_object.dart';
import 'models/event_mapping_override.dart';
import 'models/event_strategy.dart';
import 'models/linq_strategy.dart';
import 'models/naming_conventions.dart';
import 'models/nullability_config.dart';
import 'models/struct_mapping_override.dart';

/// Constructs a strongly-typed [ConfigObject] from a validated map of YAML key/value pairs.
///
/// All absent keys are substituted with the corresponding [ConfigObject.defaults] values.
final class ConfigBuilder {
  /// Builds a [ConfigObject] from [validated], a map produced by `ConfigValidator.validate`.
  ///
  /// Keys use YAML snake_case names. Missing keys fall back to [ConfigObject.defaults].
  static ConfigObject build(Map<String, dynamic> validated) {
    final d = ConfigObject.defaults;

    return ConfigObject(
      linqStrategy: _linqStrategy(validated, d),
      nullability: _nullability(validated, d),
      asyncBehavior: _asyncBehavior(validated, d),
      namespaceMappings: _stringMap(validated, 'namespace_mappings') ?? d.namespaceMappings,
      rootNamespace: validated.containsKey('root_namespace')
          ? validated['root_namespace'] as String?
          : d.rootNamespace,
      barrelFiles: validated.containsKey('barrel_files')
          ? validated['barrel_files'] as bool
          : d.barrelFiles,
      namespacePrefixAliases:
          _stringMap(validated, 'namespace_prefix_aliases') ?? d.namespacePrefixAliases,
      autoResolveConflicts: validated.containsKey('auto_resolve_conflicts')
          ? validated['auto_resolve_conflicts'] as bool
          : d.autoResolveConflicts,
      eventStrategy: _eventStrategy(validated, d),
      eventMappings: _eventMappings(validated, d),
      packageMappings: _stringMap(validated, 'package_mappings') ?? d.packageMappings,
      sdkPath: validated.containsKey('sdk_path')
          ? validated['sdk_path'] as String?
          : d.sdkPath,
      nugetFeedUrls: _stringList(validated, 'nuget_feeds') ?? d.nugetFeedUrls,
      libraryMappings: _stringMap(validated, 'library_mappings') ?? d.libraryMappings,
      structMappings: _structMappings(validated, d),
      namingConventions: _namingConventions(validated, d),
      experimentalFeatures: _boolMap(validated, 'experimental') ?? d.experimentalFeatures,
    );
  }

  // ---------------------------------------------------------------------------
  // Scalar helpers
  // ---------------------------------------------------------------------------

  static LinqStrategy _linqStrategy(Map<String, dynamic> v, ConfigObject d) {
    if (!v.containsKey('linq_strategy')) return d.linqStrategy;
    final raw = v['linq_strategy'] as String;
    return LinqStrategy.fromYaml(raw) ?? d.linqStrategy;
  }

  static EventStrategy _eventStrategy(Map<String, dynamic> v, ConfigObject d) {
    if (!v.containsKey('event_strategy')) return d.eventStrategy;
    final raw = v['event_strategy'] as String;
    return EventStrategy.fromYaml(raw) ?? d.eventStrategy;
  }

  // ---------------------------------------------------------------------------
  // Nested section helpers
  // ---------------------------------------------------------------------------

  static NullabilityConfig _nullability(Map<String, dynamic> v, ConfigObject d) {
    if (!v.containsKey('nullability')) return d.nullability;
    final raw = _toMap(v['nullability']);
    if (raw == null) return d.nullability;
    return NullabilityConfig(
      treatNullableAsOptional: raw['treat_nullable_as_optional'] as bool? ??
          d.nullability.treatNullableAsOptional,
      emitNullAsserts:
          raw['emit_null_asserts'] as bool? ?? d.nullability.emitNullAsserts,
      preserveNullableAnnotations: raw['preserve_nullable_annotations'] as bool? ??
          d.nullability.preserveNullableAnnotations,
    );
  }

  static AsyncConfig _asyncBehavior(Map<String, dynamic> v, ConfigObject d) {
    if (!v.containsKey('async_behavior')) return d.asyncBehavior;
    final raw = _toMap(v['async_behavior']);
    if (raw == null) return d.asyncBehavior;
    return AsyncConfig(
      omitConfigureAwait: raw['omit_configure_await'] as bool? ??
          d.asyncBehavior.omitConfigureAwait,
      mapValueTaskToFuture: raw['map_value_task_to_future'] as bool? ??
          d.asyncBehavior.mapValueTaskToFuture,
    );
  }

  static NamingConventions _namingConventions(Map<String, dynamic> v, ConfigObject d) {
    if (!v.containsKey('naming_conventions')) return d.namingConventions;
    final raw = _toMap(v['naming_conventions']);
    if (raw == null) return d.namingConventions;
    return NamingConventions(
      classNameStyle: _caseStyle(raw, 'class_name_style') ??
          d.namingConventions.classNameStyle,
      methodNameStyle: _caseStyle(raw, 'method_name_style') ??
          d.namingConventions.methodNameStyle,
      fieldNameStyle: _caseStyle(raw, 'field_name_style') ??
          d.namingConventions.fieldNameStyle,
      fileNameStyle: _caseStyle(raw, 'file_name_style') ??
          d.namingConventions.fileNameStyle,
      privatePrefix: raw['private_prefix'] as String? ??
          d.namingConventions.privatePrefix,
    );
  }

  static Map<String, EventMappingOverride> _eventMappings(
      Map<String, dynamic> v, ConfigObject d) {
    if (!v.containsKey('event_mappings')) return d.eventMappings;
    final raw = _toMap(v['event_mappings']);
    if (raw == null) return d.eventMappings;
    return {
      for (final entry in raw.entries)
        entry.key: _eventMappingOverride(_toMap(entry.value) ?? {}),
    };
  }

  static EventMappingOverride _eventMappingOverride(Map<String, dynamic> raw) {
    final strategyRaw = raw['strategy'] as String?;
    return EventMappingOverride(
      strategy: strategyRaw != null ? EventStrategy.fromYaml(strategyRaw) : null,
      dartEventName: raw['dart_event_name'] as String?,
    );
  }

  static Map<String, StructMappingOverride> _structMappings(
      Map<String, dynamic> v, ConfigObject d) {
    if (!v.containsKey('struct_mappings')) return d.structMappings;
    final raw = _toMap(v['struct_mappings']);
    if (raw == null) return d.structMappings;
    return {
      for (final entry in raw.entries)
        entry.key: _structMappingOverride(_toMap(entry.value) ?? {}),
    };
  }

  static StructMappingOverride _structMappingOverride(Map<String, dynamic> raw) {
    return StructMappingOverride(
      dartType: raw['dart_type'] as String?,
      dartPackage: raw['dart_package'] as String?,
    );
  }

  // ---------------------------------------------------------------------------
  // Collection helpers
  // ---------------------------------------------------------------------------

  static Map<String, String>? _stringMap(Map<String, dynamic> v, String key) {
    if (!v.containsKey(key)) return null;
    final raw = _toMap(v[key]);
    if (raw == null) return null;
    return {for (final e in raw.entries) e.key: e.value as String};
  }

  static Map<String, bool>? _boolMap(Map<String, dynamic> v, String key) {
    if (!v.containsKey(key)) return null;
    final raw = _toMap(v[key]);
    if (raw == null) return null;
    return {for (final e in raw.entries) e.key: e.value as bool};
  }

  static List<String>? _stringList(Map<String, dynamic> v, String key) {
    if (!v.containsKey(key)) return null;
    final raw = v[key];
    if (raw is YamlList) return raw.map((e) => e as String).toList();
    if (raw is List) return raw.cast<String>();
    return null;
  }

  static CaseStyle? _caseStyle(Map<String, dynamic> raw, String key) {
    if (!raw.containsKey(key)) return null;
    final value = raw[key] as String?;
    if (value == null) return null;
    return CaseStyle.fromYaml(value);
  }

  /// Converts a [YamlMap] or plain [Map] to a `Map<String, dynamic>`.
  static Map<String, dynamic>? _toMap(dynamic value) {
    if (value is YamlMap) {
      return {for (final e in value.entries) e.key as String: e.value};
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return null;
  }
}
