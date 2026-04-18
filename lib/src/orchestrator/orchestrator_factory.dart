import '../project_loader/compilation_builder.dart';
import '../project_loader/input_parser.dart';
import '../project_loader/nuget_handler.dart';
import '../project_loader/sdk_resolver.dart';
import 'orchestrator.dart';
import 'project_loader_adapter.dart';

// ---------------------------------------------------------------------------
// Stub implementations for stages not yet implemented by their own specs.
// Each stub throws [UnimplementedError] so that the factory compiles while
// the concrete implementations are developed in parallel specs.
// ---------------------------------------------------------------------------

/// Stub [IRoslynFrontend] — throws [UnimplementedError] until the
/// Roslyn Frontend spec is implemented.
final class RoslynFrontend implements IRoslynFrontend {
  const RoslynFrontend();

  @override
  Future<FrontendResult> process(loadResult, config) =>
      throw UnimplementedError('RoslynFrontend is not yet implemented.');
}

/// Stub [IIrBuilder] — throws [UnimplementedError] until the
/// IR Builder spec is implemented.
final class IrBuilder implements IIrBuilder {
  const IrBuilder();

  @override
  Future<IrBuildResult> build(frontendResult) =>
      throw UnimplementedError('IrBuilder is not yet implemented.');
}

/// Stub [IDartGenerator] — throws [UnimplementedError] until the
/// Dart Generator spec is implemented.
final class DartGenerator implements IDartGenerator {
  const DartGenerator();

  @override
  Future<GenResult> generate(irBuildResult) =>
      throw UnimplementedError('DartGenerator is not yet implemented.');
}

/// Stub [IValidator] — throws [UnimplementedError] until the
/// Validator spec is implemented.
final class Validator implements IValidator {
  const Validator();

  @override
  Future<TranspilerResult> validate(genResult) =>
      throw UnimplementedError('Validator is not yet implemented.');
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

/// Provides the production wiring for the [Orchestrator].
///
/// Concrete stage implementations that are not yet available are replaced by
/// stub classes that throw [UnimplementedError]. Once each spec is implemented,
/// the corresponding stub is replaced with the real class.
final class OrchestratorFactory {
  /// Creates a fully-wired production [Orchestrator].
  ///
  /// The [ProjectLoader] is wired with its own production dependencies.
  /// The remaining pipeline stages ([RoslynFrontend], [IrBuilder],
  /// [DartGenerator], [Validator]) are stub implementations that throw
  /// [UnimplementedError] until their respective specs are completed.
  static Orchestrator create() => Orchestrator(
        projectLoader: ProjectLoaderAdapter(
          inputParser: const InputParser(),
          sdkResolver: const SdkResolver(),
          nugetHandler: const NuGetHandler(),
          compilationBuilder: const CompilationBuilder(),
        ),
        roslynFrontend: const RoslynFrontend(),
        irBuilder: const IrBuilder(),
        dartGenerator: const DartGenerator(),
        validator: const Validator(),
      );
}
