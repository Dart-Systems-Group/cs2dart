// Validates: Requirements 1.6, 14.3
import 'package:test/test.dart';
import 'package:cs2dart/src/roslyn_frontend/serialization/frontend_result_deserializer.dart';
import 'package:cs2dart/src/roslyn_frontend/models/frontend_result.dart';
import 'package:cs2dart/src/roslyn_frontend/models/frontend_unit.dart';
import 'package:cs2dart/src/roslyn_frontend/models/generic_syntax_node.dart';
import 'package:cs2dart/src/roslyn_frontend/models/ir_type.dart';
import 'package:cs2dart/src/roslyn_frontend/models/annotations.dart';
import 'package:cs2dart/src/roslyn_frontend/models/resolved_symbol.dart';
import 'package:cs2dart/src/project_loader/models/output_kind.dart';
import 'package:cs2dart/src/project_loader/models/diagnostic.dart';

const _deserializer = FrontendResultDeserializer();

// ---------------------------------------------------------------------------
// JSON builder helpers (test-only serializer)
// ---------------------------------------------------------------------------

Map<String, dynamic> _sourceLocationJson({
  String filePath = '/src/Foo.cs',
  int line = 10,
  int column = 5,
}) =>
    {'filePath': filePath, 'line': line, 'column': column};

Map<String, dynamic> _resolvedSymbolJson({
  String fullyQualifiedName = 'System.String',
  String assemblyName = 'System.Runtime',
  String kind = 'type',
  String? sourcePackageId,
  Map<String, dynamic>? sourceLocation,
  Object? constantValue,
}) {
  final m = <String, dynamic>{
    'fullyQualifiedName': fullyQualifiedName,
    'assemblyName': assemblyName,
    'kind': kind,
  };
  if (sourcePackageId != null) m['sourcePackageId'] = sourcePackageId;
  if (sourceLocation != null) m['sourceLocation'] = sourceLocation;
  if (constantValue != null) m['constantValue'] = constantValue;
  return m;
}

Map<String, dynamic> _namedTypeJson({
  Map<String, dynamic>? symbol,
  List<Map<String, dynamic>> typeArguments = const [],
}) =>
    {
      r'$type': 'NamedType',
      'symbol': symbol ?? _resolvedSymbolJson(),
      'typeArguments': typeArguments,
    };

Map<String, dynamic> _nullableTypeJson(Map<String, dynamic> inner) =>
    {r'$type': 'NullableType', 'inner': inner};

Map<String, dynamic> _functionTypeJson({
  List<Map<String, dynamic>> parameterTypes = const [],
  Map<String, dynamic>? returnType,
}) =>
    {
      r'$type': 'FunctionType',
      'parameterTypes': parameterTypes,
      'returnType': returnType ?? _namedTypeJson(),
    };

Map<String, dynamic> _dynamicTypeJson() => {r'$type': 'DynamicType'};

Map<String, dynamic> _unresolvedTypeJson() => {r'$type': 'UnresolvedType'};

Map<String, dynamic> _syntaxNodeJson({
  int nodeId = 1,
  String kind = 'CompilationUnit',
  List<Map<String, dynamic>> children = const [],
  List<Map<String, dynamic>> annotations = const [],
}) =>
    {
      'nodeId': nodeId,
      'kind': kind,
      'children': children,
      'annotations': annotations,
    };

Map<String, dynamic> _symbolTableJson(Map<String, dynamic> entries) =>
    {'entries': entries};

Map<String, dynamic> _normalizedTreeJson({
  String filePath = '/src/Foo.cs',
  Map<String, dynamic>? root,
  Map<String, dynamic>? symbolTable,
}) =>
    {
      'filePath': filePath,
      'root': root ?? _syntaxNodeJson(),
      'symbolTable': symbolTable ?? _symbolTableJson({}),
    };

Map<String, dynamic> _packageRefJson({
  String packageName = 'Newtonsoft.Json',
  String version = '13.0.1',
  int tier = 1,
  Map<String, dynamic>? dartMapping,
}) {
  final m = <String, dynamic>{
    'packageName': packageName,
    'version': version,
    'tier': tier,
  };
  if (dartMapping != null) m['dartMapping'] = dartMapping;
  return m;
}

Map<String, dynamic> _dartMappingJson({
  String dartPackageName = 'json_serializable',
  String dartImportPath = 'package:json_serializable/json_serializable.dart',
}) =>
    {
      'dartPackageName': dartPackageName,
      'dartImportPath': dartImportPath,
    };

Map<String, dynamic> _frontendUnitJson({
  String projectName = 'MyApp',
  String outputKind = 'exe',
  String targetFramework = 'net8.0',
  String langVersion = '12.0',
  bool nullableEnabled = true,
  List<Map<String, dynamic>> packageReferences = const [],
  List<Map<String, dynamic>> normalizedTrees = const [],
}) =>
    {
      'projectName': projectName,
      'outputKind': outputKind,
      'targetFramework': targetFramework,
      'langVersion': langVersion,
      'nullableEnabled': nullableEnabled,
      'packageReferences': packageReferences,
      'normalizedTrees': normalizedTrees,
    };

Map<String, dynamic> _diagnosticJson({
  String severity = 'error',
  String code = 'RF0001',
  String message = 'Something went wrong',
  String? source,
  Map<String, dynamic>? location,
}) {
  final m = <String, dynamic>{
    'severity': severity,
    'code': code,
    'message': message,
  };
  if (source != null) m['source'] = source;
  if (location != null) m['location'] = location;
  return m;
}

Map<String, dynamic> _frontendResultJson({
  List<Map<String, dynamic>> units = const [],
  List<Map<String, dynamic>> diagnostics = const [],
  bool success = true,
}) =>
    {
      'units': units,
      'diagnostics': diagnostics,
      'success': success,
    };
