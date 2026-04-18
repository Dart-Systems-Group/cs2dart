import 'symbol_table.dart';
import 'syntax_node.dart';

/// A rewritten syntax tree (plain-data nodes, no Roslyn types) paired with
/// a [SymbolTable].
final class NormalizedSyntaxTree {
  /// Absolute path to the source file this tree was produced from.
  final String filePath;

  /// The root node of the rewritten, annotated syntax tree.
  ///
  /// Contains only plain-data node types — no Roslyn types.
  final SyntaxNode root;

  /// Maps every named-reference node in [root] to its resolved symbol.
  ///
  /// Key: node identity (stable integer ID assigned during normalization).
  /// Value: [ResolvedSymbol] record.
  final SymbolTable symbolTable;

  const NormalizedSyntaxTree({
    required this.filePath,
    required this.root,
    required this.symbolTable,
  });
}
