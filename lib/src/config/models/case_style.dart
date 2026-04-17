/// Naming case style for generated Dart identifiers.
enum CaseStyle {
  /// PascalCase (YAML: "PascalCase").
  pascalCase,

  /// camelCase (YAML: "camelCase").
  camelCase,

  /// snake_case (YAML: "snake_case").
  snakeCase,

  /// SCREAMING_SNAKE_CASE (YAML: "SCREAMING_SNAKE_CASE").
  screamingSnakeCase;

  /// The YAML string value for this case style.
  String get yamlValue => switch (this) {
        CaseStyle.pascalCase => 'PascalCase',
        CaseStyle.camelCase => 'camelCase',
        CaseStyle.snakeCase => 'snake_case',
        CaseStyle.screamingSnakeCase => 'SCREAMING_SNAKE_CASE',
      };

  /// Returns the [CaseStyle] for the given YAML string, or null if unrecognized.
  static CaseStyle? fromYaml(String value) => switch (value) {
        'PascalCase' => CaseStyle.pascalCase,
        'camelCase' => CaseStyle.camelCase,
        'snake_case' => CaseStyle.snakeCase,
        'SCREAMING_SNAKE_CASE' => CaseStyle.screamingSnakeCase,
        _ => null,
      };
}
