import 'models/models.dart';

/// Serialization extension for [ConfigObject].
extension ConfigObjectSerialization on ConfigObject {
  /// Produces a [Map<String, dynamic>] representation of this [ConfigObject]
  /// using the canonical YAML key names defined in the transpiler.yaml schema.
  ///
  /// The resulting map is suitable for serialization back to YAML and supports
  /// the round-trip property: parsing the serialized output SHALL produce a
  /// value-equal [ConfigObject].
  Map<String, dynamic> toYamlMap() {
    return {
      'linq_strategy': linqStrategy.yamlValue,
      'nullability': {
        'treat_nullable_as_optional': nullability.treatNullableAsOptional,
        'emit_null_asserts': nullability.emitNullAsserts,
        'preserve_nullable_annotations': nullability.preserveNullableAnnotations,
      },
      'async_behavior': {
        'omit_configure_await': asyncBehavior.omitConfigureAwait,
        'map_value_task_to_future': asyncBehavior.mapValueTaskToFuture,
      },
      'namespace_mappings': Map<String, String>.from(namespaceMappings),
      if (rootNamespace != null) 'root_namespace': rootNamespace,
      'barrel_files': barrelFiles,
      'namespace_prefix_aliases': Map<String, String>.from(namespacePrefixAliases),
      'auto_resolve_conflicts': autoResolveConflicts,
      'event_strategy': eventStrategy.yamlValue,
      'event_mappings': {
        for (final entry in eventMappings.entries)
          entry.key: {
            if (entry.value.strategy != null)
              'strategy': entry.value.strategy!.yamlValue,
            'dart_event_name': entry.value.dartEventName,
          },
      },
      'package_mappings': Map<String, String>.from(packageMappings),
      if (sdkPath != null) 'sdk_path': sdkPath,
      'nuget_feeds': List<String>.from(nugetFeedUrls),
      'library_mappings': Map<String, String>.from(libraryMappings),
      'struct_mappings': {
        for (final entry in structMappings.entries)
          entry.key: {
            'dart_type': entry.value.dartType,
            'dart_package': entry.value.dartPackage,
          },
      },
      'naming_conventions': {
        'class_name_style': namingConventions.classNameStyle.yamlValue,
        'method_name_style': namingConventions.methodNameStyle.yamlValue,
        'field_name_style': namingConventions.fieldNameStyle.yamlValue,
        'file_name_style': namingConventions.fileNameStyle.yamlValue,
        'private_prefix': namingConventions.privatePrefix,
      },
      'experimental': Map<String, bool>.from(experimentalFeatures),
    };
  }
}
