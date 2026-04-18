import 'package:cs2dart/src/config/i_config_service.dart';
import 'package:cs2dart/src/config/models/models.dart';

/// A minimal [IConfigService] implementation for tests that returns all
/// default configuration values.
final class FakeConfigService implements IConfigService {
  @override
  LinqStrategy get linqStrategy => LinqStrategy.preserveFunctional;

  @override
  NullabilityConfig get nullability => const NullabilityConfig();

  @override
  AsyncConfig get asyncBehavior => const AsyncConfig();

  @override
  Map<String, String> get namespaceMappings => const {};

  @override
  String? get rootNamespace => null;

  @override
  bool get barrelFiles => false;

  @override
  Map<String, String> get namespacePrefixAliases => const {};

  @override
  bool get autoResolveConflicts => false;

  @override
  EventStrategy get eventStrategy => EventStrategy.stream;

  @override
  Map<String, EventMappingOverride> get eventMappings => const {};

  @override
  Map<String, String> get packageMappings => const {};

  @override
  String? get sdkPath => null;

  @override
  List<String> get nugetFeedUrls =>
      const ['https://api.nuget.org/v3/index.json'];

  @override
  Map<String, String> get libraryMappings => const {};

  @override
  Map<String, StructMappingOverride> get structMappings => const {};

  @override
  NamingConventions get namingConventions => const NamingConventions();

  @override
  Map<String, bool> get experimentalFeatures => const {};

  @override
  ConfigObject get config => ConfigObject.defaults;
}
