namespace Cs2DartRoslynWorker.Models;

/// <summary>
/// Severity level for a diagnostic message.
/// </summary>
public enum DiagnosticSeverity
{
    Error,
    Warning,
    Info,
}

/// <summary>
/// A structured diagnostic message conforming to the pipeline-wide schema.
/// Diagnostic codes use a prefix followed by a 4-digit number, e.g. RF0001, CS0001.
/// </summary>
public sealed class Diagnostic
{
    public DiagnosticSeverity Severity { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public string? Source { get; set; }
    public SourceLocation? Location { get; set; }
}
