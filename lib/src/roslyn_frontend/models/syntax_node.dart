/// Abstract base class for all plain-data syntax nodes in a
/// [NormalizedSyntaxTree].
///
/// Concrete node types are defined in the IR_Builder specification.
/// This base class exists so that [NormalizedSyntaxTree.root] has a typed
/// reference without depending on any Roslyn types.
abstract class SyntaxNode {
  /// Stable integer ID assigned during normalization.
  ///
  /// Used as the key in [SymbolTable.entries] to look up the resolved symbol
  /// for named-reference nodes.
  final int nodeId;

  const SyntaxNode({required this.nodeId});
}
