import 'dart:io';
import 'dart:isolate';

import 'models/interop_exception.dart';

/// Resolves the absolute path to the `cs2dart_roslyn_worker` binary at runtime.
///
/// Search order:
///   1. Explicit [override] path (if provided and the file exists).
///   2. `<packageRoot>/build/roslyn_worker/cs2dart_roslyn_worker[.exe]`
///
/// Throws [InteropException] if the binary does not exist at the resolved path.
final class WorkerBinaryLocator {
  /// Returns the absolute path to the worker binary.
  ///
  /// If [override] is non-null and the file at that path exists, it is
  /// returned immediately without further resolution.
  ///
  /// Otherwise the binary is expected at
  /// `<packageRoot>/build/roslyn_worker/cs2dart_roslyn_worker[.exe]`,
  /// where `<packageRoot>` is the directory containing the package's
  /// `pubspec.yaml` file (resolved from the package configuration URI).
  ///
  /// Throws [InteropException] with a descriptive message if the binary
  /// cannot be found at the resolved path.
  static Future<String> resolve({String? override}) async {
    // 1. Honour an explicit override if the file exists.
    if (override != null) {
      final overrideFile = File(override);
      if (overrideFile.existsSync()) {
        return override;
      }
      throw InteropException(
        message:
            'Worker binary override path does not exist: $override. '
            'Ensure the file exists at the specified path.',
      );
    }

    // 2. Resolve relative to the package root.
    final packageRoot = await _resolvePackageRoot();
    final binaryName = Platform.isWindows
        ? 'cs2dart_roslyn_worker.exe'
        : 'cs2dart_roslyn_worker';
    final binaryPath =
        '$packageRoot/build/roslyn_worker/$binaryName';

    final binaryFile = File(binaryPath);
    if (binaryFile.existsSync()) {
      return binaryPath;
    }

    throw InteropException(
      message:
          'Worker binary not found at: $binaryPath. '
          'Run "dart run build_runner build" to compile the '
          'cs2dart_roslyn_worker binary before using PipeInteropBridge.',
    );
  }

  /// Resolves the package root directory (the directory containing
  /// `pubspec.yaml`) from the current package configuration URI.
  ///
  /// Falls back to resolving relative to [Platform.script] if the package
  /// configuration is unavailable.
  static Future<String> _resolvePackageRoot() async {
    // Attempt to use Isolate.packageConfig to find the package root.
    // The package config URI typically points to
    // `<packageRoot>/.dart_tool/package_config.json`.
    final packageConfigUri = await Isolate.packageConfig;
    if (packageConfigUri != null) {
      // Navigate up from `.dart_tool/package_config.json` to the package root.
      final packageConfigFile = File.fromUri(packageConfigUri);
      // .dart_tool/ → package root
      final packageRoot = packageConfigFile.parent.parent;
      return packageRoot.path;
    }

    // Fallback: resolve relative to the current script.
    // This handles cases where the isolate package config is unavailable
    // (e.g., when running compiled AOT snapshots).
    final scriptUri = Platform.script;
    // Assume the script is somewhere inside the package; walk up until we
    // find a directory containing pubspec.yaml.
    var dir = File.fromUri(scriptUri).parent;
    for (var i = 0; i < 10; i++) {
      if (File('${dir.path}/pubspec.yaml').existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break; // reached filesystem root
      dir = parent;
    }

    throw InteropException(
      message:
          'Could not determine the Dart package root. '
          'Neither Isolate.packageConfig nor a pubspec.yaml ancestor '
          'directory could be found. '
          'Provide an explicit workerBinaryPath to PipeInteropBridge.',
    );
  }
}
