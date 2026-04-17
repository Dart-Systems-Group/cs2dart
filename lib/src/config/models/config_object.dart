import 'async_config.dart';
import 'event_mapping_override.dart';
import 'event_strategy.dart';
import 'linq_strategy.dart';
import 'naming_conventions.dart';
import 'nullability_config.dart';
import 'struct_mapping_override.dart';

/// The immutable, strongly-typed in-memory representation of `transpiler.yaml`.
///
/// All fields have documented default values accessible via [ConfigObject.defaults].
/// Instances are compared by value equality across all 17 fields.
final class ConfigObject {
  /// Controls how LINQ expressions are transpiled to Dart.
  ///
  /// Default: [LinqStrategy.preserveFunctional]
  final LinqStrategy linqStrategy;

  /// Configuration for how C# nullable reference types are mapped to Dart null-safety.
  ///
  /// Default: [NullabilityConfig] with all documented defaults.
  final NullabilityConfig nullability;

  /// Configuration for how C# async patterns are mapped to Dart.
  ///
  /// Default: [AsyncConfig] with all documented defaults.
  final AsyncConfig asyncBehavior;

  /// Fully-qualified C# namespace → Dart library path overrides.
  ///
  /// Default: empty map
  final Map<String, String> namespaceMappings;

  /// The namespace prefix to strip from generated Dart identifiers.
  ///
  /// Default: null
  final String? rootNamespace;

  /// Whether barrel export files are generated.
  ///
  /// Default: false
  final bool barrelFiles;

  /// Namespace prefix replacement map.
  ///
  /// Default: empty map
  final Map<String, String> namespacePrefixAliases;

  /// Whether namespace conflicts are auto-resolved.
  ///
  /// Default: false
  final bool autoResolveConflicts;

  /// Controls how C# events are transpiled to Dart.
  ///
  /// Default: [EventStrategy.stream]
  final EventStrategy eventStrategy;

  /// Per-event overrides for how specific C# events are transpiled.
  ///
  /// Default: empty map
  final Map<String, EventMappingOverride> eventMappings;

  /// NuGet package name → Dart package name overrides.
  ///
  /// Default: empty map
  final Map<String, String> packageMappings;

  /// Explicit .NET SDK path override.
  ///
  /// Default: null
  final String? sdkPath;

  /// Ordered list of NuGet feed URLs to query before falling back to nuget.org.
  ///
  /// Default: `["https://api.nuget.org/v3/index.json"]`
  final List<String> nugetFeedUrls;

  /// .NET type → Dart type overrides.
  ///
  /// Default: empty map
  final Map<String, String> libraryMappings;

  /// Per-struct BCL overrides for how specific C# structs are mapped to Dart types.
  ///
  /// Default: empty map
  final Map<String, StructMappingOverride> structMappings;

  /// Naming convention settings for generated Dart identifiers.
  ///
  /// Default: [NamingConventions] with all Dart-idiomatic defaults.
  final NamingConventions namingConventions;

  /// Feature-flag toggles for in-progress features.
  ///
  /// Default: empty map
  final Map<String, bool> experimentalFeatures;

  const ConfigObject({
    this.linqStrategy = LinqStrategy.preserveFunctional,
    this.nullability = const NullabilityConfig(),
    this.asyncBehavior = const AsyncConfig(),
    this.namespaceMappings = const {},
    this.rootNamespace,
    this.barrelFiles = false,
    this.namespacePrefixAliases = const {},
    this.autoResolveConflicts = false,
    this.eventStrategy = EventStrategy.stream,
    this.eventMappings = const {},
    this.packageMappings = const {},
    this.sdkPath,
    this.nugetFeedUrls = const ['https://api.nuget.org/v3/index.json'],
    this.libraryMappings = const {},
    this.structMappings = const {},
    this.namingConventions = const NamingConventions(),
    this.experimentalFeatures = const {},
  });

  /// A [ConfigObject] with all fields at their documented default values.
  static const ConfigObject defaults = ConfigObject();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ConfigObject) return false;
    return linqStrategy == other.linqStrategy &&
        nullability == other.nullability &&
        asyncBehavior == other.asyncBehavior &&
        _mapsEqual(namespaceMappings, other.namespaceMappings) &&
        rootNamespace == other.rootNamespace &&
        barrelFiles == other.barrelFiles &&
        _mapsEqual(namespacePrefixAliases, other.namespacePrefixAliases) &&
        autoResolveConflicts == other.autoResolveConflicts &&
        eventStrategy == other.eventStrategy &&
        _mapsEqual(eventMappings, other.eventMappings) &&
        _mapsEqual(packageMappings, other.packageMappings) &&
        sdkPath == other.sdkPath &&
        _listsEqual(nugetFeedUrls, other.nugetFeedUrls) &&
        _mapsEqual(libraryMappings, other.libraryMappings) &&
        _mapsEqual(structMappings, other.structMappings) &&
        namingConventions == other.namingConventions &&
        _mapsEqual(experimentalFeatures, other.experimentalFeatures);
  }

  @override
  int get hashCode => Object.hashAll([
        linqStrategy,
        nullability,
        asyncBehavior,
        Object.hashAll(namespaceMappings.entries.map((e) => Object.hash(e.key, e.value))),
        rootNamespace,
        barrelFiles,
        Object.hashAll(namespacePrefixAliases.entries.map((e) => Object.hash(e.key, e.value))),
        autoResolveConflicts,
        eventStrategy,
        Object.hashAll(eventMappings.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(packageMappings.entries.map((e) => Object.hash(e.key, e.value))),
        sdkPath,
        Object.hashAll(nugetFeedUrls),
        Object.hashAll(libraryMappings.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(structMappings.entries.map((e) => Object.hash(e.key, e.value))),
        namingConventions,
        Object.hashAll(experimentalFeatures.entries.map((e) => Object.hash(e.key, e.value))),
      ]);
}

/// Returns true if two maps have the same keys and equal values.
bool _mapsEqual<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Returns true if two lists have the same length and equal elements.
bool _listsEqual<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
