/// Per-struct BCL override for how a specific C# struct is mapped to a Dart type.
final class StructMappingOverride {
  /// Override the generated Dart type name.
  ///
  /// When null, the type name is derived from the C# struct name.
  final String? dartType;

  /// The Dart package that provides [dartType].
  ///
  /// When null, no package import is added.
  final String? dartPackage;

  const StructMappingOverride({this.dartType, this.dartPackage});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StructMappingOverride) return false;
    return dartType == other.dartType && dartPackage == other.dartPackage;
  }

  @override
  int get hashCode => Object.hash(dartType, dartPackage);
}
