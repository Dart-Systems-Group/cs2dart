import 'dependency_node.dart';

/// The inter-project dependency graph for a solution.
///
/// Used to determine topological processing order (leaf projects first).
final class DependencyGraph {
  /// All project nodes, keyed by absolute `.csproj` path.
  final Map<String, DependencyNode> nodes;

  /// Directed edges: a key project depends on all projects in its value set.
  final Map<String, Set<String>> edges;

  const DependencyGraph({
    required this.nodes,
    required this.edges,
  });

  /// An empty dependency graph with no nodes or edges.
  static const DependencyGraph empty = DependencyGraph(nodes: {}, edges: {});
}
