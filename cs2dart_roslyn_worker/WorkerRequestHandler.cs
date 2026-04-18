using Cs2DartRoslynWorker.Models;

namespace Cs2DartRoslynWorker;

/// <summary>
/// Handles an <see cref="InteropRequest"/> by iterating over its projects,
/// invoking <see cref="ProjectProcessor"/> for each, and assembling a <see cref="FrontendResult"/>.
/// </summary>
public static class WorkerRequestHandler
{
    /// <summary>
    /// Processes all projects in the request and returns a <see cref="FrontendResult"/>.
    /// </summary>
    /// <param name="request">The deserialized interop request from the Dart side.</param>
    /// <returns>
    /// A <see cref="FrontendResult"/> containing one <see cref="FrontendUnit"/> per project,
    /// plus any diagnostics collected during processing.
    /// </returns>
    public static FrontendResult Handle(InteropRequest request)
    {
        var units = new List<FrontendUnit>(request.Projects.Count);
        var diagnostics = new List<Diagnostic>();

        foreach (var project in request.Projects)
        {
            try
            {
                var unit = ProjectProcessor.Process(project);
                units.Add(unit);
            }
            catch (Exception ex)
            {
                // Emit an RF-prefixed error diagnostic for any unhandled exception
                // during project processing so the Dart side can report it cleanly.
                diagnostics.Add(new Diagnostic
                {
                    Severity = DiagnosticSeverity.Error,
                    Code = "RF0000",
                    Message = $"Unhandled exception processing project '{project.ProjectName}': {ex.Message}",
                    Source = project.ProjectFilePath,
                });
            }
        }

        bool success = !diagnostics.Exists(d => d.Severity == DiagnosticSeverity.Error);

        return new FrontendResult
        {
            Units = units,
            Diagnostics = diagnostics,
            Success = success,
        };
    }
}
