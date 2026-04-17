import 'i_config_service.dart';
import 'models/models.dart';

/// The result of loading and validating a `transpiler.yaml` file.
///
/// Carries the resolved [IConfigService] (when no errors occurred), the
/// resolved [ConfigObject], and all [ConfigDiagnostic] entries produced
/// during loading and validation.
final class ConfigLoadResult {
  /// The config service, or null when any [DiagnosticSeverity.error]-severity
  /// diagnostic is present.
  final IConfigService? service;

  /// The resolved config object.
  ///
  /// Contains the default [ConfigObject] when no file was found, or null when
  /// parsing failed entirely.
  final ConfigObject? config;

  /// All diagnostics produced during loading and validation.
  final List<ConfigDiagnostic> diagnostics;

  /// Returns true when any diagnostic has severity [DiagnosticSeverity.error].
  bool get hasErrors =>
      diagnostics.any((d) => d.severity == DiagnosticSeverity.error);

  const ConfigLoadResult({
    required this.service,
    required this.config,
    required this.diagnostics,
  });
}
