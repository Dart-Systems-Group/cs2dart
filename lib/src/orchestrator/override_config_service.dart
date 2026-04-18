import '../config/i_config_service.dart';
import '../config/models/models.dart';

/// A decorator around [IConfigService] that merges [_overrides] into
/// [experimentalFeatures] while delegating all other getters to the
/// wrapped [_inner] instance unchanged.
///
/// Used by the Orchestrator to apply `SkipFormat`/`SkipAnalyze` flags
/// without mutating the original [IConfigService] produced by config loading.
///
/// The override is applied once at construction time; the same instance is
/// passed to every pipeline stage that accepts an [IConfigService].
final class OverrideConfigService implements IConfigService {
  final IConfigService _inner;
  final Map<String, bool> _overrides;

  const OverrideConfigService(this._inner, this._overrides);

  @override
  Map<String, bool> get experimentalFeatures => {
        ..._inner.experimentalFeatures,
        ..._overrides,
      };

  // All other getters delegate to _inner unchanged.

  @override
  LinqStrategy get linqStrategy => _inner.linqStrategy;

  @override
  NullabilityConfig get nullability => _inner.nullability;

  @override
  AsyncConfig get asyncBehavior => _inner.asyncBehavior;

  @override
  Map<String, String> get namespaceMappings => _inner.namespaceMappings;

  @override
  String? get rootNamespace => _inner.rootNamespace;

  @override
  bool get barrelFiles => _inner.barrelFiles;

  @override
  Map<String, String> get namespacePrefixAliases => _inner.namespacePrefixAliases;

  @override
  bool get autoResolveConflicts => _inner.autoResolveConflicts;

  @override
  EventStrategy get eventStrategy => _inner.eventStrategy;

  @override
  Map<String, EventMappingOverride> get eventMappings => _inner.eventMappings;

  @override
  Map<String, String> get packageMappings => _inner.packageMappings;

  @override
  String? get sdkPath => _inner.sdkPath;

  @override
  List<String> get nugetFeedUrls => _inner.nugetFeedUrls;

  @override
  Map<String, String> get libraryMappings => _inner.libraryMappings;

  @override
  Map<String, StructMappingOverride> get structMappings => _inner.structMappings;

  @override
  NamingConventions get namingConventions => _inner.namingConventions;

  @override
  ConfigObject get config => _inner.config;
}
