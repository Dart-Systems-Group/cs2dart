import '../models/sdk_resolve_result.dart';

/// Locates .NET SDK reference assemblies for a given target framework.
abstract interface class ISdkResolver {
  /// Resolves the reference assembly paths for [targetFramework].
  ///
  /// Uses [sdkPath] when non-null; otherwise auto-detects the SDK from
  /// standard installation locations and the `DOTNET_ROOT` environment variable.
  ///
  /// Returns a [SdkResolveResult] containing assembly paths and any diagnostics.
  /// Emits `PL0020` Error when no matching SDK is found.
  /// Emits `PL0021` Error when the configured [sdkPath] does not exist.
  Future<SdkResolveResult> resolve(String targetFramework, {String? sdkPath});
}
