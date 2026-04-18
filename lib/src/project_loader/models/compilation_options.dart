import 'output_kind.dart';

/// Options used to configure a [CSharpCompilation].
final class CompilationOptions {
  /// The output kind for the compiled assembly.
  final OutputKind outputKind;

  /// Whether nullable reference type analysis is enabled.
  final bool nullableEnabled;

  /// The C# language version string, e.g. "12.0" or "Latest".
  final String langVersion;

  const CompilationOptions({
    required this.outputKind,
    required this.nullableEnabled,
    required this.langVersion,
  });
}
