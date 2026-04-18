import 'dart:io';

import '../config/i_config_service.dart';
import 'interfaces/i_nuget_handler.dart';
import 'models/diagnostic.dart';
import 'models/nuget_resolve_result.dart';
import 'models/package_reference_entry.dart';
import 'models/package_reference_spec.dart';
import 'models/roslyn_interop.dart';

/// Diagnostic code emitted when a package cannot be found in the local cache.
const _kNR0001 = 'NR0001';

/// A registry entry describing a known Tier 1 NuGet package.
final class _MappingEntry {
  final int tier;
  final DartMapping? dartMapping;

  const _MappingEntry({required this.tier, this.dartMapping});
}

/// Hardcoded mapping registry for well-known NuGet packages.
///
/// Tier 1 — packages with a known Dart equivalent.
/// Tier 2 — packages that will be transpiled (no Dart mapping).
/// Unknown packages default to Tier 3 (stubbed).
const Map<String, _MappingEntry> _kMappingRegistry = {
  'Newtonsoft.Json': _MappingEntry(
    tier: 1,
    dartMapping: DartMapping(
      dartPackageName: 'dart_convert',
      dartImportPath: 'dart:convert',
    ),
  ),
  'System.Text.Json': _MappingEntry(
    tier: 1,
    dartMapping: DartMapping(
      dartPackageName: 'dart_convert',
      dartImportPath: 'dart:convert',
    ),
  ),
};

/// Resolves NuGet package references from the local NuGet cache and classifies
/// each package into a tier using the [_kMappingRegistry] and config overrides.
///
/// Resolution strategy:
/// 1. Check the local NuGet cache for the package assembly.
/// 2. If not found, emit an [_kNR0001] Error diagnostic and continue.
///
/// Tier classification:
/// - Tier 1: known Dart equivalent — [DartMapping] is populated.
/// - Tier 2: will be transpiled — [dartMapping] is null.
/// - Tier 3 (default): stubbed — [dartMapping] is null; assembly NOT added.
///
/// TODO: Transitive dependency resolution (parsing `.nuspec` files) is not yet
/// implemented. Only direct dependencies are resolved in this version.
final class NuGetHandler implements INuGetHandler {
  const NuGetHandler();

  @override
  Future<NuGetResolveResult> resolve(
    List<PackageReferenceSpec> packageReferences,
    String targetFramework,
    IConfigService config,
  ) async {
    final assemblyPaths = <String>[];
    final entries = <PackageReferenceEntry>[];
    final diagnostics = <Diagnostic>[];

    for (final ref in packageReferences) {
      final entry = await _resolvePackage(
        ref,
        targetFramework,
        config,
        assemblyPaths,
        diagnostics,
      );
      entries.add(entry);
    }

    return NuGetResolveResult(
      assemblyPaths: assemblyPaths,
      packageReferences: entries,
      diagnostics: diagnostics,
    );
  }

  Future<PackageReferenceEntry> _resolvePackage(
    PackageReferenceSpec ref,
    String targetFramework,
    IConfigService config,
    List<String> assemblyPaths,
    List<Diagnostic> diagnostics,
  ) async {
    final classification = _classifyPackage(ref.packageName, config);
    final tier = classification.tier;
    final dartMapping = classification.dartMapping;

    // Tier 3 packages are stubbed — no assembly is added.
    if (tier == 3) {
      return PackageReferenceEntry(
        packageName: ref.packageName,
        version: ref.version,
        tier: tier,
        dartMapping: null,
      );
    }

    // For Tier 1 and Tier 2, attempt to locate the assembly in the local cache.
    final dllPaths = _findAssembliesInCache(
      ref.packageName,
      ref.version,
      targetFramework,
    );

    if (dllPaths.isEmpty) {
      diagnostics.add(Diagnostic(
        severity: DiagnosticSeverity.error,
        code: _kNR0001,
        message:
            'Package "${ref.packageName}" version "${ref.version}" could not be '
            'found in the local NuGet cache. '
            'Run "dotnet restore" to populate the cache.',
      ));
      // Downgrade to Tier 3 when the assembly is missing (per design doc).
      return PackageReferenceEntry(
        packageName: ref.packageName,
        version: ref.version,
        tier: 3,
        dartMapping: null,
      );
    }

    assemblyPaths.addAll(dllPaths);

    return PackageReferenceEntry(
      packageName: ref.packageName,
      version: ref.version,
      tier: tier,
      dartMapping: dartMapping,
    );
  }

  /// Classifies a package using the hardcoded registry and config overrides.
  ///
  /// Config overrides are checked first via [IConfigService.packageMappings].
  /// A non-empty mapping value indicates Tier 1; an empty string indicates
  /// Tier 2. If no override is present, the hardcoded registry is consulted.
  /// Unknown packages default to Tier 3.
  _MappingEntry _classifyPackage(String packageName, IConfigService config) {
    // Check config-level package mapping overrides.
    final packageMappings = config.packageMappings;
    if (packageMappings.containsKey(packageName)) {
      final mappedValue = packageMappings[packageName]!;
      if (mappedValue.isNotEmpty) {
        // Non-empty mapping → Tier 1 with the provided Dart import path.
        return _MappingEntry(
          tier: 1,
          dartMapping: DartMapping(
            dartPackageName: mappedValue,
            dartImportPath: mappedValue,
          ),
        );
      } else {
        // Empty mapping → Tier 2 (transpiled, no Dart equivalent).
        return const _MappingEntry(tier: 2);
      }
    }

    // Fall back to the hardcoded registry.
    return _kMappingRegistry[packageName] ?? const _MappingEntry(tier: 3);
  }

  /// Searches the local NuGet cache for `.dll` files matching the given
  /// package, version, and target framework.
  ///
  /// Cache locations:
  /// - Linux/macOS: `~/.nuget/packages/{id}/{version}/lib/{tfm}/*.dll`
  /// - Windows:     `%USERPROFILE%\.nuget\packages\{id}\{version}\lib\{tfm}\*.dll`
  ///                `%LOCALAPPDATA%\NuGet\Cache\{id}\{version}\lib\{tfm}\*.dll`
  List<String> _findAssembliesInCache(
    String packageName,
    String version,
    String targetFramework,
  ) {
    final packageId = packageName.toLowerCase();
    final cacheDirs = _nugetCacheDirectories();

    for (final cacheDir in cacheDirs) {
      final packageDir = Directory(
        [cacheDir, packageId, version, 'lib', targetFramework].join(
          Platform.pathSeparator,
        ),
      );

      if (packageDir.existsSync()) {
        final dlls = packageDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.dll'))
            .map((f) => f.absolute.path)
            .toList();

        if (dlls.isNotEmpty) {
          return dlls;
        }
      }

      // Also try without a TFM subdirectory (some packages place DLLs in lib/).
      final libDir = Directory(
        [cacheDir, packageId, version, 'lib'].join(Platform.pathSeparator),
      );

      if (libDir.existsSync()) {
        final dlls = libDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.dll'))
            .map((f) => f.absolute.path)
            .toList();

        if (dlls.isNotEmpty) {
          return dlls;
        }
      }
    }

    return const [];
  }

  /// Returns the list of candidate NuGet cache root directories for the
  /// current platform, in priority order.
  List<String> _nugetCacheDirectories() {
    final dirs = <String>[];

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        dirs.add('$userProfile\\.nuget\\packages');
      }
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        dirs.add('$localAppData\\NuGet\\Cache');
      }
    } else {
      // Linux / macOS
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        dirs.add('$home/.nuget/packages');
      }
    }

    return dirs;
  }
}
