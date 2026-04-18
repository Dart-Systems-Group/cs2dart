import 'resolved_symbol.dart';

/// The type annotation attached to every expression node in a
/// [NormalizedSyntaxTree]. Expressed as a sealed class hierarchy so the
/// IR_Builder can pattern-match exhaustively.
sealed class IrType {
  const IrType();
}

/// A named type, e.g. int, string, List<T>.
final class NamedType extends IrType {
  /// The resolved symbol for this type.
  final ResolvedSymbol symbol;

  /// Type arguments for generic types; empty for non-generic types.
  final List<IrType> typeArguments;

  const NamedType({required this.symbol, this.typeArguments = const []});
}

/// A nullable wrapper: T? (both reference and value types).
final class NullableType extends IrType {
  /// The underlying non-nullable type.
  final IrType inner;

  const NullableType({required this.inner});
}

/// A function type: (T1, T2) -> TReturn.
final class FunctionType extends IrType {
  /// The types of the function parameters, in order.
  final List<IrType> parameterTypes;

  /// The return type of the function.
  final IrType returnType;

  const FunctionType({required this.parameterTypes, required this.returnType});
}

/// Represents the C# `dynamic` type — emits a Warning diagnostic.
final class DynamicType extends IrType {
  const DynamicType();
}

/// Sentinel: [SemanticModel.GetTypeInfo] returned null or error type.
final class UnresolvedType extends IrType {
  const UnresolvedType();
}
