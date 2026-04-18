import 'dart:io';

import '../config/i_config_service.dart';
import '../config/models/config_object.dart';
import 'dependency_graph_builder.dart';
import 'input_parser.dart';
import 'interfaces/i_compilation_builder.dart';
import 'interfaces/i_input_parser.dart';
import 'interfaces/i_nuget_handler.dart';
import 'interfaces/i_project_loader.dart';
import 'interfaces/i_sdk_resolver.dart';
import 'models/compilation_options.dart';
import 'models/dependency_graph.dart';
import 'models/diagnostic.dart';
import 'models/load_result.dart';
import 'models/output_kind.dart';
import 'models/project_entry.dart';
import 'models/project_file_data.dart';
import 'models/roslyn_interop.dart';

/// Concrete implementation of [IProjectLoader].
///
/// Orchestrates [IInputParser], [ISdkResolver], [INuGetHandler], and
/// [ICompilationBuilder] to produce a [LoadResult] from a `.csproj` or `.sln`
/// input path.
final class ProjectLoader implements IProjectLoader {
  final IInputParser _inputParser;
  final ISdkResolver _sdkResolver;
  final INuGetHandler _nugetHandler;
  final ICompilationBuilder _compilationBuilder;

  const ProjectLoader({
    required IInputParser inputParser,
    required ISdkResolver sdkResolver,
    required INuGetHandler nugetHandler,
    required ICompilationBuilder compilationBuilder,
  })  : _inputParser = inputParser,
        _sdkResolver = sdkResolver,
        _nugetHandler = nugetHandler,
        _compilationBuilder = compilationBuilder;

  @override
  Future<LoadResult> load(String inputPath, IConfigService config) async {
    final configObject = config.config;

    // 1. Resolve relative paths against CWD.
    final absolutePath = File(inputPath).absolute.path;

    // 2. Validate: file must exist.
    if (!File(absolutePath).existsSync()) {
      return _errorResult(
        configObject,
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'PL0001',
          message: 'File does not exist: $absolutePath',
          source: absolutePath,
        ),
      );
    }

    // 3. Validate: extension must be .csproj or .sln.
    final extension = _fileExtension(absolutePath).toLowerCase();
    if (extension != '.csproj' && extension != '.sln') {
      return _errorResult(
        configObject,
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'PL0002',
          message:
              'Unsupported file extension "$extension". '
              'Only .csproj and .sln files are supported.',
          source: absolutePath,
        ),
      );
    }

    // 4. Dispatch to the appropriate load flow.
    if (extension == '.csproj') {
      return _loadCsproj(absolutePath, config, configObject);
    } else {
      return _loadSln(absolutePath, config, configObject);
    }
  }

  // ---------------------------------------------------------------------------
  // Single .csproj load flow
  // ---------------------------------------------------------------------------

  Future<LoadResult> _loadCsproj(
    String absolutePath,
    IConfigService config,
    ConfigObject configObject,
  ) async {
    final plDiagnostics = <Diagnostic>[];

    // 4a. Parse the .csproj file.
    final projectFileData = await _parseCsproj(absolutePath, plDiagnostics);
    if (projectFileData == null) {
      return LoadResult(
        projects: const [],
        dependencyGraph: DependencyGraph.empty,
        diagnostics: plDiagnostics,
        success: false,
        config: configObject,
      );
    }

    // 4b. Determine target framework (emit PL0012 Warning if missing).
    final String targetFramework;
    if (projectFileData.targetFramework != null) {
      targetFramework = projectFileData.targetFramework!;
    } else {
      plDiagnostics.add(Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'PL0012',
        message:
            'No <TargetFramework> element found in "$absolutePath". '
            'Defaulting to "net8.0".',
        source: absolutePath,
      ));
      targetFramework = 'net8.0';
    }

    // 4c. Determine assembly name.
    final assemblyName =
        projectFileData.assemblyName ?? _deriveAssemblyName(absolutePath);

    // 4d. Resolve SDK assemblies.
    final sdkResult = await _sdkResolver.resolve(
      targetFramework,
      sdkPath: config.sdkPath,
    );
    plDiagnostics.addAll(sdkResult.diagnostics);

    // 4e. Resolve NuGet packages.
    final nugetResult = await _nugetHandler.resolve(
      projectFileData.packageReferences,
      targetFramework,
      config,
    );

    // 4f. Build metadata references in deterministic order.
    final metadataRefs = _buildMetadataRefs(
      sdkResult.assemblyPaths,
      nugetResult.assemblyPaths,
      const [], // project reference assemblies — empty for single project
    );

    // 4g. Build CompilationOptions from project file data.
    final options = CompilationOptions(
      outputKind: _buildOutputKind(projectFileData.outputType),
      nullableEnabled: projectFileData.nullableEnabled,
      langVersion: projectFileData.langVersion ?? 'Latest',
    );

    // 4h. Build the CSharpCompilation.
    final compilation = _compilationBuilder.build(
      assemblyName,
      projectFileData.sourceGlobs,
      metadataRefs,
      options,
    );

    // 4i. Collect Roslyn diagnostics (placeholder — no diagnostics for now).
    final roslynDiagnostics = <Diagnostic>[];

    // 4j. Assemble ProjectEntry.
    final projectDiagnostics = [
      ...plDiagnostics,
      ...nugetResult.diagnostics,
      ...roslynDiagnostics,
    ];

    final entry = ProjectEntry(
      projectPath: absolutePath,
      projectName: assemblyName,
      targetFramework: targetFramework,
      outputKind: options.outputKind,
      langVersion: options.langVersion,
      nullableEnabled: options.nullableEnabled,
      compilation: compilation,
      packageReferences: nugetResult.packageReferences,
      diagnostics: projectDiagnostics,
    );

    // 4k. Aggregate all diagnostics: PL first, then NR, then CS.
    final allDiagnostics = _aggregateDiagnostics([
      ...plDiagnostics,
      ...nugetResult.diagnostics,
      ...roslynDiagnostics,
    ]);

    // 4l. Return LoadResult.
    final hasError =
        allDiagnostics.any((d) => d.severity == DiagnosticSeverity.error);

    return LoadResult(
      projects: [entry],
      dependencyGraph: DependencyGraph.empty,
      diagnostics: allDiagnostics,
      success: !hasError,
      config: configObject,
    );
  }

  // ---------------------------------------------------------------------------
  // .sln load flow with dependency graph
  // ---------------------------------------------------------------------------

  Future<LoadResult> _loadSln(
    String absolutePath,
    IConfigService config,
    ConfigObject configObject,
  ) async {
    final plDiagnostics = <Diagnostic>[];

    // Step 1: Parse the .sln file to get the list of .csproj paths.
    List<String> csprojPaths;
    try {
      csprojPaths = await _inputParser.parseSln(absolutePath);
    } on MalformedSlnException catch (e) {
      plDiagnostics.add(Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'PL0004',
        message: 'Malformed .sln file: ${e.details}',
        source: absolutePath,
      ));
      return LoadResult(
        projects: const [],
        dependencyGraph: DependencyGraph.empty,
        diagnostics: plDiagnostics,
        success: false,
        config: configObject,
      );
    } catch (e) {
      plDiagnostics.add(Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'PL0004',
        message: 'Failed to parse .sln file: $e',
        source: absolutePath,
      ));
      return LoadResult(
        projects: const [],
        dependencyGraph: DependencyGraph.empty,
        diagnostics: plDiagnostics,
        success: false,
        config: configObject,
      );
    }

    // Step 2: Parse each .csproj file; collect ProjectFileData.
    // Also validate ProjectReference paths against the known set.
    final csprojPathSet = csprojPaths.toSet();
    final allProjectData = <ProjectFileData>[];

    for (final csprojPath in csprojPaths) {
      final projectData = await _parseCsproj(csprojPath, plDiagnostics);
      if (projectData == null) {
        // PL0003 already emitted; skip this project.
        continue;
      }

      // Validate each ProjectReference path.
      for (final refPath in projectData.projectReferencePaths) {
        if (!csprojPathSet.contains(refPath)) {
          plDiagnostics.add(Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'PL0010',
            message:
                'Unresolvable <ProjectReference> path "$refPath" in "$csprojPath". '
                'The referenced project is not part of the solution.',
            source: csprojPath,
          ));
        }
      }

      allProjectData.add(projectData);
    }

    // Step 3: Build the dependency graph and topologically sort.
    final graphResult = DependencyGraphBuilder().build(allProjectData);

    // Collect graph diagnostics (e.g. PL0011 cycle errors).
    plDiagnostics.addAll(graphResult.diagnostics);

    // If a cycle was detected, return early with empty projects.
    final hasCycle = graphResult.diagnostics
        .any((d) => d.severity == DiagnosticSeverity.error);
    if (hasCycle) {
      return LoadResult(
        projects: const [],
        dependencyGraph: graphResult.graph,
        diagnostics: plDiagnostics,
        success: false,
        config: configObject,
      );
    }

    // Step 4: Load each project in topological order (leaf-first).
    final projectDataByPath = {
      for (final pd in allProjectData) pd.absolutePath: pd,
    };

    final loadedProjects = <String, ProjectEntry>{};
    final nugetDiagnostics = <Diagnostic>[];

    for (final projectPath in graphResult.sortedProjectPaths) {
      final projectFileData = projectDataByPath[projectPath];
      if (projectFileData == null) {
        // This project was skipped due to a parse error; skip here too.
        continue;
      }

      final projectPlDiagnostics = <Diagnostic>[];

      // 4a. Determine target framework.
      final String targetFramework;
      if (projectFileData.targetFramework != null) {
        targetFramework = projectFileData.targetFramework!;
      } else {
        projectPlDiagnostics.add(Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'PL0012',
          message:
              'No <TargetFramework> element found in "$projectPath". '
              'Defaulting to "net8.0".',
          source: projectPath,
        ));
        targetFramework = 'net8.0';
      }

      // 4b. Determine assembly name.
      final assemblyName =
          projectFileData.assemblyName ?? _deriveAssemblyName(projectPath);

      // 4c. Resolve SDK assemblies.
      final sdkResult = await _sdkResolver.resolve(
        targetFramework,
        sdkPath: config.sdkPath,
      );
      projectPlDiagnostics.addAll(sdkResult.diagnostics);

      // 4d. Resolve NuGet packages.
      final nugetResult = await _nugetHandler.resolve(
        projectFileData.packageReferences,
        targetFramework,
        config,
      );

      // 4e. Collect project reference assembly paths from already-loaded projects.
      final projectRefAssemblyPaths = <String>[];
      for (final refPath in projectFileData.projectReferencePaths) {
        final loadedRef = loadedProjects[refPath];
        if (loadedRef != null) {
          // Use the project's absolute path as the assembly path (placeholder).
          projectRefAssemblyPaths.add(loadedRef.projectPath);
        }
        // If not loaded (e.g. parse failed), skip silently — PL0010 already emitted.
      }

      // 4f. Build metadata references in deterministic order.
      final metadataRefs = _buildMetadataRefs(
        sdkResult.assemblyPaths,
        nugetResult.assemblyPaths,
        projectRefAssemblyPaths,
      );

      // 4g. Build CompilationOptions.
      final options = CompilationOptions(
        outputKind: _buildOutputKind(projectFileData.outputType),
        nullableEnabled: projectFileData.nullableEnabled,
        langVersion: projectFileData.langVersion ?? 'Latest',
      );

      // 4h. Build the CSharpCompilation.
      final compilation = _compilationBuilder.build(
        assemblyName,
        projectFileData.sourceGlobs,
        metadataRefs,
        options,
      );

      // 4i. Collect Roslyn diagnostics (placeholder).
      final roslynDiagnostics = <Diagnostic>[];

      // 4j. Assemble ProjectEntry.
      final projectDiagnostics = [
        ...projectPlDiagnostics,
        ...nugetResult.diagnostics,
        ...roslynDiagnostics,
      ];

      final entry = ProjectEntry(
        projectPath: projectPath,
        projectName: assemblyName,
        targetFramework: targetFramework,
        outputKind: options.outputKind,
        langVersion: options.langVersion,
        nullableEnabled: options.nullableEnabled,
        compilation: compilation,
        packageReferences: nugetResult.packageReferences,
        diagnostics: projectDiagnostics,
      );

      loadedProjects[projectPath] = entry;
      plDiagnostics.addAll(projectPlDiagnostics);
      nugetDiagnostics.addAll(nugetResult.diagnostics);
    }

    // Step 5: Assemble LoadResult.
    final orderedProjects = graphResult.sortedProjectPaths
        .map((p) => loadedProjects[p])
        .whereType<ProjectEntry>()
        .toList();

    // Aggregate diagnostics: PL first, then NR, then CS.
    final allDiagnostics = _aggregateDiagnostics([
      ...plDiagnostics,
      ...nugetDiagnostics,
    ]);
    final hasError =
        allDiagnostics.any((d) => d.severity == DiagnosticSeverity.error);

    return LoadResult(
      projects: orderedProjects,
      dependencyGraph: graphResult.graph,
      diagnostics: allDiagnostics,
      success: !hasError,
      config: configObject,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Parses a `.csproj` file, appending any error diagnostics to [diagnostics].
  ///
  /// Returns `null` and appends a `PL0003` Error if parsing fails.
  Future<dynamic> _parseCsproj(
    String absolutePath,
    List<Diagnostic> diagnostics,
  ) async {
    try {
      return await _inputParser.parseCsproj(absolutePath);
    } on MalformedCsprojException catch (e) {
      diagnostics.add(Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'PL0003',
        message: 'Malformed .csproj file: ${e.details}',
        source: absolutePath,
      ));
      return null;
    } catch (e) {
      diagnostics.add(Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'PL0003',
        message: 'Failed to parse .csproj file: $e',
        source: absolutePath,
      ));
      return null;
    }
  }

  /// Derives the assembly name from the `.csproj` file path.
  ///
  /// Example: `/path/to/MyProject.csproj` → `MyProject`
  static String _deriveAssemblyName(String absolutePath) {
    final fileName = absolutePath.split(RegExp(r'[/\\]')).last;
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex >= 0 ? fileName.substring(0, dotIndex) : fileName;
  }

  /// Maps the `<OutputType>` string to an [OutputKind] enum value.
  static OutputKind _buildOutputKind(String? outputType) {
    switch (outputType?.trim().toLowerCase()) {
      case 'exe':
        return OutputKind.exe;
      case 'winexe':
        return OutputKind.winExe;
      default:
        return OutputKind.library;
    }
  }

  /// Builds a deterministically ordered list of [MetadataReference] entries.
  ///
  /// Order: SDK assemblies (sorted by file name) → NuGet assemblies (sorted by
  /// file name) → project reference assemblies (sorted by path).
  static List<MetadataReference> _buildMetadataRefs(
    List<String> sdkPaths,
    List<String> nugetPaths,
    List<String> projectRefPaths,
  ) {
    final sdkSorted = [...sdkPaths]
      ..sort((a, b) => _basename(a).compareTo(_basename(b)));
    final nugetSorted = [...nugetPaths]
      ..sort((a, b) => _basename(a).compareTo(_basename(b)));
    final projectRefSorted = [...projectRefPaths]..sort();

    return [
      ...sdkSorted.map((p) => MetadataReference(assemblyPath: p)),
      ...nugetSorted.map((p) => MetadataReference(assemblyPath: p)),
      ...projectRefSorted.map((p) => MetadataReference(assemblyPath: p)),
    ];
  }

  /// Returns a [LoadResult] with a single error diagnostic and no projects.
  static LoadResult _errorResult(
    ConfigObject configObject,
    Diagnostic diagnostic,
  ) {
    return LoadResult(
      projects: const [],
      dependencyGraph: DependencyGraph.empty,
      diagnostics: [diagnostic],
      success: false,
      config: configObject,
    );
  }

  /// Returns the file extension including the leading dot, e.g. `.csproj`.
  static String _fileExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot < 0) return '';
    // Ensure the dot is after the last path separator.
    final lastSep = path.lastIndexOf(RegExp(r'[/\\]'));
    if (lastDot < lastSep) return '';
    return path.substring(lastDot);
  }

  /// Returns the basename (file name without directory) of [path].
  static String _basename(String path) {
    final idx = path.lastIndexOf(RegExp(r'[/\\]'));
    return idx < 0 ? path : path.substring(idx + 1);
  }

  // ---------------------------------------------------------------------------
  // Diagnostic aggregation helpers
  // ---------------------------------------------------------------------------

  /// Aggregates [diagnostics] into the canonical order:
  ///   PL diagnostics (sorted) → NR diagnostics (sorted) → CS diagnostics (sorted) → others (sorted)
  ///
  /// Within each prefix group, diagnostics are sorted by:
  ///   1. source file path (nulls last)
  ///   2. line number (nulls last)
  ///   3. column (nulls last)
  static List<Diagnostic> _aggregateDiagnostics(List<Diagnostic> diagnostics) {
    final pl = <Diagnostic>[];
    final nr = <Diagnostic>[];
    final cs = <Diagnostic>[];
    final others = <Diagnostic>[];

    for (final d in diagnostics) {
      final prefix = _diagnosticPrefix(d.code);
      switch (prefix) {
        case 'PL':
          pl.add(d);
        case 'NR':
          nr.add(d);
        case 'CS':
          cs.add(d);
        default:
          others.add(d);
      }
    }

    pl.sort(_compareDiagnostics);
    nr.sort(_compareDiagnostics);
    cs.sort(_compareDiagnostics);
    others.sort(_compareDiagnostics);

    return [...pl, ...nr, ...cs, ...others];
  }

  /// Extracts the alphabetic prefix from a diagnostic code.
  ///
  /// For example, `"PL0001"` → `"PL"`, `"NR0042"` → `"NR"`.
  /// Returns an empty string if the code does not match the expected pattern.
  static String _diagnosticPrefix(String code) {
    final match = RegExp(r'^([A-Z]+)\d{4}$').firstMatch(code);
    return match?.group(1) ?? '';
  }

  /// Compares two [Diagnostic] instances for sorting within a prefix group.
  ///
  /// Sort order: source file path (nulls last) → line number (nulls last) → column (nulls last).
  static int _compareDiagnostics(Diagnostic a, Diagnostic b) {
    final sourceCompare = _compareNullableString(a.source, b.source);
    if (sourceCompare != 0) return sourceCompare;
    final lineCompare =
        _compareNullableInt(a.location?.line, b.location?.line);
    if (lineCompare != 0) return lineCompare;
    return _compareNullableInt(a.location?.column, b.location?.column);
  }

  /// Compares two nullable [String] values, placing nulls last.
  static int _compareNullableString(String? a, String? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  /// Compares two nullable [int] values, placing nulls last.
  static int _compareNullableInt(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }
}
