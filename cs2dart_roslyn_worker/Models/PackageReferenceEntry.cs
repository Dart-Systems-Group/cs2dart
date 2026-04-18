namespace Cs2DartRoslynWorker.Models;

/// <summary>
/// A NuGet package reference with its resolved version.
/// </summary>
public sealed class PackageReferenceEntry
{
    public string PackageName { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
}
