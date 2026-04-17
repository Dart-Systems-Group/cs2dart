import 'event_strategy.dart';

/// Per-event override for how a specific C# event is transpiled to Dart.
final class EventMappingOverride {
  /// Override the event strategy for this specific event.
  ///
  /// When null, the global [EventStrategy] is used.
  final EventStrategy? strategy;

  /// Override the generated Dart event name.
  ///
  /// When null, the name is derived from the C# event name.
  final String? dartEventName;

  const EventMappingOverride({this.strategy, this.dartEventName});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EventMappingOverride) return false;
    return strategy == other.strategy && dartEventName == other.dartEventName;
  }

  @override
  int get hashCode => Object.hash(strategy, dartEventName);
}
