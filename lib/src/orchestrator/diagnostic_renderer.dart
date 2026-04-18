import 'dart:io';

import '../project_loader/models/diagnostic.dart';
import 'models/transpiler_result.dart';

/// Formats and renders [Diagnostic] instances to stdout/stderr for CLI output.
final class DiagnosticRenderer {
  DiagnosticRenderer._();

  /// Formats a single diagnostic to the CLI output format.
  ///
  /// Format: `<severity> <CODE>: <MESSAGE> [<SOURCE>:<LINE>:<COLUMN>]`
  ///
  /// - `<severity>` is `error`, `warning`, or `info` (lowercase).
  /// - The `[<SOURCE>:<LINE>:<COLUMN>]` bracket is omitted when [source] is null.
  /// - When [source] is present but [location] is null, the bracket is `[<SOURCE>]`.
  /// - When both [source] and [location] are present, the bracket is
  ///   `[<SOURCE>:<LINE>:<COLUMN>]`.
  static String format(Diagnostic d) {
    final severityLabel = switch (d.severity) {
      DiagnosticSeverity.error => 'error',
      DiagnosticSeverity.warning => 'warning',
      DiagnosticSeverity.info => 'info',
    };

    final buffer = StringBuffer()
      ..write(severityLabel)
      ..write(' ')
      ..write(d.code)
      ..write(': ')
      ..write(d.message);

    if (d.source != null) {
      buffer.write(' [');
      buffer.write(d.source);
      if (d.location != null) {
        buffer.write(':');
        buffer.write(d.location!.line);
        buffer.write(':');
        buffer.write(d.location!.column);
      }
      buffer.write(']');
    }

    return buffer.toString();
  }

  /// Renders all diagnostics from [result] to stdout/stderr according to the
  /// [verbose] setting, then prints the summary line.
  ///
  /// Routing rules:
  /// - `Error` and `Warning` diagnostics → stderr
  /// - `Info` diagnostics → stdout, only when [verbose] is `true`
  ///
  /// Summary line:
  /// - Success: stdout → `Transpilation succeeded. <N> package(s) written to <dir>.`
  /// - Failure: stderr → `Transpilation failed with <E> error(s) and <W> warning(s).`
  ///
  /// When [verbose] is `false`, [result.success] is `true`, and there are no
  /// `Warning` diagnostics, no output is produced at all (silent clean run).
  static void renderAll(
    TranspilerResult result, {
    required bool verbose,
    String? outputDirectory,
  }) {
    var errorCount = 0;
    var warningCount = 0;

    for (final d in result.diagnostics) {
      switch (d.severity) {
        case DiagnosticSeverity.error:
          errorCount++;
          stderr.writeln(format(d));
        case DiagnosticSeverity.warning:
          warningCount++;
          stderr.writeln(format(d));
        case DiagnosticSeverity.info:
          if (verbose) {
            stdout.writeln(format(d));
          }
      }
    }

    if (result.success) {
      // Silent clean run: no output when not verbose, no warnings, and success.
      if (!verbose && warningCount == 0) return;

      final n = result.packages.length;
      final dir = outputDirectory ?? '';
      stdout.writeln('Transpilation succeeded. $n package(s) written to $dir.');
    } else {
      stderr.writeln(
        'Transpilation failed with $errorCount error(s) and $warningCount warning(s).',
      );
    }
  }
}
