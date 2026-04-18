using Cs2DartRoslynWorker.Models;

namespace Cs2DartRoslynWorker;

/// <summary>
/// Processes a single <see cref="ProjectEntryRequest"/> through the normalization pipeline
/// and produces a <see cref="FrontendUnit"/>.
///
/// This is a stub implementation that returns an empty <see cref="FrontendUnit"/>.
/// The full normalization pipeline (Roslyn compilation, semantic model querying,
/// normalization passes, enrichment, and symbol table building) is implemented in
/// subsequent tasks.
/// </summary>
public static class ProjectProcessor
{
    /// <summary>
    /// Processes the given project entry and returns a <see cref="FrontendUnit"/>.
    /// </summary>
    /// <param name="project">The project entry request to process.</param>
    /// <returns>
    /// A <see cref="FrontendUnit"/> with metadata populated from the request and
    /// an empty <see cref="NormalizedSyntaxTree"/> list (stub).
    /// </returns>
    public static FrontendUnit Process(ProjectEntryRequest project)
    {
        // Stub: return an empty FrontendUnit with metadata from the request.
        // Full normalization pipeline is implemented in subsequent tasks.
        return new FrontendUnit
        {
            ProjectName = project.ProjectName,
            OutputKind = project.OutputKind,
            TargetFramework = project.TargetFramework,
            LangVersion = project.LangVersion,
            NullableEnabled = project.NullableEnabled,
            PackageReferences = project.PackageReferences,
            NormalizedTrees = new List<NormalizedSyntaxTree>(),
        };
    }
}
