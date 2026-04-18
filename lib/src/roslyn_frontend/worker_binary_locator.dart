import 'dart:io';

import 'models/interop_exception.dart';

/// Resolves the absolute path to the `cs2dart_roslyn_worker` binary at runtime.
///
/// Search order:
///   1. Explicit [override] path (if provided).
///   2. Next to the executable named cs2dart_roslyn_worker[.exe]
///   3. <packageRoot>/cs2dart_roslyn_worker/bin/cs2dart_roslyn_worker[.exe]
///
/// Throws [InteropException] if the binary does not exist at the resolved path.
final class WorkerBinaryLocator {
  /// Returns the absolute path to the worker binary.
  ///
  /// Search order:
  ///   1. Explicit [override] path (if provided).
  ///   2. Next to the executable named cs2dart_roslyn_worker[.exe]
  ///   3. <packageRoot>/cs2dart_roslyn_worker/bin/cs2dart_roslyn_worker[.exe]
  ///
  /// Throws [InteropException] if the binary does not exist at the resolved path.
  static String resolve({String? override}) {
    final binaryName = Platform.isWindows
        ? 'cs2dart_roslyn_worker.exe'
        : 'cs2dart_roslyn_worker';

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

    // 2. Look next to the current executable.
    final executableDir = File(Platform.resolvedExecutable).parent;
    final siblingPath = '${executableDir.path}/$binaryName';
    if (File(siblingPath).existsSync()) {
      return siblingPath;
    }

    // 3. Resolve relative to the package root.
    final packageRoot = _resolvePackageRoot();
    final packageBinPath =
        '$packageRoot/cs2dart_roslyn_worker/bin/$binaryName';
    if (File(packageBinPath).existsSync()) {
      return packageBinPath;
    }

    throw InteropException(
      message:
          'Worker binary not found. Searched:\n'
          '  (1) $siblingPath\n'
          '  (2) $packageBinPath\n'
          'Ensure the cs2dart_roslyn_worker binary has been built and is '
          'available at one of the above locations.',
    );
  }

  /// Resolves the package root directory (the directory containing
  /// `pubspec.yaml`) by walking up from the current script location.
  ///
  /// Throws [InteropException] if the package root cannot be determined.
  static String _resolvePackageRoot() {
    // Walk up from the current script until we find a pubspec.yaml.
    var dir = File.fromUri(Platform.script).parent;
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
          'No pubspec.yaml ancestor directory could be found. '
          'Provide an explicit workerBinaryPath to PipeInteropBridge.',
    );
  }
}
