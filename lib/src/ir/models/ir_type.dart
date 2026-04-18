/// The type hierarchy for IR type nodes.
///
/// Every expression, parameter, field, property, and local declaration
/// carries an [IrType] that fully describes the C# type.
sealed class IrType {
  const IrType();
}

/// A C# primitive type: int, long, double, bool, char, byte, etc.
final class PrimitiveType extends IrType {
  /// The CLR primitive type name, e.g. "int", "long", "bool", "string".
  final String name;

  const PrimitiveType({required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PrimitiveType && name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'PrimitiveType($name)';
}

/// A named (non-primitive) type, e.g. `MyClass`, `System.DateTime`.
final class NamedType extends IrType {
  /// The fully-qualified CLR type name.
  final String fullyQualifiedName;

  const NamedType({required this.fullyQualifiedName});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NamedType && fullyQualifiedName == other.fullyQualifiedName;

  @override
  int get hashCode => fullyQualifiedName.hashCode;

  @override
  String toString() => 'NamedType($fullyQualifiedName)';
}

/// A closed generic type, e.g. `List<int>`, `Dictionary<string, int>`.
final class GenericType extends IrType {
  /// The base (open) type, e.g. `NamedType("System.Collections.Generic.List")`.
  final IrType baseType;

  /// The resolved type arguments, in declaration order.
  final List<IrType> typeArguments;

  const GenericType({required this.baseType, required this.typeArguments});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenericType &&
          baseType == other.baseType &&
          _listEquals(typeArguments, other.typeArguments);

  @override
  int get hashCode => Object.hash(baseType, Object.hashAll(typeArguments));

  @override
  String toString() => 'GenericType($baseType, $typeArguments)';
}

/// An array type, e.g. `int[]`, `string[][]`.
final class ArrayType extends IrType {
  /// The element type.
  final IrType elementType;

  /// The number of dimensions (1 for `T[]`, 2 for `T[,]`, etc.).
  final int rank;

  const ArrayType({required this.elementType, this.rank = 1});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrayType &&
          elementType == other.elementType &&
          rank == other.rank;

  @override
  int get hashCode => Object.hash(elementType, rank);

  @override
  String toString() => 'ArrayType($elementType, rank: $rank)';
}

/// A nullable wrapper: `T?` (both reference and value types).
final class NullableType extends IrType {
  /// The underlying non-nullable type.
  final IrType inner;

  const NullableType({required this.inner});

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NullableType && inner == other.inner;

  @override
  int get hashCode => inner.hashCode;

  @override
  String toString() => 'NullableType($inner)';
}

/// A C# tuple type, e.g. `(int x, string y)`.
final class TupleType extends IrType {
  /// The named element types, in declaration order.
  final List<TupleElement> elements;

  const TupleType({required this.elements});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TupleType && _listEquals(elements, other.elements);

  @override
  int get hashCode => Object.hashAll(elements);

  @override
  String toString() => 'TupleType($elements)';
}

/// A single element of a [TupleType].
final class TupleElement {
  /// The element name; null for unnamed tuple elements.
  final String? name;

  /// The element type.
  final IrType type;

  const TupleElement({this.name, required this.type});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TupleElement && name == other.name && type == other.type;

  @override
  int get hashCode => Object.hash(name, type);
}

/// A delegate or lambda type: `(T1, T2) -> TReturn`.
final class FunctionType extends IrType {
  /// The parameter types, in declaration order.
  final List<IrType> parameterTypes;

  /// The return type.
  final IrType returnType;

  const FunctionType({required this.parameterTypes, required this.returnType});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FunctionType &&
          _listEquals(parameterTypes, other.parameterTypes) &&
          returnType == other.returnType;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(parameterTypes), returnType);

  @override
  String toString() => 'FunctionType($parameterTypes -> $returnType)';
}

/// The C# `void` return type.
final class VoidType extends IrType {
  const VoidType();

  @override
  bool operator ==(Object other) => other is VoidType;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'VoidType';
}

/// The C# `dynamic` type — emits an IR0010 Warning diagnostic.
final class DynamicType extends IrType {
  const DynamicType();

  @override
  bool operator ==(Object other) => other is DynamicType;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'DynamicType';
}

/// An open generic type parameter, e.g. `T` in `List<T>`.
final class TypeParameterType extends IrType {
  /// The name of the type parameter.
  final String name;

  const TypeParameterType({required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TypeParameterType && name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'TypeParameterType($name)';
}

/// Sentinel: type resolution failed (e.g., Roslyn binding error).
final class UnresolvedType extends IrType {
  const UnresolvedType();

  @override
  bool operator ==(Object other) => other is UnresolvedType;

  @override
  int get hashCode => 2;

  @override
  String toString() => 'UnresolvedType';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
