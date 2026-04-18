import 'package:cs2dart/src/config/i_config_service.dart';
import 'package:cs2dart/src/config/models/config_object.dart';
import 'package:cs2dart/src/orchestrator/interfaces/i_project_loader.dart';
import 'package:cs2dart/src/project_loader/models/compilation_options.dart';
import 'package:cs2dart/src/project_loader/models/dependency_graph.dart';
import 'package:cs2dart/src/project_loader/models/output_kind.dart';
import 'package:cs2dart/src/project_loader/models/project_entry.dart';
import 'package:cs2dart/src/project_loader/models/roslyn_interop.dart';

/// A test double for [IProjectLoader] that records whether it was called and
/// returns a pre-configured [LoadResult].
///
/// By default returns a successful [LoadResult] with one [ProjectEntry] and
/// no diagnostics, so that the pipeline does not trigger an early exit.
///
/// Set [throwException] to make the fake throw instead of returning a result,
/// which exercises the Orchestrator's exception-wrapping logic.
final class FakeProjectLoader implements IProjectLoader {
  /// Whether [load] has been called at least once.
  bool wasCalled = false;

  /// The result returned by [load]. Defaults to a successful single-project result.
  LoadResult result = LoadResult(
    projects: [
      ProjectEntry(
        projectPath: '/fake/FakeProject.csproj',
        projectName: 'FakeProject',
        targetFramework: 'net8.0',
        outputKind: OutputKind.library,
        langVersion: 'Latest',
        nullableEnabled: true,
        compilation: CSharpCompilation(
          assemblyName: 'FakeProject',
          syntaxTreePaths: const [],
          metadataReferences: const [],
          options: CompilationOptions(
            outputKind: OutputKind.library,
            nullableEnabled: true,
            langVersion: 'Latest',
          ),
        ),
        packageReferences: const [],
        diagnostics: const [],
      ),
    ],
    dependencyGraph: DependencyGraph.empty,
    diagnostics: const [],
    success: true,
    config: ConfigObject.defaults,
  );

  /// When non-null, [load] throws this exception instead of returning [result].
  Exception? throwException;

  @override
  Future<LoadResult> load(String inputPath, IConfigService config) async {
    wasCalled = true;
    if (throwException != null) throw throwException!;
    return result;
  }
}
