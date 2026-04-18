import 'models/dependency_graph.dart';
import 'models/dependency_node.dart';
import 'models/diagnostic.dart';
import 'models/project_file_data.dart';

/// The result of building a [DependencyGraph] from a list of [ProjectFileData].
final class DependencyGraphResult {
  /// The constructed dependency graph.
  final DependencyGraph graph;

  /// Topologically sorted project paths (leaf-first).
  ///
  /// Empty when a cycle is detected.
  final List<String> sortedProjectPaths;

  /// Any [PL0011] diagnostics emitted during graph construction.
  final List<Diagnostic> diagnostics;

  const DependencyGraphResult({
    required this.graph,
    required this.sortedProjectPaths,
    required this.diagnostics,
  });
}

/// Builds a [DependencyGraph] from a list of [ProjectFileData] and performs
/// a topological sort with cycle detection.
final class DependencyGraphBuilder {
  /// Builds a [DependencyGraph] from [projects] and returns a
  /// [DependencyGraphResult] containing the graph, sorted project paths,
  /// and any diagnostics.
  ///
  /// - Leaf projects (no dependencies) appear first in [DependencyGraphResult.sortedProjectPaths].
  /// - Ties are broken alphabetically by project path.
  /// - If a cycle is detected, [DependencyGraphResult.sortedProjectPaths] is empty
  ///   and a `PL0011` Error diagnostic is emitted.
  DependencyGraphResult build(List<ProjectFileData> projects) {
    final projectPaths = {for (final p in projects) p.absolutePath};

    // Build nodes and edges.
    final nodes = <String, DependencyNode>{};
    final edges = <String, Set<String>>{};

    for (final project in projects) {
      final assemblyName = project.assemblyName ?? _deriveAssemblyName(project.absolutePath);

      // Only include edges to projects that are in the input set.
      final deps = project.projectReferencePaths
          .where((ref) => projectPaths.contains(ref))
          .toList();

      nodes[project.absolutePath] = DependencyNode(
        projectPath: project.absolutePath,
        projectName: assemblyName,
        dependsOn: deps,
      );

      edges[project.absolutePath] = deps.toSet();
    }

    final graph = DependencyGraph(nodes: nodes, edges: edges);

    // Perform DFS-based topological sort with cycle detection.
    final result = _topoSort(graph);

    if (result.cycle != null) {
      final cycleProjects = result.cycle!.join(', ');
      final diagnostic = Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'PL0011',
        message: 'Dependency cycle detected involving projects: [$cycleProjects]',
      );
      return DependencyGraphResult(
        graph: graph,
        sortedProjectPaths: const [],
        diagnostics: [diagnostic],
      );
    }

    return DependencyGraphResult(
      graph: graph,
      sortedProjectPaths: result.sorted,
      diagnostics: const [],
    );
  }

  /// Derives the assembly name from the `.csproj` file path.
  ///
  /// Example: `path/to/MyProject.csproj` → `MyProject`
  static String _deriveAssemblyName(String absolutePath) {
    final fileName = absolutePath.split(RegExp(r'[/\\]')).last;
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex >= 0 ? fileName.substring(0, dotIndex) : fileName;
  }
}

// ---------------------------------------------------------------------------
// Internal DFS topological sort
// ---------------------------------------------------------------------------

enum _VisitState { unvisited, visiting, visited }

final class _TopoResult {
  final List<String> sorted;
  final List<String>? cycle;

  const _TopoResult({required this.sorted, this.cycle});
}

_TopoResult _topoSort(DependencyGraph graph) {
  final state = <String, _VisitState>{
    for (final key in graph.nodes.keys) key: _VisitState.unvisited,
  };

  final sorted = <String>[];
  final stack = <String>[];

  // Visit nodes in alphabetical order for deterministic tie-breaking.
  final allPaths = graph.nodes.keys.toList()..sort();

  for (final path in allPaths) {
    if (state[path] == _VisitState.unvisited) {
      final cycle = _dfs(path, graph, state, stack, sorted);
      if (cycle != null) {
        return _TopoResult(sorted: const [], cycle: cycle);
      }
    }
  }

  return _TopoResult(sorted: sorted);
}

/// Returns the cycle path if a cycle is detected, otherwise null.
List<String>? _dfs(
  String node,
  DependencyGraph graph,
  Map<String, _VisitState> state,
  List<String> stack,
  List<String> sorted,
) {
  state[node] = _VisitState.visiting;
  stack.add(node);

  // Visit neighbours in alphabetical order for determinism.
  final neighbours = (graph.edges[node] ?? <String>{}).toList()..sort();

  for (final neighbour in neighbours) {
    final neighbourState = state[neighbour];
    if (neighbourState == _VisitState.visiting) {
      // Cycle detected — collect the cycle from the stack.
      final cycleStart = stack.indexOf(neighbour);
      final cycle = stack.sublist(cycleStart).toList()..sort();
      return cycle;
    }
    if (neighbourState == _VisitState.unvisited) {
      final cycle = _dfs(neighbour, graph, state, stack, sorted);
      if (cycle != null) return cycle;
    }
  }

  stack.removeLast();
  state[node] = _VisitState.visited;
  // Leaf-first: add after all dependencies are processed.
  sorted.add(node);
  return null;
}
