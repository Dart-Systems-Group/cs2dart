namespace Cs2DartRoslynWorker.Models;

/// <summary>
/// The complete output of the Roslyn_Frontend stage, serialized back to the Dart side.
/// </summary>
public sealed class FrontendResult
{
    /// <summary>
    /// One FrontendUnit per project, in the same order as the request's Projects list
    /// (topological, leaf-first).
    /// </summary>
    public List<FrontendUnit> Units { get; set; } = new();

    /// <summary>
    /// Aggregated diagnostics: RF-prefixed diagnostics from the frontend followed by
    /// CS-prefixed Roslyn compiler diagnostics.
    /// </summary>
    public List<Diagnostic> Diagnostics { get; set; } = new();

    /// <summary>True if and only if Diagnostics contains no Error-severity entry.</summary>
    public bool Success { get; set; }
}
