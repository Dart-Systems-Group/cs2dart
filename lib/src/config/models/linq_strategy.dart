/// Controls how LINQ expressions are transpiled to Dart.
enum LinqStrategy {
  /// Preserve functional collection method chains (YAML: "preserve_functional").
  preserveFunctional,

  /// Lower LINQ queries to imperative loops (YAML: "lower_to_loops").
  lowerToLoops;

  /// The YAML string value for this strategy.
  String get yamlValue => switch (this) {
        LinqStrategy.preserveFunctional => 'preserve_functional',
        LinqStrategy.lowerToLoops => 'lower_to_loops',
      };

  /// Returns the [LinqStrategy] for the given YAML string, or null if unrecognized.
  static LinqStrategy? fromYaml(String value) => switch (value) {
        'preserve_functional' => LinqStrategy.preserveFunctional,
        'lower_to_loops' => LinqStrategy.lowerToLoops,
        _ => null,
      };
}
