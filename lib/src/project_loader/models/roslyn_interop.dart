import 'compilation_options.dart';

/// Placeholder for the Roslyn [CSharpCompilation] type.
///
/// The actual Roslyn interop layer (via FFI or a .NET bridge) is not yet
/// implemented. This placeholder stores the data that would be passed to
/// `CSharpCompilation.Create`, allowing tests to verify the compilation was
/// built correctly.
final class CSharpCompilation {
  /// The assembly name passed to `CSharpCompilation.Create`.
  final String assemblyName;

  /// The source file paths representing the syntax trees in this compilation.
  final List<String> syntaxTreePaths;

  /// The metadata references (SDK, NuGet, and project reference assemblies).
  final List<MetadataReference> metadataReferences;

  /// The compilation options derived from the project file.
  final CompilationOptions options;

  const CSharpCompilation({
    required this.assemblyName,
    required this.syntaxTreePaths,
    required this.metadataReferences,
    required this.options,
  });
}

/// Placeholder for the Roslyn [MetadataReference] type.
///
/// Represents a reference to a compiled assembly (.dll) that is added to a
/// [CSharpCompilation] to make its types available during semantic analysis.
final class MetadataReference {
  /// The file-system path to the assembly.
  final String assemblyPath;

  const MetadataReference({required this.assemblyPath});
}

/// Placeholder for the Dart mapping record produced by the NuGet_Handler.
///
/// Populated for Tier 1 NuGet packages that have a known Dart equivalent.
/// Null for Tier 2 and Tier 3 packages.
final class DartMapping {
  /// The Dart package name that maps to this NuGet package.
  final String dartPackageName;

  /// The Dart import path for the mapped library.
  final String dartImportPath;

  const DartMapping({
    required this.dartPackageName,
    required this.dartImportPath,
  });
}
