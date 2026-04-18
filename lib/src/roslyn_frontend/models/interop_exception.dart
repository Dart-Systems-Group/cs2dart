/// Thrown by [IInteropBridge.invoke] when the .NET worker process exits
/// unexpectedly or returns a malformed response.
final class InteropException implements Exception {
  final String message;
  final Object? cause;

  const InteropException({required this.message, this.cause});

  @override
  String toString() =>
      'InteropException: $message${cause != null ? ' (caused by: $cause)' : ''}';
}
