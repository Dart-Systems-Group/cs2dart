namespace Cs2DartRoslynWorker.Models;

/// <summary>
/// The kind of a resolved symbol.
/// </summary>
public enum SymbolKind
{
    Type,
    Method,
    Field,
    Property,
    Event,
    Local,
    Parameter,
    /// <summary>Sentinel: Roslyn could not bind this reference.</summary>
    Unresolved,
}

/// <summary>
/// A plain-data record representing a fully-resolved Roslyn symbol.
/// No Roslyn types appear in this record.
/// </summary>
public sealed class ResolvedSymbol
{
    /// <summary>Fully-qualified name, e.g. "System.Collections.Generic.List&lt;T&gt;".</summary>
    public string FullyQualifiedName { get; set; } = string.Empty;

    /// <summary>The assembly that defines this symbol, e.g. "System.Collections".</summary>
    public string AssemblyName { get; set; } = string.Empty;

    /// <summary>The kind of symbol.</summary>
    public SymbolKind Kind { get; set; }

    /// <summary>
    /// NuGet package ID when the symbol comes from an external package;
    /// null when the symbol is defined in the same compilation or the BCL.
    /// </summary>
    public string? SourcePackageId { get; set; }

    /// <summary>Source location of the symbol's declaration; null for external symbols.</summary>
    public SourceLocation? SourceLocation { get; set; }

    /// <summary>Compile-time constant value for const symbols; null otherwise.</summary>
    public object? ConstantValue { get; set; }
}
