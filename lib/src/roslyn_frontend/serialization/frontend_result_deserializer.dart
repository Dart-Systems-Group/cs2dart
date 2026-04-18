import '../../project_loader/models/roslyn_interop.dart';
import '../models/annotations.dart';
import '../models/frontend_result.dart';
import '../models/frontend_unit.dart';
import '../models/generic_syntax_node.dart';
import '../models/ir_type.dart';
import '../models/normalized_syntax_tree.dart';
import '../models/resolved_symbol.dart';
import '../models/symbol_table.dart';
import '../models/syntax_node.dart';

/// Deserializes a [FrontendResult] from a JSON-compatible map produced by the
/// .NET worker process.
///
/// No Roslyn types appear in the deserialized object graph — all fields are
/// plain Dart values.
final class FrontendResultDeserializer {
  const FrontendResultDeserializer();

  // -------------------------------------------------------------------------
  // Public entry point
  // -------------------------------------------------------------------------

  /// Deserializes a [FrontendResult] from [json].
  ///
  /// [json] must be the top-level map produced by the .NET worker's
  /// `WorkerResponseSerializer`.
  FrontendResult fromJson(Map<String, dynamic> json) {
    final units = (json['units'] as List<dynamic>)
        .map((e) => _frontendUnitFromJson(e as Map<String, dynamic>))
        .toList();

    final diagnostics = (json['diagnostics'] as List<dynamic>)
        .map((e) => _diagnosticFromJson(e as Map<String, dynamic>))
        .toList();

    return FrontendResult(
      units: units,
      diagnostics: diagnostics,
      success: json['success'] as bool,
    );
  }

  // -------------------------------------------------------------------------
  // FrontendUnit
  // -------------------------------------------------------------------------

  FrontendUnit _frontendUnitFromJson(Map<String, dynamic> json) {
    final packageReferences = (json['packageReferences'] as List<dynamic>)
        .map((e) => _packageReferenceFromJson(e as Map<String, dynamic>))
        .toList();

    final normalizedTrees = (json['normalizedTrees'] as List<dynamic>)
        .map((e) => _normalizedSyntaxTreeFromJson(e as Map<String, dynamic>))
        .toList();

    return FrontendUnit(
      projectName: json['projectName'] as String,
      outputKind: _outputKindFromJson(json['outputKind'] as String),
      targetFramework: json['targetFramework'] as String,
      langVersion: json['langVersion'] as String,
      nullableEnabled: json['nullableEnabled'] as bool,
      packageReferences: packageReferences,
      normalizedTrees: normalizedTrees,
    );
  }

  OutputKind _outputKindFromJson(String value) {
    return switch (value) {
      'exe' => OutputKind.exe,
      'library' => OutputKind.library,
      'winExe' => OutputKind.winExe,
      _ => throw ArgumentError.value(value, 'outputKind', 'Unknown OutputKind'),
    };
  }

  PackageReferenceEntry _packageReferenceFromJson(Map<String, dynamic> json) {
    final dartMappingJson = json['dartMapping'] as Map<String, dynamic>?;
    final dartMapping =
        dartMappingJson != null ? _dartMappingFromJson(dartMappingJson) : null;

    return PackageReferenceEntry(
      packageName: json['packageName'] as String,
      version: json['version'] as String,
      tier: json['tier'] as int,
      dartMapping: dartMapping,
    );
  }

  DartMapping _dartMappingFromJson(Map<String, dynamic> json) {
    return DartMapping(
      dartPackageName: json['dartPackageName'] as String,
      dartImportPath: json['dartImportPath'] as String,
    );
  }

  // -------------------------------------------------------------------------
  // NormalizedSyntaxTree
  // -------------------------------------------------------------------------

  NormalizedSyntaxTree _normalizedSyntaxTreeFromJson(
      Map<String, dynamic> json) {
    final root =
        _syntaxNodeFromJson(json['root'] as Map<String, dynamic>);
    final symbolTable =
        _symbolTableFromJson(json['symbolTable'] as Map<String, dynamic>);

    return NormalizedSyntaxTree(
      filePath: json['filePath'] as String,
      root: root,
      symbolTable: symbolTable,
    );
  }

  // -------------------------------------------------------------------------
  // SyntaxNode (GenericSyntaxNode)
  // -------------------------------------------------------------------------

  SyntaxNode _syntaxNodeFromJson(Map<String, dynamic> json) {
    final children = (json['children'] as List<dynamic>)
        .map((e) => _syntaxNodeFromJson(e as Map<String, dynamic>))
        .toList();

    final annotations = (json['annotations'] as List<dynamic>)
        .map((e) => _annotationFromJson(e as Map<String, dynamic>))
        .toList();

    return GenericSyntaxNode(
      nodeId: json['nodeId'] as int,
      kind: json['kind'] as String,
      children: children,
      annotations: annotations,
    );
  }

  // -------------------------------------------------------------------------
  // SymbolTable
  // -------------------------------------------------------------------------

  SymbolTable _symbolTableFromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as Map<String, dynamic>;
    final entries = rawEntries.map((key, value) => MapEntry(
          int.parse(key),
          _resolvedSymbolFromJson(value as Map<String, dynamic>),
        ));

    return SymbolTable(entries: entries);
  }

  // -------------------------------------------------------------------------
  // ResolvedSymbol
  // -------------------------------------------------------------------------

  ResolvedSymbol _resolvedSymbolFromJson(Map<String, dynamic> json) {
    final sourceLocationJson =
        json['sourceLocation'] as Map<String, dynamic>?;
    final sourceLocation = sourceLocationJson != null
        ? _sourceLocationFromJson(sourceLocationJson)
        : null;

    return ResolvedSymbol(
      fullyQualifiedName: json['fullyQualifiedName'] as String,
      assemblyName: json['assemblyName'] as String,
      kind: _symbolKindFromJson(json['kind'] as String),
      sourcePackageId: json['sourcePackageId'] as String?,
      sourceLocation: sourceLocation,
      constantValue: json['constantValue'],
    );
  }

  SymbolKind _symbolKindFromJson(String value) {
    return switch (value) {
      'type' => SymbolKind.type,
      'method' => SymbolKind.method,
      'field' => SymbolKind.field,
      'property' => SymbolKind.property,
      'event' => SymbolKind.event,
      'local' => SymbolKind.local,
      'parameter' => SymbolKind.parameter,
      'unresolved' => SymbolKind.unresolved,
      _ =>
        throw ArgumentError.value(value, 'kind', 'Unknown SymbolKind'),
    };
  }

  SourceLocation _sourceLocationFromJson(Map<String, dynamic> json) {
    return SourceLocation(
      filePath: json['filePath'] as String,
      line: json['line'] as int,
      column: json['column'] as int,
    );
  }

  // -------------------------------------------------------------------------
  // IrType hierarchy
  // -------------------------------------------------------------------------

  IrType _irTypeFromJson(Map<String, dynamic> json) {
    final type = json[r'$type'] as String;
    return switch (type) {
      'NamedType' => _namedTypeFromJson(json),
      'NullableType' => _nullableTypeFromJson(json),
      'FunctionType' => _functionTypeFromJson(json),
      'DynamicType' => const DynamicType(),
      'UnresolvedType' => const UnresolvedType(),
      _ => throw ArgumentError.value(type, r'$type', 'Unknown IrType'),
    };
  }

  NamedType _namedTypeFromJson(Map<String, dynamic> json) {
    final symbol =
        _resolvedSymbolFromJson(json['symbol'] as Map<String, dynamic>);
    final typeArguments = (json['typeArguments'] as List<dynamic>)
        .map((e) => _irTypeFromJson(e as Map<String, dynamic>))
        .toList();

    return NamedType(symbol: symbol, typeArguments: typeArguments);
  }

  NullableType _nullableTypeFromJson(Map<String, dynamic> json) {
    final inner = _irTypeFromJson(json['inner'] as Map<String, dynamic>);
    return NullableType(inner: inner);
  }

  FunctionType _functionTypeFromJson(Map<String, dynamic> json) {
    final parameterTypes = (json['parameterTypes'] as List<dynamic>)
        .map((e) => _irTypeFromJson(e as Map<String, dynamic>))
        .toList();
    final returnType =
        _irTypeFromJson(json['returnType'] as Map<String, dynamic>);

    return FunctionType(parameterTypes: parameterTypes, returnType: returnType);
  }

  // -------------------------------------------------------------------------
  // Annotation types
  // -------------------------------------------------------------------------

  Object _annotationFromJson(Map<String, dynamic> json) {
    final type = json[r'$type'] as String;
    return switch (type) {
      'AsyncAnnotation' => _asyncAnnotationFromJson(json),
      'ConfigureAwaitAnnotation' => _configureAwaitAnnotationFromJson(json),
      'OverflowCheckAnnotation' => _overflowCheckAnnotationFromJson(json),
      'ForeachAnnotation' => _foreachAnnotationFromJson(json),
      'IndexerAnnotation' => _indexerAnnotationFromJson(json),
      'ExtensionAnnotation' => _extensionAnnotationFromJson(json),
      'ExplicitInterfaceAnnotation' =>
        _explicitInterfaceAnnotationFromJson(json),
      'UnsupportedAnnotation' => _unsupportedAnnotationFromJson(json),
      'DeclarationModifiers' => _declarationModifiersFromJson(json),
      _ => throw ArgumentError.value(type, r'$type', 'Unknown annotation type'),
    };
  }

  AsyncAnnotation _asyncAnnotationFromJson(Map<String, dynamic> json) {
    final returnTypeSymbolJson =
        json['returnTypeSymbol'] as Map<String, dynamic>?;
    final returnTypeSymbol = returnTypeSymbolJson != null
        ? _resolvedSymbolFromJson(returnTypeSymbolJson)
        : null;

    return AsyncAnnotation(
      isAsync: json['isAsync'] as bool,
      isIterator: json['isIterator'] as bool,
      isFireAndForget: json['isFireAndForget'] as bool,
      returnTypeSymbol: returnTypeSymbol,
    );
  }

  ConfigureAwaitAnnotation _configureAwaitAnnotationFromJson(
      Map<String, dynamic> json) {
    return ConfigureAwaitAnnotation(
      configureAwait: json['configureAwait'] as bool,
    );
  }

  OverflowCheckAnnotation _overflowCheckAnnotationFromJson(
      Map<String, dynamic> json) {
    return OverflowCheckAnnotation(
      checked: json['checked'] as bool,
    );
  }

  ForeachAnnotation _foreachAnnotationFromJson(Map<String, dynamic> json) {
    final elementType =
        _irTypeFromJson(json['elementType'] as Map<String, dynamic>);
    return ForeachAnnotation(elementType: elementType);
  }

  IndexerAnnotation _indexerAnnotationFromJson(Map<String, dynamic> json) {
    return IndexerAnnotation(
      isIndexer: json['isIndexer'] as bool,
    );
  }

  ExtensionAnnotation _extensionAnnotationFromJson(Map<String, dynamic> json) {
    final extendedType =
        _resolvedSymbolFromJson(json['extendedType'] as Map<String, dynamic>);
    return ExtensionAnnotation(
      isExtension: json['isExtension'] as bool,
      extendedType: extendedType,
    );
  }

  ExplicitInterfaceAnnotation _explicitInterfaceAnnotationFromJson(
      Map<String, dynamic> json) {
    final implementedInterface = _resolvedSymbolFromJson(
        json['implementedInterface'] as Map<String, dynamic>);
    return ExplicitInterfaceAnnotation(
      implementedInterface: implementedInterface,
    );
  }

  UnsupportedAnnotation _unsupportedAnnotationFromJson(
      Map<String, dynamic> json) {
    return UnsupportedAnnotation(
      description: json['description'] as String,
      originalSourceSpan: json['originalSourceSpan'] as String,
    );
  }

  DeclarationModifiers _declarationModifiersFromJson(
      Map<String, dynamic> json) {
    return DeclarationModifiers(
      accessibility: _accessibilityFromJson(json['accessibility'] as String),
      isStatic: json['isStatic'] as bool? ?? false,
      isAbstract: json['isAbstract'] as bool? ?? false,
      isVirtual: json['isVirtual'] as bool? ?? false,
      isOverride: json['isOverride'] as bool? ?? false,
      isSealed: json['isSealed'] as bool? ?? false,
      isReadonly: json['isReadonly'] as bool? ?? false,
      isConst: json['isConst'] as bool? ?? false,
      isExtern: json['isExtern'] as bool? ?? false,
      isNew: json['isNew'] as bool? ?? false,
      isOperator: json['isOperator'] as bool? ?? false,
      isConversion: json['isConversion'] as bool? ?? false,
      isImplicit: json['isImplicit'] as bool? ?? false,
      isExplicit: json['isExplicit'] as bool? ?? false,
      isExtension: json['isExtension'] as bool? ?? false,
      isIndexer: json['isIndexer'] as bool? ?? false,
    );
  }

  Accessibility _accessibilityFromJson(String value) {
    return switch (value) {
      'public' => Accessibility.public,
      'internal' => Accessibility.internal,
      'protected' => Accessibility.protected,
      'protectedInternal' => Accessibility.protectedInternal,
      'privateProtected' => Accessibility.privateProtected,
      'private' => Accessibility.private,
      _ => throw ArgumentError.value(
          value, 'accessibility', 'Unknown Accessibility'),
    };
  }

  // -------------------------------------------------------------------------
  // Diagnostic
  // -------------------------------------------------------------------------

  Diagnostic _diagnosticFromJson(Map<String, dynamic> json) {
    final locationJson = json['location'] as Map<String, dynamic>?;
    final location =
        locationJson != null ? _sourceLocationFromJson(locationJson) : null;

    return Diagnostic(
      severity: _diagnosticSeverityFromJson(json['severity'] as String),
      code: json['code'] as String,
      message: json['message'] as String,
      source: json['source'] as String?,
      location: location,
    );
  }

  DiagnosticSeverity _diagnosticSeverityFromJson(String value) {
    return switch (value) {
      'error' => DiagnosticSeverity.error,
      'warning' => DiagnosticSeverity.warning,
      'info' => DiagnosticSeverity.info,
      _ => throw ArgumentError.value(
          value, 'severity', 'Unknown DiagnosticSeverity'),
    };
  }
}
