import 'dart:io';

import '../project_loader/models/diagnostic.dart';
import 'models/stage_results.dart';

/// Assigns absolute output paths to each [OutputPackage] in a [GenResult].
///
/// Handles snake_case conversion of C# project names and collision
/// disambiguation when multiple projects map to the same snake_case name.
final class OutputPathAssigner {
  const OutputPathAssigner();

  /// Converts a C# project name to a Dart-idiomatic snake_case package name.
  ///
  /// Six-step algorithm:
  /// 1. Insert `_` before each uppercase letter that follows a lowercase letter
  ///    or digit (e.g., `MyProject` → `My_Project`).
  /// 2. Insert `_` before each uppercase letter that is followed by a lowercase
  ///    letter and preceded by an uppercase letter (handles acronyms:
  ///    `XMLParser` → `XML_Parser`).
  /// 3. Replace `.`, `-`, and spaces with `_`.
  /// 4. Lowercase the entire string.
  /// 5. Collapse consecutive `_` into a single `_`.
  /// 6. Strip leading/trailing `_`.
  ///
  /// Examples:
  /// - `MyProject.Core` → `my_project_core`
  /// - `XMLParser` → `xml_parser`
  static String toSnakeCase(String projectName) {
    // Step 1: Insert `_` before each uppercase letter that follows a lowercase
    // letter or digit.
    var result = projectName.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (m) => '${m[1]}_${m[2]}',
    );

    // Step 2: Insert `_` before each uppercase letter that is followed by a
    // lowercase letter and preceded by an uppercase letter (acronym handling).
    result = result.replaceAllMapped(
      RegExp(r'([A-Z])([A-Z][a-z])'),
      (m) => '${m[1]}_${m[2]}',
    );

    // Step 3: Replace `.`, `-`, and spaces with `_`.
    result = result.replaceAll(RegExp(r'[.\- ]'), '_');

    // Step 4: Lowercase the entire string.
    result = result.toLowerCase();

    // Step 5: Collapse consecutive `_` into a single `_`.
    result = result.replaceAll(RegExp(r'_+'), '_');

    // Step 6: Strip leading/trailing `_`.
    result = result.replaceAll(RegExp(r'^_+|_+$'), '');

    return result;
  }

  /// Assigns absolute [OutputPackage.outputPath] values to all packages in
  /// [genResult].
  ///
  /// - Resolves [outputDirectory] to an absolute path (relative paths are
  ///   resolved against [Directory.current.path]).
  /// - Applies collision disambiguation: when two or more packages share the
  ///   same snake_case name, the first keeps the base name and subsequent ones
  ///   receive `_2`, `_3`, … suffixes in the order they appear in
  ///   [GenResult.packages].
  /// - Emits one [OR0006] [DiagnosticSeverity.warning] diagnostic per
  ///   collision group.
  ///
  /// Returns a new [GenResult] with updated packages; does not mutate the
  /// input.
  GenResult assign(GenResult genResult, String outputDirectory) {
    // Resolve outputDirectory to an absolute path.
    final absOutputDir = _resolveAbsolute(outputDirectory);

    // Build a map from snake_case name → list of (index, package) pairs.
    final nameToIndices = <String, List<int>>{};
    for (var i = 0; i < genResult.packages.length; i++) {
      final snakeName = toSnakeCase(genResult.packages[i].projectName);
      nameToIndices.putIfAbsent(snakeName, () => []).add(i);
    }

    // Assign output paths and collect collision diagnostics.
    final updatedPackages = List<OutputPackage>.of(genResult.packages);
    final collisionDiagnostics = <Diagnostic>[];

    for (final entry in nameToIndices.entries) {
      final snakeName = entry.key;
      final indices = entry.value;

      if (indices.length > 1) {
        // Collision: emit OR0006 warning.
        final projectNames =
            indices.map((i) => genResult.packages[i].projectName).toList();
        collisionDiagnostics.add(Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'OR0006',
          message:
              'Package name collision for "$snakeName": projects $projectNames '
              'disambiguated with numeric suffixes.',
        ));

        // First package gets the base name; subsequent ones get _2, _3, etc.
        for (var j = 0; j < indices.length; j++) {
          final suffix = j == 0 ? '' : '_${j + 1}';
          final outputPath = _joinPath(absOutputDir, '$snakeName$suffix');
          updatedPackages[indices[j]] =
              updatedPackages[indices[j]].withOutputPath(outputPath);
        }
      } else {
        // No collision: assign base name directly.
        final outputPath = _joinPath(absOutputDir, snakeName);
        updatedPackages[indices[0]] =
            updatedPackages[indices[0]].withOutputPath(outputPath);
      }
    }

    // Build updated diagnostics list (original + collision warnings).
    final updatedDiagnostics = [
      ...genResult.diagnostics,
      ...collisionDiagnostics,
    ];

    return GenResult(
      packages: updatedPackages,
      diagnostics: updatedDiagnostics,
      success: genResult.success,
    );
  }

  /// Resolves [path] to an absolute path.
  ///
  /// If [path] is already absolute, returns it unchanged.
  /// Otherwise, resolves it relative to [Directory.current.path].
  static String _resolveAbsolute(String path) {
    if (_isAbsolute(path)) return path;
    return _joinPath(Directory.current.path, path);
  }

  /// Returns true if [path] is an absolute path.
  static bool _isAbsolute(String path) {
    if (path.isEmpty) return false;
    // Unix absolute path starts with '/'.
    if (path.startsWith('/')) return true;
    // Windows absolute path: drive letter followed by ':' (e.g., 'C:\').
    if (path.length >= 2 && path[1] == ':') return true;
    // Windows UNC path starts with '\\'.
    if (path.startsWith(r'\\')) return true;
    return false;
  }

  /// Joins two path segments using the platform separator.
  static String _joinPath(String base, String segment) {
    final separator = Platform.pathSeparator;
    if (base.endsWith(separator)) {
      return '$base$segment';
    }
    return '$base$separator$segment';
  }
}
