namespace Cs2DartRoslynWorker.Models;

/// <summary>
/// The plain-data payload sent from the Dart side to the .NET worker.
/// </summary>
public sealed class InteropRequest
{
    /// <summary>
    /// Serialized LoadResult projects (paths, compilation options, references).
    /// </summary>
    public List<ProjectEntryRequest> Projects { get; set; } = new();

    /// <summary>
    /// Active configuration values relevant to the frontend.
    /// </summary>
    public FrontendConfig Config { get; set; } = new();
}

/// <summary>
/// Configuration values extracted from the Dart IConfigService for the worker.
/// </summary>
public sealed class FrontendConfig
{
    /// <summary>
    /// LINQ strategy: "preserve_functional" | "lower_to_loops".
    /// </summary>
    public string LinqStrategy { get; set; } = "preserve_functional";

    /// <summary>
    /// True when nullable reference type analysis is enabled.
    /// </summary>
    public bool NullabilityEnabled { get; set; }

    /// <summary>
    /// Experimental feature flags keyed by feature name.
    /// </summary>
    public Dictionary<string, bool> ExperimentalFeatures { get; set; } = new();
}

/// <summary>
/// A plain-data representation of a ProjectEntry for the interop request.
/// Contains only the fields needed by the .NET worker; Roslyn-typed fields are excluded.
/// </summary>
public sealed class ProjectEntryRequest
{
    /// <summary>The assembly name of the project.</summary>
    public string ProjectName { get; set; } = string.Empty;

    /// <summary>Absolute path to the .csproj file.</summary>
    public string ProjectFilePath { get; set; } = string.Empty;

    /// <summary>Output kind: Exe, Library, or WinExe.</summary>
    public OutputKind OutputKind { get; set; } = OutputKind.Library;

    /// <summary>Resolved target framework moniker, e.g. "net8.0".</summary>
    public string TargetFramework { get; set; } = string.Empty;

    /// <summary>Resolved C# language version string, e.g. "12.0".</summary>
    public string LangVersion { get; set; } = string.Empty;

    /// <summary>True when &lt;Nullable&gt;enable&lt;/Nullable&gt; is set in the project file.</summary>
    public bool NullableEnabled { get; set; }

    /// <summary>Resolved NuGet package references.</summary>
    public List<PackageReferenceEntry> PackageReferences { get; set; } = new();

    /// <summary>Absolute paths to all source files, sorted alphabetically.</summary>
    public List<string> SourceFilePaths { get; set; } = new();

    /// <summary>Absolute paths to metadata (assembly) references.</summary>
    public List<string> MetadataReferences { get; set; } = new();
}
