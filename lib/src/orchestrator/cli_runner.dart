import 'dart:io';

import 'package:args/args.dart';

import 'diagnostic_renderer.dart';
import 'orchestrator.dart';

/// Parses command-line arguments and delegates to [Orchestrator.transpile].
///
/// Returns an exit code suitable for passing to [exit()]:
/// - `0` on success
/// - `1` on argument errors or when the transpilation fails
final class CliRunner {
  final Orchestrator _orchestrator;

  CliRunner(this._orchestrator);

  /// Runs the CLI with the given [args].
  ///
  /// Parses arguments, constructs [TranspilerOptions], invokes the orchestrator,
  /// renders diagnostics, and returns the appropriate exit code.
  Future<int> run(List<String> args) async {
    final parser = _buildParser();

    final ArgResults results;
    try {
      results = parser.parse(args);
    } on ArgParserException catch (e) {
      stderr.writeln('Error: ${e.message}');
      stderr.writeln();
      stderr.writeln(_usage(parser));
      return 1;
    }

    // --help / -h: print usage to stdout and exit 0.
    if (results['help'] as bool) {
      stdout.writeln(_usage(parser));
      return 0;
    }

    // Positional argument (input path) is required.
    if (results.rest.isEmpty) {
      stderr.writeln('Error: Missing required positional argument: <input>');
      stderr.writeln();
      stderr.writeln(_usage(parser));
      return 1;
    }

    // --output is mandatory; ArgParser throws ArgParserException when absent,
    // but guard defensively in case the value is somehow null.
    final outputDir = results['output'] as String?;
    if (outputDir == null || outputDir.isEmpty) {
      stderr.writeln('Error: Missing required option "--output".');
      stderr.writeln();
      stderr.writeln(_usage(parser));
      return 1;
    }

    final inputPath = results.rest.first;
    final configPath = results['config'] as String?;
    final verbose = results['verbose'] as bool;
    final skipFormat = results['no-format'] as bool;
    final skipAnalyze = results['no-analyze'] as bool;

    final options = TranspilerOptions(
      inputPath: inputPath,
      outputDirectory: outputDir,
      configPath: configPath,
      verbose: verbose,
      skipFormat: skipFormat,
      skipAnalyze: skipAnalyze,
    );

    final result = await _orchestrator.transpile(options);

    DiagnosticRenderer.renderAll(
      result,
      verbose: options.verbose,
      outputDirectory: options.outputDirectory,
    );

    return result.success ? 0 : 1;
  }

  /// Builds the [ArgParser] with all supported flags and options.
  ArgParser _buildParser() => ArgParser()
    ..addOption('output', abbr: 'o', mandatory: true, help: 'Output directory')
    ..addOption('config', help: 'Explicit path to transpiler.yaml')
    ..addFlag('verbose',
        abbr: 'v', negatable: false, help: 'Emit Info diagnostics')
    ..addFlag('no-format', negatable: false, help: 'Skip dart format')
    ..addFlag('no-analyze', negatable: false, help: 'Skip dart analyze')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage');

  /// Returns a formatted usage string for the CLI.
  String _usage(ArgParser parser) {
    final buffer = StringBuffer()
      ..writeln('Usage: cs2dart <input> --output <dir> [options]')
      ..writeln()
      ..writeln('Arguments:')
      ..writeln('  <input>    Path to a .csproj or .sln file (required)')
      ..writeln()
      ..writeln('Options:')
      ..write(parser.usage);
    return buffer.toString();
  }
}
