import 'dart:io';

import 'config_builder.dart';
import 'config_load_result.dart';
import 'config_parser.dart';
import 'config_service.dart';
import 'config_validator.dart';
import 'models/config_diagnostic.dart';
import 'models/config_object.dart';
import 'models/diagnostic_severity.dart';

/// Discovers, reads, parses, validates, and builds the transpiler configuration.
///
/// Never throws — all errors are captured as [ConfigDiagnostic] entries in the
/// returned [ConfigLoadResult].
final class ConfigLoader {
  /// Discovers and loads `transpiler.yaml`, running the full pipeline:
  /// file discovery → [ConfigParser.parse] → [ConfigValidator.validate] →
  /// [ConfigBuilder.build] → [ConfigService] → [ConfigLoadResult].
  ///
  /// [entryPath] is the `.csproj` or `.sln` file path used as the starting
  /// point for directory search when [explicitConfigPath] is null.
  ///
  /// [explicitConfigPath] is the value of `--config`, if provided. When set,
  /// directory search is skipped entirely.
  static Future<ConfigLoadResult> load({
    required String entryPath,
    String? explicitConfigPath,
  }) async {
    // -------------------------------------------------------------------------
    // Step 1: File discovery
    // -------------------------------------------------------------------------
    final discoveryResult = await _discoverConfigFile(entryPath, explicitConfigPath);

    // Explicit path missing → CFG0001 Error
    if (discoveryResult.missingExplicit) {
      return ConfigLoadResult(
        service: null,
        config: null,
        diagnostics: [
          ConfigDiagnostic(
            severity: DiagnosticSeverity.error,
            code: 'CFG0001',
            message:
                'Explicit config file not found: "${explicitConfigPath!}"',
          ),
        ],
      );
    }

    // No file found → defaults + CFG0020 Info
    if (discoveryResult.filePath == null) {
      final defaults = ConfigObject.defaults;
      return ConfigLoadResult(
        service: ConfigService(defaults),
        config: defaults,
        diagnostics: [
          const ConfigDiagnostic(
            severity: DiagnosticSeverity.info,
            code: 'CFG0020',
            message:
                'No transpiler.yaml found; using all default configuration values.',
          ),
        ],
      );
    }

    final filePath = discoveryResult.filePath!;

    // -------------------------------------------------------------------------
    // Step 2: Read file content
    // -------------------------------------------------------------------------
    String content;
    try {
      content = await File(filePath).readAsString();
    } catch (e) {
      return ConfigLoadResult(
        service: null,
        config: null,
        diagnostics: [
          ConfigDiagnostic(
            severity: DiagnosticSeverity.error,
            code: 'CFG0001',
            message: 'Failed to read config file "$filePath": $e',
          ),
        ],
      );
    }

    // -------------------------------------------------------------------------
    // Step 3: Parse YAML
    // -------------------------------------------------------------------------
    final parseResult = ConfigParser.parse(content, filePath);
    if (parseResult.error != null) {
      return ConfigLoadResult(
        service: null,
        config: null,
        diagnostics: [parseResult.error!],
      );
    }

    final yamlMap = parseResult.map!;

    // -------------------------------------------------------------------------
    // Step 4: Validate
    // -------------------------------------------------------------------------
    final validationResult = ConfigValidator.validate(yamlMap, filePath);
    final diagnostics = List<ConfigDiagnostic>.from(validationResult.diagnostics);

    // -------------------------------------------------------------------------
    // Step 5: Build ConfigObject
    // -------------------------------------------------------------------------
    final config = ConfigBuilder.build(validationResult.cleaned);

    // -------------------------------------------------------------------------
    // Step 6: Assemble result
    // -------------------------------------------------------------------------
    final hasErrors =
        diagnostics.any((d) => d.severity == DiagnosticSeverity.error);

    return ConfigLoadResult(
      service: hasErrors ? null : ConfigService(config),
      config: config,
      diagnostics: diagnostics,
    );
  }

  // ---------------------------------------------------------------------------
  // File discovery
  // ---------------------------------------------------------------------------

  static Future<_DiscoveryResult> _discoverConfigFile(
    String entryPath,
    String? explicitConfigPath,
  ) async {
    // Explicit path provided
    if (explicitConfigPath != null) {
      if (File(explicitConfigPath).existsSync()) {
        return _DiscoveryResult(filePath: explicitConfigPath);
      }
      return const _DiscoveryResult(missingExplicit: true);
    }

    // Walk from entry-point directory up to filesystem root
    var searchDir = File(entryPath).parent;

    while (true) {
      final candidate = File('${searchDir.path}${Platform.pathSeparator}transpiler.yaml');
      if (candidate.existsSync()) {
        return _DiscoveryResult(filePath: candidate.path);
      }

      final parent = searchDir.parent;
      if (parent.path == searchDir.path) {
        // Reached filesystem root
        break;
      }
      searchDir = parent;
    }

    // No file found
    return const _DiscoveryResult();
  }
}

// ---------------------------------------------------------------------------
// Internal result type for discovery
// ---------------------------------------------------------------------------

class _DiscoveryResult {
  /// The resolved config file path, or null if not found.
  final String? filePath;

  /// True when an explicit path was provided but the file does not exist.
  final bool missingExplicit;

  const _DiscoveryResult({
    this.filePath,
    this.missingExplicit = false,
  });
}
