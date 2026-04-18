/// All runtime parameters for a single transpiler invocation.
final class TranspilerOptions {
  /// Path to the .csproj or .sln file to transpile.
  final String inputPath;

  /// Root directory under which per-package subdirectories are created.
  final String outputDirectory;

  /// Explicit path to transpiler.yaml; null triggers directory search.
  final String? configPath;

  /// When true, emit Info-severity diagnostics to stdout.
  ///
  /// Defaults to [false].
  final bool verbose;

  /// When true, skip `dart format` (sets validation.skip_format flag).
  ///
  /// Defaults to [false].
  final bool skipFormat;

  /// When true, skip `dart analyze` (sets validation.skip_analyze flag).
  ///
  /// Defaults to [false].
  final bool skipAnalyze;

  const TranspilerOptions({
    required this.inputPath,
    required this.outputDirectory,
    this.configPath,
    this.verbose = false,
    this.skipFormat = false,
    this.skipAnalyze = false,
  });
}
