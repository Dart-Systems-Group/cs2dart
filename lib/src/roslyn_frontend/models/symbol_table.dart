import 'resolved_symbol.dart';

/// A dictionary mapping node IDs to resolved symbols.
///
/// Every named-reference node in a [NormalizedSyntaxTree] has a corresponding
/// entry — either a fully-resolved [ResolvedSymbol] or one with
/// [SymbolKind.unresolved] as the sentinel.
final class SymbolTable {
  /// Maps node identity (assigned during normalization) to its resolved symbol.
  final Map<int, ResolvedSymbol> entries;

  const SymbolTable({required this.entries});

  /// Returns the [ResolvedSymbol] for [nodeId], or null if not present.
  ResolvedSymbol? lookup(int nodeId) => entries[nodeId];
}
