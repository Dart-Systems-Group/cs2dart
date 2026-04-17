/// Controls how C# events are transpiled to Dart.
enum EventStrategy {
  /// Emit events as Dart [Stream]s (YAML: "stream").
  stream,

  /// Emit events as callback functions (YAML: "callback").
  callback;

  /// The YAML string value for this strategy.
  String get yamlValue => switch (this) {
        EventStrategy.stream => 'stream',
        EventStrategy.callback => 'callback',
      };

  /// Returns the [EventStrategy] for the given YAML string, or null if unrecognized.
  static EventStrategy? fromYaml(String value) => switch (value) {
        'stream' => EventStrategy.stream,
        'callback' => EventStrategy.callback,
        _ => null,
      };
}
