import 'models/models.dart';

/// The public contract consumed by all pipeline modules.
///
/// All methods are pure getters — no I/O, no side effects.
/// This is the only mechanism by which pipeline modules access configuration.
abstract interface class IConfigService {
  // LINQ
  LinqStrategy get linqStrategy;

  // Nullability
  NullabilityConfig get nullability;

  // Async
  AsyncConfig get asyncBehavior;

  // Namespace mapping
  Map<String, String> get namespaceMappings;
  String? get rootNamespace;
  bool get barrelFiles;
  Map<String, String> get namespacePrefixAliases;
  bool get autoResolveConflicts;

  // Events
  EventStrategy get eventStrategy;
  Map<String, EventMappingOverride> get eventMappings;

  // NuGet / packages
  Map<String, String> get packageMappings;
  String? get sdkPath;
  List<String> get nugetFeedUrls;

  // Type mappings
  Map<String, String> get libraryMappings;
  Map<String, StructMappingOverride> get structMappings;

  // Naming
  NamingConventions get namingConventions;

  // Feature flags
  Map<String, bool> get experimentalFeatures;

  // Resolved config object (for Load_Result)
  ConfigObject get config;
}
