import 'i_config_service.dart';
import 'models/models.dart';

/// Concrete implementation of [IConfigService].
///
/// Wraps a [ConfigObject] and delegates all accessors to it.
/// Constructed by the config loading pipeline; not instantiated directly by consumers.
final class ConfigService implements IConfigService {
  final ConfigObject _config;

  const ConfigService(this._config);

  @override
  LinqStrategy get linqStrategy => _config.linqStrategy;

  @override
  NullabilityConfig get nullability => _config.nullability;

  @override
  AsyncConfig get asyncBehavior => _config.asyncBehavior;

  @override
  Map<String, String> get namespaceMappings => _config.namespaceMappings;

  @override
  String? get rootNamespace => _config.rootNamespace;

  @override
  bool get barrelFiles => _config.barrelFiles;

  @override
  Map<String, String> get namespacePrefixAliases => _config.namespacePrefixAliases;

  @override
  bool get autoResolveConflicts => _config.autoResolveConflicts;

  @override
  EventStrategy get eventStrategy => _config.eventStrategy;

  @override
  Map<String, EventMappingOverride> get eventMappings => _config.eventMappings;

  @override
  Map<String, String> get packageMappings => _config.packageMappings;

  @override
  String? get sdkPath => _config.sdkPath;

  @override
  List<String> get nugetFeedUrls => _config.nugetFeedUrls;

  @override
  Map<String, String> get libraryMappings => _config.libraryMappings;

  @override
  Map<String, StructMappingOverride> get structMappings => _config.structMappings;

  @override
  NamingConventions get namingConventions => _config.namingConventions;

  @override
  Map<String, bool> get experimentalFeatures => _config.experimentalFeatures;

  @override
  ConfigObject get config => _config;
}
