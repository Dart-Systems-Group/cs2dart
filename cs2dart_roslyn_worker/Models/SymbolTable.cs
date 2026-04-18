namespace Cs2DartRoslynWorker.Models;

/// <summary>
/// A dictionary mapping node IDs to resolved symbols.
/// Every named-reference node in a NormalizedSyntaxTree has a corresponding entry.
/// </summary>
public sealed class SymbolTable
{
    /// <summary>
    /// Maps node identity (assigned during normalization) to its resolved symbol.
    /// </summary>
    public Dictionary<int, ResolvedSymbol> Entries { get; set; } = new();

    /// <summary>Returns the ResolvedSymbol for nodeId, or null if not present.</summary>
    public ResolvedSymbol? Lookup(int nodeId) =>
        Entries.TryGetValue(nodeId, out var symbol) ? symbol : null;
}
