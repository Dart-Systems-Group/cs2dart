namespace Cs2DartRoslynWorker.Models;

/// <summary>
/// A rewritten syntax tree (plain-data nodes, no Roslyn types) paired with a SymbolTable.
/// </summary>
public sealed class NormalizedSyntaxTree
{
    /// <summary>Absolute path to the source file this tree was produced from.</summary>
    public string FilePath { get; set; } = string.Empty;

    /// <summary>
    /// The root node of the rewritten, annotated syntax tree.
    /// Represented as a generic object for the stub; full node types are defined in
    /// subsequent normalization pipeline tasks.
    /// </summary>
    public object? Root { get; set; }

    /// <summary>
    /// Maps every named-reference node in Root to its resolved symbol.
    /// Key: node identity (stable integer ID assigned during normalization).
    /// </summary>
    public SymbolTable SymbolTable { get; set; } = new();
}
