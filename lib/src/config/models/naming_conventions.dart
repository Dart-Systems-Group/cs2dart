import 'case_style.dart';

/// Configuration for naming convention rules applied to generated Dart identifiers.
final class NamingConventions {
  /// Casing for generated class names.
  ///
  /// Default: [CaseStyle.pascalCase]
  final CaseStyle classNameStyle;

  /// Casing for generated method names.
  ///
  /// Default: [CaseStyle.camelCase]
  final CaseStyle methodNameStyle;

  /// Casing for generated field names.
  ///
  /// Default: [CaseStyle.camelCase]
  final CaseStyle fieldNameStyle;

  /// Casing for generated file names.
  ///
  /// Default: [CaseStyle.snakeCase]
  final CaseStyle fileNameStyle;

  /// Prefix for library-private identifiers.
  ///
  /// Default: `"_"`
  final String privatePrefix;

  const NamingConventions({
    this.classNameStyle = CaseStyle.pascalCase,
    this.methodNameStyle = CaseStyle.camelCase,
    this.fieldNameStyle = CaseStyle.camelCase,
    this.fileNameStyle = CaseStyle.snakeCase,
    this.privatePrefix = '_',
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NamingConventions) return false;
    return classNameStyle == other.classNameStyle &&
        methodNameStyle == other.methodNameStyle &&
        fieldNameStyle == other.fieldNameStyle &&
        fileNameStyle == other.fileNameStyle &&
        privatePrefix == other.privatePrefix;
  }

  @override
  int get hashCode => Object.hash(
        classNameStyle,
        methodNameStyle,
        fieldNameStyle,
        fileNameStyle,
        privatePrefix,
      );
}
