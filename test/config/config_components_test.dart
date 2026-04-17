import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:cs2dart/src/config/config_parser.dart';
import 'package:cs2dart/src/config/config_validator.dart';
import 'package:cs2dart/src/config/config_builder.dart';
import 'package:cs2dart/src/config/config_service.dart';
import 'package:cs2dart/src/config/models/models.dart';

void main() {
  // ---------------------------------------------------------------------------
  // ConfigParser (task 4.2)
  // ---------------------------------------------------------------------------
  group('ConfigParser', () {
    test('valid YAML returns a YamlMap', () {
      final result = ConfigParser.parse('linq_strategy: preserve_functional', 'cfg.yaml');
      expect(result.map, isA<YamlMap>());
      expect(result.error, isNull);
    });

    test('empty content returns empty YamlMap', () {
      final result = ConfigParser.parse('', 'cfg.yaml');
      expect(result.map, isA<YamlMap>());
      expect(result.map!.isEmpty, isTrue);
      expect(result.error, isNull);
    });

    test('invalid YAML syntax emits CFG0002 with location info', () {
      final result = ConfigParser.parse(': bad: yaml: [unclosed', 'cfg.yaml');
      expect(result.map, isNull);
      expect(result.error, isNotNull);
      expect(result.error!.code, 'CFG0002');
      expect(result.error!.severity, DiagnosticSeverity.error);
      expect(result.error!.location?.filePath, 'cfg.yaml');
    });

    test('non-mapping top-level document emits CFG0002', () {
      final result = ConfigParser.parse('- item1\n- item2', 'cfg.yaml');
      expect(result.map, isNull);
      expect(result.error, isNotNull);
      expect(result.error!.code, 'CFG0002');
      expect(result.error!.location?.filePath, 'cfg.yaml');
      expect(result.error!.location?.line, 1);
    });

    test('scalar top-level document emits CFG0002', () {
      final result = ConfigParser.parse('just a string', 'cfg.yaml');
      expect(result.map, isNull);
      expect(result.error!.code, 'CFG0002');
    });
  });

  // ---------------------------------------------------------------------------
  // ConfigValidator (task 5.4)
  // ---------------------------------------------------------------------------
  group('ConfigValidator', () {
    YamlMap _yaml(String content) => loadYaml(content) as YamlMap;

    test('unrecognized top-level key emits CFG0010 Warning and parsing continues', () {
      final raw = _yaml('unknown_key: value\nlinq_strategy: preserve_functional');
      final result = ConfigValidator.validate(raw, 'cfg.yaml');
      final warnings = result.diagnostics.where((d) => d.code == 'CFG0010').toList();
      expect(warnings, hasLength(1));
      expect(warnings.first.severity, DiagnosticSeverity.warning);
      // recognized key is still in cleaned map
      expect(result.cleaned.containsKey('linq_strategy'), isTrue);
    });

    test('type mismatch on recognized key emits CFG0003 Error', () {
      final raw = _yaml('barrel_files: not_a_bool');
      final result = ConfigValidator.validate(raw, 'cfg.yaml');
      final errors = result.diagnostics.where((d) => d.code == 'CFG0003').toList();
      expect(errors, hasLength(1));
      expect(errors.first.severity, DiagnosticSeverity.error);
    });

    test('invalid linq_strategy value emits CFG0004 Error', () {
      final raw = _yaml('linq_strategy: invalid_value');
      final result = ConfigValidator.validate(raw, 'cfg.yaml');
      final errors = result.diagnostics.where((d) => d.code == 'CFG0004').toList();
      expect(errors, hasLength(1));
      expect(errors.first.severity, DiagnosticSeverity.error);
    });

    test('invalid event_strategy value emits CFG0004 Error', () {
      final raw = _yaml('event_strategy: invalid_value');
      final result = ConfigValidator.validate(raw, 'cfg.yaml');
      final errors = result.diagnostics.where((d) => d.code == 'CFG0004').toList();
      expect(errors, hasLength(1));
      expect(errors.first.severity, DiagnosticSeverity.error);
    });

    test('unrecognized key under nullability emits CFG0011 Warning', () {
      final raw = _yaml('nullability:\n  unknown_key: true');
      final result = ConfigValidator.validate(raw, 'cfg.yaml');
      final warnings = result.diagnostics.where((d) => d.code == 'CFG0011').toList();
      expect(warnings, hasLength(1));
      expect(warnings.first.severity, DiagnosticSeverity.warning);
    });

    test('unrecognized key under async_behavior emits CFG0012 Warning', () {
      final raw = _yaml('async_behavior:\n  unknown_key: true');
      final result = ConfigValidator.validate(raw, 'cfg.yaml');
      final warnings = result.diagnostics.where((d) => d.code == 'CFG0012').toList();
      expect(warnings, hasLength(1));
      expect(warnings.first.severity, DiagnosticSeverity.warning);
    });

    test('unrecognized key under naming_conventions emits CFG0013 Warning', () {
      final raw = _yaml('naming_conventions:\n  unknown_key: value');
      final result = ConfigValidator.validate(raw, 'cfg.yaml');
      final warnings = result.diagnostics.where((d) => d.code == 'CFG0013').toList();
      expect(warnings, hasLength(1));
      expect(warnings.first.severity, DiagnosticSeverity.warning);
    });

    test('duplicate (code, location) pairs are deduplicated', () {
      // Two unrecognized keys at different locations → two diagnostics
      final raw = _yaml('unknown_a: 1\nunknown_b: 2');
      final result = ConfigValidator.validate(raw, 'cfg.yaml');
      final codes = result.diagnostics.map((d) => d.code).toList();
      // Each unique location produces one diagnostic
      expect(codes.where((c) => c == 'CFG0010').length, 2);
    });

    test('valid YAML produces no diagnostics', () {
      final raw = _yaml('linq_strategy: preserve_functional\nbarrel_files: true');
      final result = ConfigValidator.validate(raw, 'cfg.yaml');
      expect(result.diagnostics, isEmpty);
      expect(result.cleaned['linq_strategy'], 'preserve_functional');
      expect(result.cleaned['barrel_files'], true);
    });
  });

  // ---------------------------------------------------------------------------
  // ConfigBuilder (task 6.2)
  // ---------------------------------------------------------------------------
  group('ConfigBuilder', () {
    test('empty map produces ConfigObject.defaults', () {
      final result = ConfigBuilder.build({});
      expect(result, equals(ConfigObject.defaults));
    });

    test('linq_strategy lower_to_loops maps to LinqStrategy.lowerToLoops', () {
      final result = ConfigBuilder.build({'linq_strategy': 'lower_to_loops'});
      expect(result.linqStrategy, LinqStrategy.lowerToLoops);
    });

    test('linq_strategy preserve_functional maps to LinqStrategy.preserveFunctional', () {
      final result = ConfigBuilder.build({'linq_strategy': 'preserve_functional'});
      expect(result.linqStrategy, LinqStrategy.preserveFunctional);
    });

    test('nuget_feeds default is the nuget.org v3 URL', () {
      final result = ConfigBuilder.build({});
      expect(result.nugetFeedUrls, ['https://api.nuget.org/v3/index.json']);
    });

    test('barrel_files field is correctly mapped', () {
      final result = ConfigBuilder.build({'barrel_files': true});
      expect(result.barrelFiles, isTrue);
    });

    test('root_namespace field is correctly mapped', () {
      final result = ConfigBuilder.build({'root_namespace': 'MyApp'});
      expect(result.rootNamespace, 'MyApp');
    });

    test('nullability section fields are correctly mapped', () {
      final yamlMap = loadYaml(
        'nullability:\n  treat_nullable_as_optional: true\n  emit_null_asserts: true',
      ) as YamlMap;
      final validated = ConfigValidator.validate(yamlMap, 'cfg.yaml');
      final result = ConfigBuilder.build(validated.cleaned);
      expect(result.nullability.treatNullableAsOptional, isTrue);
      expect(result.nullability.emitNullAsserts, isTrue);
    });

    test('async_behavior section fields are correctly mapped', () {
      final yamlMap = loadYaml(
        'async_behavior:\n  omit_configure_await: true',
      ) as YamlMap;
      final validated = ConfigValidator.validate(yamlMap, 'cfg.yaml');
      final result = ConfigBuilder.build(validated.cleaned);
      expect(result.asyncBehavior.omitConfigureAwait, isTrue);
    });

    test('naming_conventions section fields are correctly mapped', () {
      final yamlMap = loadYaml(
        'naming_conventions:\n  class_name_style: snake_case',
      ) as YamlMap;
      final validated = ConfigValidator.validate(yamlMap, 'cfg.yaml');
      final result = ConfigBuilder.build(validated.cleaned);
      expect(result.namingConventions.classNameStyle, CaseStyle.snakeCase);
    });
  });

  // ---------------------------------------------------------------------------
  // ConfigService (task 3.3)
  // ---------------------------------------------------------------------------
  group('ConfigService', () {
    late ConfigObject obj;
    late ConfigService service;

    setUp(() {
      obj = const ConfigObject(
        linqStrategy: LinqStrategy.lowerToLoops,
        barrelFiles: true,
        rootNamespace: 'TestNS',
        autoResolveConflicts: true,
        eventStrategy: EventStrategy.callback,
        sdkPath: '/sdk',
        nugetFeedUrls: ['https://example.com/feed'],
        namespaceMappings: {'A': 'b'},
        packageMappings: {'pkg': 'dart_pkg'},
        libraryMappings: {'T': 'DartT'},
        experimentalFeatures: {'newFeature': true},
      );
      service = ConfigService(obj);
    });

    test('linqStrategy accessor delegates to ConfigObject', () {
      expect(service.linqStrategy, LinqStrategy.lowerToLoops);
    });

    test('nullability accessor delegates to ConfigObject', () {
      expect(service.nullability, obj.nullability);
    });

    test('asyncBehavior accessor delegates to ConfigObject', () {
      expect(service.asyncBehavior, obj.asyncBehavior);
    });

    test('namespaceMappings accessor delegates to ConfigObject', () {
      expect(service.namespaceMappings, {'A': 'b'});
    });

    test('rootNamespace accessor delegates to ConfigObject', () {
      expect(service.rootNamespace, 'TestNS');
    });

    test('barrelFiles accessor delegates to ConfigObject', () {
      expect(service.barrelFiles, isTrue);
    });

    test('namespacePrefixAliases accessor delegates to ConfigObject', () {
      expect(service.namespacePrefixAliases, obj.namespacePrefixAliases);
    });

    test('autoResolveConflicts accessor delegates to ConfigObject', () {
      expect(service.autoResolveConflicts, isTrue);
    });

    test('eventStrategy accessor delegates to ConfigObject', () {
      expect(service.eventStrategy, EventStrategy.callback);
    });

    test('eventMappings accessor delegates to ConfigObject', () {
      expect(service.eventMappings, obj.eventMappings);
    });

    test('packageMappings accessor delegates to ConfigObject', () {
      expect(service.packageMappings, {'pkg': 'dart_pkg'});
    });

    test('sdkPath accessor delegates to ConfigObject', () {
      expect(service.sdkPath, '/sdk');
    });

    test('nugetFeedUrls accessor delegates to ConfigObject', () {
      expect(service.nugetFeedUrls, ['https://example.com/feed']);
    });

    test('libraryMappings accessor delegates to ConfigObject', () {
      expect(service.libraryMappings, {'T': 'DartT'});
    });

    test('structMappings accessor delegates to ConfigObject', () {
      expect(service.structMappings, obj.structMappings);
    });

    test('namingConventions accessor delegates to ConfigObject', () {
      expect(service.namingConventions, obj.namingConventions);
    });

    test('experimentalFeatures accessor delegates to ConfigObject', () {
      expect(service.experimentalFeatures, {'newFeature': true});
    });

    test('config accessor returns the wrapped ConfigObject', () {
      expect(service.config, same(obj));
    });
  });
}
