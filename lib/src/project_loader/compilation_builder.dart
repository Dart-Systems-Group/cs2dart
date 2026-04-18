import 'interfaces/i_compilation_builder.dart';
import 'models/compilation_options.dart';
import 'models/roslyn_interop.dart';

/// Concrete implementation of [ICompilationBuilder].
///
/// Constructs a [CSharpCompilation] placeholder that stores all data passed to
/// `CSharpCompilation.Create`. The actual Roslyn interop layer is not yet
/// implemented; this class captures the inputs so that tests and downstream
/// stages can verify the compilation was built correctly.
///
/// Metadata references must be provided in deterministic order by the caller
/// (the coordinator): SDK assemblies first (sorted by file name), then NuGet
/// assemblies (sorted by package ID then file name), then project reference
/// assemblies (sorted by project path). This builder does not re-sort them.
final class CompilationBuilder implements ICompilationBuilder {
  const CompilationBuilder();

  /// Creates a [CSharpCompilation] from the provided inputs.
  ///
  /// - [assemblyName]: the assembly name for the compilation.
  /// - [sourceFilePaths]: paths to `.cs` source files; each represents one
  ///   syntax tree in the compilation.
  /// - [metadataReferences]: assembly references in deterministic order
  ///   (SDK → NuGet → project refs), as supplied by the coordinator.
  /// - [options]: compilation options derived from the project file
  ///   (`OutputKind`, nullable context, language version).
  @override
  CSharpCompilation build(
    String assemblyName,
    List<String> sourceFilePaths,
    List<MetadataReference> metadataReferences,
    CompilationOptions options,
  ) {
    return CSharpCompilation(
      assemblyName: assemblyName,
      syntaxTreePaths: List.unmodifiable(sourceFilePaths),
      metadataReferences: List.unmodifiable(metadataReferences),
      options: options,
    );
  }
}
