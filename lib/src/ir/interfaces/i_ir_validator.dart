import '../models/ir_build_result.dart';

export '../models/ir_build_result.dart';

/// The public interface for the IR_Validator stage.
///
/// Checks structural and semantic invariants on a completed IR tree.
/// Never throws; collects all violations before returning.
abstract interface class IIrValidator {
  /// Validates structural and semantic invariants on [unit].
  ///
  /// Returns a (possibly empty) list of IR-prefixed diagnostics.
  /// All violations are collected before returning — validation does not
  /// stop on the first error.
  ///
  /// Completes in O(n) time proportional to the number of IR nodes.
  List<Diagnostic> validate(IrCompilationUnit unit);
}
