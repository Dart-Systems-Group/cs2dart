import '../../roslyn_frontend/models/frontend_result.dart';
import '../models/ir_build_result.dart';

export '../../roslyn_frontend/models/frontend_result.dart';
export '../models/ir_build_result.dart';

/// The public interface for the IR_Builder stage.
///
/// Accepts a [FrontendResult] from the Roslyn_Frontend and produces an
/// [IrBuildResult] containing the language-agnostic IR tree.
///
/// The IR_Builder has no dependency on Roslyn. All symbol resolution, type
/// information, and attribute data are read from the plain-data records in
/// [FrontendResult].
abstract interface class IIrBuilder {
  /// Builds an IR tree from [frontendResult].
  ///
  /// Returns an [IrBuildResult] that is always non-null.
  /// [IrBuildResult.success] is false when any Error-severity diagnostic is
  /// present in [IrBuildResult.diagnostics].
  ///
  /// Never throws on unsupported constructs — emits diagnostics and
  /// substitutes placeholder nodes instead.
  IrBuildResult build(FrontendResult frontendResult);
}
