/// Configuration for how C# async patterns are mapped to Dart.
final class AsyncConfig {
  /// When true, `ConfigureAwait(false)` calls are silently dropped.
  ///
  /// Default: false
  final bool omitConfigureAwait;

  /// When true, `ValueTask<T>` is mapped to `Future<T>`.
  ///
  /// Default: true
  final bool mapValueTaskToFuture;

  const AsyncConfig({
    this.omitConfigureAwait = false,
    this.mapValueTaskToFuture = true,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AsyncConfig) return false;
    return omitConfigureAwait == other.omitConfigureAwait &&
        mapValueTaskToFuture == other.mapValueTaskToFuture;
  }

  @override
  int get hashCode => Object.hash(omitConfigureAwait, mapValueTaskToFuture);
}
