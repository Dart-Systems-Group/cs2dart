import 'diagnostic_severity.dart';
import 'source_location.dart';

/// A structured diagnostic message produced by the Config_Service.
///
/// Diagnostic codes are in the range CFG0001–CFG9999.
final class ConfigDiagnostic {
  final DiagnosticSeverity severity;

  /// Unique diagnostic code, e.g. "CFG0001".
  final String code;

  final String message;

  /// Optional source location where the diagnostic was triggered.
  final SourceLocation? location;

  const ConfigDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.location,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfigDiagnostic &&
          severity == other.severity &&
          code == other.code &&
          message == other.message &&
          location == other.location;

  @override
  int get hashCode => Object.hash(severity, code, message, location);

  @override
  String toString() {
    final loc = location != null ? ' at $location' : '';
    return '[$severity] $code$loc: $message';
  }
}
