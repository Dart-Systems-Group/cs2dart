import 'package:yaml/yaml.dart';

import 'models/models.dart';

/// Parses raw YAML content into a [YamlMap].
///
/// Returns either a [YamlMap] on success or a [ConfigDiagnostic] with code
/// `CFG0002` on [YamlException] or a non-map top-level document.
final class ConfigParser {
  static ({YamlMap? map, ConfigDiagnostic? error}) parse(
    String content,
    String sourcePath,
  ) {
    try {
      final doc = loadYaml(content);
      if (doc == null) return (map: YamlMap(), error: null);
      if (doc is! YamlMap) {
        return (
          map: null,
          error: ConfigDiagnostic(
            severity: DiagnosticSeverity.error,
            code: 'CFG0002',
            message: 'transpiler.yaml must be a YAML mapping at the top level',
            location: SourceLocation(filePath: sourcePath, line: 1, column: 1),
          ),
        );
      }
      return (map: doc, error: null);
    } on YamlException catch (e) {
      return (
        map: null,
        error: ConfigDiagnostic(
          severity: DiagnosticSeverity.error,
          code: 'CFG0002',
          message: 'YAML syntax error: ${e.message}',
          location: SourceLocation(
            filePath: sourcePath,
            line: e.span?.start.line ?? 0,
            column: e.span?.start.column ?? 0,
          ),
        ),
      );
    }
  }
}
