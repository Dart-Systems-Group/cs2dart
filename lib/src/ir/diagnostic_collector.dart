import '../project_loader/models/diagnostic.dart';
import '../config/models/source_location.dart';

export '../project_loader/models/diagnostic.dart';

/// Accumulates IR-prefixed diagnostics during IR_Builder processing.
///
/// Diagnostics are deduplicated by `(code, source, location)` before being
/// stored, satisfying Property 15 (no duplicate diagnostics for same location
/// and code).
final class DiagnosticCollector {
  final List<Diagnostic> _diagnostics = [];

  /// All diagnostics collected so far, in insertion order.
  List<Diagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  /// Adds [diagnostic] to the collection, deduplicating by
  /// `(code, source, location)`.
  void add(Diagnostic diagnostic) {
    final isDuplicate = _diagnostics.any(
      (d) =>
          d.code == diagnostic.code &&
          d.source == diagnostic.source &&
          d.location == diagnostic.location,
    );
    if (!isDuplicate) {
      _diagnostics.add(diagnostic);
    }
  }

  /// Emits a Warning diagnostic with the given [code] and [message].
  void warn(
    String code,
    String message, {
    String? source,
    SourceLocation? location,
  }) {
    add(
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: code,
        message: message,
        source: source,
        location: location,
      ),
    );
  }

  /// Emits an Error diagnostic with the given [code] and [message].
  void error(
    String code,
    String message, {
    String? source,
    SourceLocation? location,
  }) {
    add(
      Diagnostic(
        severity: DiagnosticSeverity.error,
        code: code,
        message: message,
        source: source,
        location: location,
      ),
    );
  }

  /// Returns true if any Error-severity diagnostic has been collected.
  bool get hasErrors =>
      _diagnostics.any((d) => d.severity == DiagnosticSeverity.error);
}
