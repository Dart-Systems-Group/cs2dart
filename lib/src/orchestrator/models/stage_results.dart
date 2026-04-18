import '../../project_loader/models/diagnostic.dart';

/// A generated Dart package produced by the Dart_Generator stage.
///
/// Stub definition — full schema defined in the Dart_Generator specification.
final class OutputPackage {
  /// The C# project name this package was generated from.
  final String projectName;

  /// The absolute path to the output directory for this package.
  final String outputPath;

  const OutputPackage({
    required this.projectName,
    required this.outputPath,
  });

  /// Returns a copy of this [OutputPackage] with [outputPath] replaced.
  OutputPackage withOutputPath(String newOutputPath) =>
      OutputPackage(projectName: projectName, outputPath: newOutputPath);
}

/// The output of the Roslyn_Frontend stage.
///
/// Stub definition — full schema defined in the Roslyn Frontend specification.
final class FrontendResult {
  /// The compilation units produced by the frontend.
  ///
  /// Empty when [success] is false and no units could be processed.
  final List<Object> units;

  /// Aggregated diagnostics from the frontend stage.
  final List<Diagnostic> diagnostics;

  /// True if and only if [diagnostics] contains no Error-severity entry.
  final bool success;

  const FrontendResult({
    required this.units,
    required this.diagnostics,
    required this.success,
  });
}

/// The output of the IR_Builder stage.
///
/// Stub definition — full schema defined in the IR_Builder specification.
final class IrBuildResult {
  /// The IR units produced by the builder.
  ///
  /// Empty when [success] is false and no units could be built.
  final List<Object> units;

  /// Aggregated diagnostics from the IR builder stage.
  final List<Diagnostic> diagnostics;

  /// True if and only if [diagnostics] contains no Error-severity entry.
  final bool success;

  const IrBuildResult({
    required this.units,
    required this.diagnostics,
    required this.success,
  });
}

/// The output of the Dart_Generator stage.
///
/// Stub definition — full schema defined in the Dart_Generator specification.
final class GenResult {
  /// The generated Dart packages.
  ///
  /// Empty when [success] is false and no packages could be generated.
  final List<OutputPackage> packages;

  /// Aggregated diagnostics from the generator stage.
  final List<Diagnostic> diagnostics;

  /// True if and only if [diagnostics] contains no Error-severity entry.
  final bool success;

  const GenResult({
    required this.packages,
    required this.diagnostics,
    required this.success,
  });

  /// Returns a copy of this [GenResult] with [packages] replaced.
  GenResult withPackages(List<OutputPackage> newPackages) => GenResult(
        packages: newPackages,
        diagnostics: diagnostics,
        success: success,
      );
}
