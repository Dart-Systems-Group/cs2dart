/// Configuration for how C# nullable reference types are mapped to Dart null-safety.
final class NullabilityConfig {
  /// When true, `T?` parameters are emitted as optional Dart parameters.
  ///
  /// Default: false
  final bool treatNullableAsOptional;

  /// When true, non-nullable dereferences emit `!` assertions.
  ///
  /// Default: false
  final bool emitNullAsserts;

  /// When true, all `?` annotations from C# are preserved in Dart.
  /// When false, all types are emitted as non-nullable in Dart.
  ///
  /// Default: true
  final bool preserveNullableAnnotations;

  const NullabilityConfig({
    this.treatNullableAsOptional = false,
    this.emitNullAsserts = false,
    this.preserveNullableAnnotations = true,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NullabilityConfig) return false;
    return treatNullableAsOptional == other.treatNullableAsOptional &&
        emitNullAsserts == other.emitNullAsserts &&
        preserveNullableAnnotations == other.preserveNullableAnnotations;
  }

  @override
  int get hashCode => Object.hash(
        treatNullableAsOptional,
        emitNullAsserts,
        preserveNullableAnnotations,
      );
}
