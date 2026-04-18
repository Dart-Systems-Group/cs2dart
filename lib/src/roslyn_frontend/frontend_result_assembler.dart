import '../config/models/source_location.dart';
import '../project_loader/models/load_result.dart';
import 'models/frontend_result.dart';

/// Dart-side post-processing that merges [LoadResult] diagnostics into the
/// worker-produced [FrontendResult] and computes the final [FrontendResult.success].
final class FrontendResultAssembler {
  const FrontendResultAssembler();

  /// Merges [workerResult] with [loadResult] diagnostics and sets [FrontendResult.success].
  ///
  /// - Prepends all `PL`-prefixed diagnostics from [loadResult.diagnostics] unchanged.
  /// - Appends worker diagnostics after the PL diagnostics.
  /// - Deduplicates diagnostics with the same [Diagnostic.code] AND [Diagnostic.source]
  ///   AND [Diagnostic.location] (line + column); emits one `RF0012` Warning per suppressed
  ///   duplicate.
  /// - Sets [FrontendResult.success] to `true` iff no [DiagnosticSeverity.error]-severity
  ///   diagnostic is present in the merged list.
  FrontendResult assemble(
    FrontendResult workerResult,
    LoadResult loadResult,
  ) {
    // 1. Collect PL-prefixed diagnostics from loadResult.
    final plDiagnostics = loadResult.diagnostics
        .where((d) => d.code.startsWith('PL'))
        .toList();

    // 2. Build the merged list: PL first, then worker diagnostics.
    final merged = <Diagnostic>[
      ...plDiagnostics,
      ...workerResult.diagnostics,
    ];

    // 3. Deduplicate: track seen (code, source, location) tuples.
    final seen = <_DiagnosticKey>{};
    final deduplicated = <Diagnostic>[];
    final rf0012Warnings = <Diagnostic>[];

    for (final diag in merged) {
      final key = _DiagnosticKey(diag.code, diag.source, diag.location);
      if (seen.contains(key)) {
        // Emit RF0012 Warning for each suppressed duplicate.
        rf0012Warnings.add(
          Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'RF0012',
            message: _buildRf0012Message(diag),
            source: diag.source,
            location: diag.location,
          ),
        );
      } else {
        seen.add(key);
        deduplicated.add(diag);
      }
    }

    // Append RF0012 warnings after the deduplicated list.
    final finalDiagnostics = [...deduplicated, ...rf0012Warnings];

    // 4. Compute success: true iff no Error-severity diagnostic is present.
    final success = !finalDiagnostics
        .any((d) => d.severity == DiagnosticSeverity.error);

    return FrontendResult(
      units: workerResult.units,
      diagnostics: finalDiagnostics,
      success: success,
    );
  }

  String _buildRf0012Message(Diagnostic suppressed) {
    final loc = suppressed.location;
    if (loc != null) {
      return 'Duplicate diagnostic suppressed: ${suppressed.code} '
          'at ${suppressed.source ?? '<unknown>'}:${loc.line}:${loc.column}';
    }
    final src = suppressed.source;
    if (src != null) {
      return 'Duplicate diagnostic suppressed: ${suppressed.code} in $src';
    }
    return 'Duplicate diagnostic suppressed: ${suppressed.code}';
  }
}

/// Key used for deduplication: (code, source, location).
final class _DiagnosticKey {
  final String code;
  final String? source;
  final SourceLocation? location;

  const _DiagnosticKey(this.code, this.source, this.location);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _DiagnosticKey &&
          code == other.code &&
          source == other.source &&
          location == other.location;

  @override
  int get hashCode => Object.hash(code, source, location);
}
