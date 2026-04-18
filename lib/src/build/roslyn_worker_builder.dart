import 'dart:io';
import 'dart:typed_data';
import 'package:glob/glob.dart';

import 'package:build/build.dart';

/// A [Builder] that invokes `dotnet publish` to produce the self-contained
/// `cs2dart_roslyn_worker` binary for the current platform.
///
/// Inputs:  `cs2dart_roslyn_worker/cs2dart_roslyn_worker.csproj`
/// Outputs: `build/roslyn_worker/cs2dart_roslyn_worker[.exe]`
Builder roslynWorkerBuilder(BuilderOptions options) => RoslynWorkerBuilder();

class RoslynWorkerBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
        // Only specify .csproj, so we run once per csproj.
        '.csproj': [
          '.dotnet_published',
        ],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Read all .cs files so build system knows we depend on the file contents.
    final csFiles = await buildStep.findAssets(Glob('**.cs')).toList();
    for (final asset in [...csFiles, buildStep.inputId]) {
      await buildStep.canRead(asset);
    }

    final rid = _runtimeIdentifier();
    final binary = _binaryName();

    log.info('Running dotnet publish for ${buildStep.inputId.path} RID=$rid ...');

    final result = await Process.run(
      'dotnet',
      [
        'publish',
        'cs2dart_roslyn_worker/cs2dart_roslyn_worker.csproj',
        '-c',
        'Release',
        '-r',
        rid,
        '--self-contained',
        'true',
        '-o',
        'cs2dart_roslyn_worker/bin/',
      ],
      runInShell: Platform.isWindows,
    );

    if (result.exitCode != 0) {
      throw StateError(
        'dotnet publish failed (exit ${result.exitCode}):\n'
        '${result.stdout}\n${result.stderr}',
      );
    }

    final compiledPath = 'cs2dart_roslyn_worker/bin/$binary';
    log.info('dotnet publish succeeded. Binary: $compiledPath');

    // Write a synthetic asset so build_runner tracks the output.
    final outputId = AssetId(
      buildStep.inputId.package,
      'cs2dart_roslyn_worker/cs2dart_roslyn_worker.dotnet_published',
    );
    final outputFile = File(compiledPath);
    if (!await outputFile.exists()) {
      throw StateError(
        'Expected output binary not found: $compiledPath',
      );
    }
    await buildStep.writeAsBytes(outputId, Uint8List(0));
  }

  /// Returns the .NET Runtime Identifier for the current platform.
  ///
  /// - Linux  → `linux-x64`
  /// - macOS  → `osx-arm64` on Apple Silicon, `osx-x64` otherwise
  /// - Windows → `win-x64`
  static String _runtimeIdentifier() {
    switch (Platform.operatingSystem) {
      case 'linux':
        return 'linux-x64';
      case 'macos':
        return _macosRid();
      case 'windows':
        return 'win-x64';
      default:
        throw UnsupportedError(
          'Unsupported platform for dotnet publish: ${Platform.operatingSystem}',
        );
    }
  }

  /// Determines the macOS RID by checking the CPU architecture.
  ///
  /// Uses `uname -m` to detect Apple Silicon (`arm64`) vs Intel (`x86_64`).
  static String _macosRid() {
    try {
      final result = Process.runSync('uname', ['-m']);
      if (result.exitCode == 0) {
        final arch = (result.stdout as String).trim();
        if (arch == 'arm64') return 'osx-arm64';
      }
    } catch (_) {
      // Fall through to default.
    }
    return 'osx-x64';
  }

  /// Returns the platform-specific binary name.
  static String _binaryName() {
    return Platform.isWindows
        ? 'cs2dart_roslyn_worker.exe'
        : 'cs2dart_roslyn_worker';
  }
}
