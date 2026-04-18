import 'package:cs2dart/src/project_loader/interfaces/i_compilation_builder.dart';
import 'package:cs2dart/src/project_loader/models/compilation_options.dart';
import 'package:cs2dart/src/project_loader/models/roslyn_interop.dart';

/// A test double for [ICompilationBuilder] that creates a real
/// [CSharpCompilation] placeholder from the provided inputs.
///
/// Behaviour is identical to the production [CompilationBuilder]; this copy
/// lives in the test tree so tests do not depend on the production class
/// directly.
final class FakeCompilationBuilder implements ICompilationBuilder {
  const FakeCompilationBuilder();

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
