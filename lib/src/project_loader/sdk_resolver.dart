import 'dart:io';

import 'interfaces/i_sdk_resolver.dart';
import 'models/diagnostic.dart';
import 'models/sdk_resolve_result.dart';

/// Implements [ISdkResolver] by probing standard .NET SDK installation
/// locations and selecting the highest compatible version.
final class SdkResolver implements ISdkResolver {
  const SdkResolver();

  @override
  Future<SdkResolveResult> resolve(
    String targetFramework, {
    String? sdkPath,
  }) async {
    // 1. If sdkPath is explicitly provided, use it directly.
    if (sdkPath != null) {
      return _resolveFromExplicitPath(sdkPath, targetFramework);
    }

    // 2. Auto-detect: collect candidate pack directories.
    final candidates = _buildCandidatePackDirs();

    // 3. Find the best matching SDK version across all candidates.
    return await _resolveFromCandidates(candidates, targetFramework);
  }

  // ---------------------------------------------------------------------------
  // Explicit sdkPath handling
  // ---------------------------------------------------------------------------

  Future<SdkResolveResult> _resolveFromExplicitPath(
    String sdkPath,
    String targetFramework,
  ) async {
    final dir = Directory(sdkPath);
    if (!dir.existsSync()) {
      return SdkResolveResult(
        assemblyPaths: [],
        diagnostics: [
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'PL0021',
            message:
                'Configured SDK path does not exist: $sdkPath',
          ),
        ],
      );
    }

    // The explicit path IS the pack directory; look for ref dlls inside it.
    final dlls = _collectDllsFromPackDir(sdkPath, targetFramework);
    return SdkResolveResult(assemblyPaths: dlls, diagnostics: []);
  }

  // ---------------------------------------------------------------------------
  // Auto-detection helpers
  // ---------------------------------------------------------------------------

  /// Returns the ordered list of `Microsoft.NETCore.App.Ref` pack directories
  /// to probe, based on the current platform and environment.
  List<String> _buildCandidatePackDirs() {
    final candidates = <String>[];

    // DOTNET_ROOT override takes highest priority.
    final dotnetRoot = Platform.environment['DOTNET_ROOT'];
    if (dotnetRoot != null && dotnetRoot.isNotEmpty) {
      candidates.add(
        _joinPath(dotnetRoot, 'packs', 'Microsoft.NETCore.App.Ref'),
      );
    }

    if (Platform.isWindows) {
      final programFiles = Platform.environment['ProgramFiles'];
      if (programFiles != null && programFiles.isNotEmpty) {
        candidates.add(
          _joinPath(
            programFiles,
            'dotnet',
            'packs',
            'Microsoft.NETCore.App.Ref',
          ),
        );
      }
    } else {
      // macOS / Linux primary location.
      candidates.add(
        '/usr/local/share/dotnet/packs/Microsoft.NETCore.App.Ref',
      );
      // Linux fallback.
      candidates.add(
        '/usr/share/dotnet/packs/Microsoft.NETCore.App.Ref',
      );
    }

    return candidates;
  }

  Future<SdkResolveResult> _resolveFromCandidates(
    List<String> candidates,
    String targetFramework,
  ) async {
    final tfmVersion = _parseTfmVersion(targetFramework);
    if (tfmVersion == null) {
      return SdkResolveResult(
        assemblyPaths: [],
        diagnostics: [
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'PL0020',
            message:
                'Cannot parse target framework moniker: $targetFramework',
          ),
        ],
      );
    }

    _SdkVersion? bestVersion;
    String? bestPackDir;

    for (final packDir in candidates) {
      final dir = Directory(packDir);
      if (!dir.existsSync()) continue;

      // Each subdirectory is a version string like "8.0.0" or "7.0.5".
      final List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        continue;
      }

      for (final entry in entries) {
        if (entry is! Directory) continue;
        final versionStr = _basename(entry.path);
        final version = _SdkVersion.tryParse(versionStr);
        if (version == null) continue;

        // Check compatibility: major version must match the TFM major.
        if (!_isSatisfied(version, tfmVersion)) continue;

        if (bestVersion == null || version.compareTo(bestVersion) > 0) {
          bestVersion = version;
          bestPackDir = entry.path;
        }
      }
    }

    if (bestPackDir == null) {
      return SdkResolveResult(
        assemblyPaths: [],
        diagnostics: [
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'PL0020',
            message:
                'No .NET SDK found for target framework $targetFramework. '
                'Install the .NET SDK or set the sdkPath configuration option.',
          ),
        ],
      );
    }

    final dlls = _collectDllsFromPackDir(bestPackDir, targetFramework);
    return SdkResolveResult(assemblyPaths: dlls, diagnostics: []);
  }

  // ---------------------------------------------------------------------------
  // DLL collection
  // ---------------------------------------------------------------------------

  /// Collects `.dll` files from `{packDir}/ref/{tfm}/`, sorted by basename.
  List<String> _collectDllsFromPackDir(
    String packDir,
    String targetFramework,
  ) {
    final refDir = Directory(_joinPath(packDir, 'ref', targetFramework));
    if (!refDir.existsSync()) return [];

    final List<FileSystemEntity> entries;
    try {
      entries = refDir.listSync(followLinks: false);
    } catch (_) {
      return [];
    }

    final dlls = entries
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.dll'))
        .map((f) => f.path)
        .toList();

    // Sort by basename for determinism.
    dlls.sort((a, b) => _basename(a).compareTo(_basename(b)));
    return dlls;
  }

  // ---------------------------------------------------------------------------
  // Version / TFM helpers
  // ---------------------------------------------------------------------------

  /// Parses a TFM like `net8.0` into a `(major, minor)` record.
  /// Returns `null` if the TFM cannot be parsed.
  ({int major, int minor})? _parseTfmVersion(String tfm) {
    // Expected format: net{major}.{minor}
    final match = RegExp(r'^net(\d+)\.(\d+)$').firstMatch(tfm);
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    if (major == null || minor == null) return null;
    return (major: major, minor: minor);
  }

  /// Returns `true` when [sdkVersion] satisfies the TFM version.
  ///
  /// A SDK version satisfies `net{X}.{Y}` when its major version equals X.
  bool _isSatisfied(
    _SdkVersion sdkVersion,
    ({int major, int minor}) tfmVersion,
  ) {
    return sdkVersion.major == tfmVersion.major;
  }

  // ---------------------------------------------------------------------------
  // Path utilities
  // ---------------------------------------------------------------------------

  String _joinPath(String base, String part1, [String? part2, String? part3]) {
    final sep = Platform.pathSeparator;
    var result = '$base$sep$part1';
    if (part2 != null) result = '$result$sep$part2';
    if (part3 != null) result = '$result$sep$part3';
    return result;
  }

  String _basename(String path) {
    final sep = Platform.pathSeparator;
    final idx = path.lastIndexOf(sep);
    if (idx < 0) return path;
    return path.substring(idx + 1);
  }
}

// ---------------------------------------------------------------------------
// Internal version representation
// ---------------------------------------------------------------------------

final class _SdkVersion implements Comparable<_SdkVersion> {
  final int major;
  final int minor;
  final int patch;

  const _SdkVersion(this.major, this.minor, this.patch);

  static _SdkVersion? tryParse(String s) {
    final parts = s.split('.');
    if (parts.length < 2) return null;
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = parts.length >= 3 ? (int.tryParse(parts[2]) ?? 0) : 0;
    if (major == null || minor == null) return null;
    return _SdkVersion(major, minor, patch);
  }

  @override
  int compareTo(_SdkVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}
