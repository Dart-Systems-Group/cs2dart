namespace Cs2DartRoslynWorker.Models;

/// <summary>
/// A source location within a file (line and column are 1-based).
/// </summary>
public sealed class SourceLocation
{
    public string FilePath { get; set; } = string.Empty;
    public int Line { get; set; }
    public int Column { get; set; }
}
