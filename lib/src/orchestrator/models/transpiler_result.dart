import '../../project_loader/models/diagnostic.dart';
import 'stage_results.dart';

export 'stage_results.dart' show OutputPackage;

/// The assembled output of a complete (or early-exited) pipeline run.
///
/// [success] is true iff no [DiagnosticSeverity.error]-severity diagnostic
/// is present in [diagnostics].
final class TranspilerResult {
  /// True when no Error-severity diagnostic is present in [diagnostics].
  final bool success;

  /// The generated Dart packages.
  ///
  /// Empty when the pipeline performed an Early_Exit.
  final List<OutputPackage> packages;

  /// All diagnostics from every stage that ran, in stage order:
  /// CFG → PL → NR → RF → IR → CG → VA → OR.
  final List<Diagnostic> diagnostics;

  const TranspilerResult({
    required this.success,
    required this.packages,
    required this.diagnostics,
  });
}
