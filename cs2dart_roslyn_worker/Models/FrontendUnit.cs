namespace Cs2DartRoslynWorker.Models;

/// <summary>
/// The normalized, fully-annotated representation of one C# project.
/// </summary>
public sealed class FrontendUnit
{
    /// <summary>The assembly name of the project.</summary>
    public string ProjectName { get; set; } = string.Empty;

    /// <summary>Output kind: Exe, Library, or WinExe.</summary>
    public OutputKind OutputKind { get; set; } = OutputKind.Library;

    /// <summary>Resolved target framework moniker, e.g. "net8.0".</summary>
    public string TargetFramework { get; set; } = string.Empty;

    /// <summary>Resolved C# language version string, e.g. "12.0".</summary>
    public string LangVersion { get; set; } = string.Empty;

    /// <summary>True when &lt;Nullable&gt;enable&lt;/Nullable&gt; is set in the project file.</summary>
    public bool NullableEnabled { get; set; }

    /// <summary>Resolved NuGet package references (propagated from ProjectEntry).</summary>
    public List<PackageReferenceEntry> PackageReferences { get; set; } = new();

    /// <summary>
    /// One NormalizedSyntaxTree per source file, in alphabetical order by file path.
    /// </summary>
    public List<NormalizedSyntaxTree> NormalizedTrees { get; set; } = new();
}
