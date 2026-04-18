/// Controls how C# events are transpiled to Dart.
///
/// Only [stream] is supported; C# events are always emitted as Dart [Stream]s.
enum EventStrategy {
  /// Emit events as Dart [Stream]s (YAML: "stream").
  stream;

  /// The YAML string value for this strategy.
  String get yamlValue => 'stream';

  /// Returns the [EventStrategy] for the given YAML string, or null if unrecognized.
  static EventStrategy? fromYaml(String value) => switch (value) {
        'stream' => EventStrategy.stream,
        _ => null,
      };
}
