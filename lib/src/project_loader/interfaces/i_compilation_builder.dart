import '../models/compilation_options.dart';
import '../models/roslyn_interop.dart';

/// Constructs a Roslyn [CSharpCompilation] from project metadata.
abstract interface class ICompilationBuilder {
  /// Creates a [CSharpCompilation] from [sourceFilePaths], [metadataReferences],
  /// and [options] derived from the project metadata.
  ///
  /// Metadata references must be provided in deterministic order:
  /// SDK assemblies first (sorted by file name), then NuGet assemblies
  /// (sorted by package ID then file name), then project reference assemblies
  /// (sorted by project path).
  CSharpCompilation build(
    String assemblyName,
    List<String> sourceFilePaths,
    List<MetadataReference> metadataReferences,
    CompilationOptions options,
  );
}
