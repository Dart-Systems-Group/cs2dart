import '../../config/models/diagnostic_severity.dart';
import '../../config/models/source_location.dart';

export '../../config/models/diagnostic_severity.dart';

/// A structured diagnostic message conforming to the pipeline-wide schema.
///
/// Diagnostic codes use a prefix followed by a 4-digit number, e.g.:
/// - `PL0001` — Project_Loader diagnostics
/// - `NR0001` — NuGet_Handler diagnostics
/// - `CS0001` — Roslyn compiler diagnostics
final class Diagnostic {
  /// The severity of this diagnostic.
  final DiagnosticSeverity severity;

  /// Unique diagnostic code, e.g. "PL0001" or "NR0042".
  final String code;

  /// Human-readable description of the diagnostic.
  final String message;

  /// Optional file path where the diagnostic was triggered.
  final String? source;

  /// Optional source location (line and column) within [source].
  final SourceLocation? location;

  const Diagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.source,
    this.location,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Diagnostic &&
          severity == other.severity &&
          code == other.code &&
          message == other.message &&
          source == other.source &&
          location == other.location;

  @override
  int get hashCode => Object.hash(severity, code, message, source, location);

  @override
  String toString() {
    final loc = location != null ? ' at $location' : '';
    final src = source != null ? ' ($source$loc)' : '';
    return '[$severity] $code$src: $message';
  }
}
