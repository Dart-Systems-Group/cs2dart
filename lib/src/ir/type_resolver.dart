import '../roslyn_frontend/models/ir_type.dart' as frontend;
import '../roslyn_frontend/models/resolved_symbol.dart';
import 'diagnostic_collector.dart';
import 'models/ir_nodes.dart';

export 'models/ir_type.dart';

/// Maps [frontend.IrType] records (from the Roslyn_Frontend) to the
/// [IrType] hierarchy used by the IR stage.
///
/// The TypeResolver has no dependency on Roslyn. All type information is
/// read from the plain-data [frontend.IrType] and [ResolvedSymbol] records
/// produced by the Roslyn_Frontend.
///
/// ### Mapping rules
///
/// | Frontend type                                  | IR type                                  |
/// |------------------------------------------------|------------------------------------------|
/// | `NamedType` with primitive FQN                 | `PrimitiveType`                          |
/// | `NamedType` with FQN `System.Void`             | `VoidType`                               |
/// | `NamedType` with FQN `dynamic`                 | `DynamicType` + IR0010 Warning           |
/// | `NamedType` with type-parameter FQN            | `TypeParameterType`                      |
/// | `NamedType` with generic args                  | `GenericType(NamedType, [...])`           |
/// | `NamedType` (other)                            | `NamedType`                              |
/// | `NullableType(NamedType<primitive>)`           | `NullableType(PrimitiveType)`            |
/// | `NullableType(NamedType<string>)`              | `NullableType(NamedType)`                |
/// | `NullableType(other)`                          | `NullableType(resolved inner)`           |
/// | `FunctionType`                                 | `FunctionType`                           |
/// | `DynamicType`                                  | `DynamicType` + IR0010 Warning           |
/// | `UnresolvedType`                               | `UnresolvedType`                         |
final class TypeResolver {
  final DiagnosticCollector _diagnostics;

  /// Creates a [TypeResolver] that emits diagnostics into [diagnostics].
  TypeResolver({required DiagnosticCollector diagnostics})
      : _diagnostics = diagnostics;

  // ---------------------------------------------------------------------------
  // Primitive CLR type names (short names used in C# source and FQNs)
  // ---------------------------------------------------------------------------

  /// Short C# keyword names that map to CLR primitive types.
  static const Set<String> _primitiveKeywords = {
    'int',
    'long',
    'short',
    'byte',
    'sbyte',
    'uint',
    'ulong',
    'ushort',
    'float',
    'double',
    'decimal',
    'bool',
    'char',
    'string',
    'object',
  };

  /// Fully-qualified CLR names for primitive types.
  static const Map<String, String> _fqnToPrimitiveName = {
    'System.Int32': 'int',
    'System.Int64': 'long',
    'System.Int16': 'short',
    'System.Byte': 'byte',
    'System.SByte': 'sbyte',
    'System.UInt32': 'uint',
    'System.UInt64': 'ulong',
    'System.UInt16': 'ushort',
    'System.Single': 'float',
    'System.Double': 'double',
    'System.Decimal': 'decimal',
    'System.Boolean': 'bool',
    'System.Char': 'char',
    'System.String': 'string',
    'System.Object': 'object',
  };

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Resolves a [frontend.IrType] to the corresponding IR [IrType].
  ///
  /// Emits an `IR0010` Warning diagnostic into the [DiagnosticCollector] when
  /// the type is `dynamic`.
  ///
  /// [sourceLocation] is attached to any emitted diagnostic.
  IrType resolve(
    frontend.IrType frontendType, {
    SourceLocation? sourceLocation,
    String? sourceFile,
    List<TypeParameterNode> enclosingTypeParameters = const [],
  }) {
    return switch (frontendType) {
      frontend.DynamicType() => _resolveDynamic(
          sourceLocation: sourceLocation,
          sourceFile: sourceFile,
        ),
      frontend.UnresolvedType() => const UnresolvedType(),
      frontend.NullableType(:final inner) => NullableType(
          inner: resolve(
            inner,
            sourceLocation: sourceLocation,
            sourceFile: sourceFile,
            enclosingTypeParameters: enclosingTypeParameters,
          ),
        ),
      frontend.FunctionType(:final parameterTypes, :final returnType) =>
        _resolveFunctionType(
          parameterTypes,
          returnType,
          sourceLocation: sourceLocation,
          sourceFile: sourceFile,
          enclosingTypeParameters: enclosingTypeParameters,
        ),
      frontend.NamedType(:final symbol, :final typeArguments) =>
        _resolveNamedType(
          symbol,
          typeArguments,
          sourceLocation: sourceLocation,
          sourceFile: sourceFile,
          enclosingTypeParameters: enclosingTypeParameters,
        ),
    };
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Resolves a [frontend.NamedType] to the appropriate IR type.
  IrType _resolveNamedType(
    ResolvedSymbol symbol,
    List<frontend.IrType> typeArguments, {
    SourceLocation? sourceLocation,
    String? sourceFile,
    List<TypeParameterNode> enclosingTypeParameters = const [],
  }) {
    final fqn = symbol.fullyQualifiedName;

    // void
    if (fqn == 'System.Void' || fqn == 'void') {
      return const VoidType();
    }

    // dynamic
    if (fqn == 'dynamic') {
      return _resolveDynamic(
        sourceLocation: sourceLocation,
        sourceFile: sourceFile,
      );
    }

    // Primitive CLR types — check FQN first, then short keyword name
    final primitiveFromFqn = _fqnToPrimitiveName[fqn];
    if (primitiveFromFqn != null) {
      return PrimitiveType(name: primitiveFromFqn);
    }

    // Short keyword names (e.g. when FQN is just "int", "bool", etc.)
    if (_primitiveKeywords.contains(fqn)) {
      return PrimitiveType(name: fqn);
    }

    // Open generic type parameter — check if the FQN matches one of the
    // enclosing type parameters by name (type params have simple names like
    // "T", "TKey", "TValue").
    if (_isTypeParameter(fqn, enclosingTypeParameters)) {
      return TypeParameterType(name: fqn);
    }

    // Closed generic type: NamedType with type arguments
    if (typeArguments.isNotEmpty) {
      final resolvedArgs = typeArguments
          .map(
            (arg) => resolve(
              arg,
              sourceLocation: sourceLocation,
              sourceFile: sourceFile,
              enclosingTypeParameters: enclosingTypeParameters,
            ),
          )
          .toList();

      // Strip generic arity suffix from FQN for the base type, e.g.
      // "System.Collections.Generic.List`1" → "System.Collections.Generic.List"
      final baseFqn = _stripGenericArity(fqn);
      return GenericType(
        baseType: NamedType(fullyQualifiedName: baseFqn),
        typeArguments: resolvedArgs,
      );
    }

    // Plain named type
    return NamedType(fullyQualifiedName: fqn);
  }

  /// Resolves a [frontend.FunctionType] to a [FunctionType].
  IrType _resolveFunctionType(
    List<frontend.IrType> parameterTypes,
    frontend.IrType returnType, {
    SourceLocation? sourceLocation,
    String? sourceFile,
    List<TypeParameterNode> enclosingTypeParameters = const [],
  }) {
    final resolvedParams = parameterTypes
        .map(
          (p) => resolve(
            p,
            sourceLocation: sourceLocation,
            sourceFile: sourceFile,
            enclosingTypeParameters: enclosingTypeParameters,
          ),
        )
        .toList();

    final resolvedReturn = resolve(
      returnType,
      sourceLocation: sourceLocation,
      sourceFile: sourceFile,
      enclosingTypeParameters: enclosingTypeParameters,
    );

    return FunctionType(
      parameterTypes: resolvedParams,
      returnType: resolvedReturn,
    );
  }

  /// Emits an IR0010 Warning and returns [DynamicType].
  IrType _resolveDynamic({
    SourceLocation? sourceLocation,
    String? sourceFile,
  }) {
    _diagnostics.warn(
      'IR0010',
      'Use of dynamic type detected. '
          'The dynamic type has limited support in the Dart code generator.',
      source: sourceFile,
      location: sourceLocation,
    );
    return const DynamicType();
  }

  /// Returns true if [fqn] matches the name of any enclosing type parameter.
  ///
  /// Type parameter names are simple identifiers (e.g. "T", "TKey") and their
  /// FQN in the [ResolvedSymbol] is just the parameter name itself.
  bool _isTypeParameter(
    String fqn,
    List<TypeParameterNode> enclosingTypeParameters,
  ) {
    // A type parameter FQN is just its simple name (no dots, no backticks).
    if (fqn.contains('.') || fqn.contains('`')) return false;
    return enclosingTypeParameters.any((tp) => tp.name == fqn);
  }

  /// Strips the generic arity suffix from a fully-qualified name.
  ///
  /// For example:
  /// - `"System.Collections.Generic.List\`1"` → `"System.Collections.Generic.List"`
  /// - `"System.Collections.Generic.Dictionary\`2"` → `"System.Collections.Generic.Dictionary"`
  /// - `"MyClass"` → `"MyClass"` (unchanged)
  static String _stripGenericArity(String fqn) {
    final backtickIndex = fqn.indexOf('`');
    return backtickIndex >= 0 ? fqn.substring(0, backtickIndex) : fqn;
  }
}
