import 'dart:io';

import 'interfaces/i_directory_manager.dart';

export 'interfaces/i_directory_manager.dart';

/// Manages output directory creation for the pipeline orchestrator.
///
/// Provides a safe wrapper around [Directory.create] that catches exceptions
/// and returns a boolean result instead of propagating errors.
final class DirectoryManager implements IDirectoryManager {
  const DirectoryManager();

  /// Ensures the directory at [path] exists, creating it (and any intermediate
  /// directories) if necessary.
  ///
  /// Returns `true` if the directory already exists or was successfully
  /// created. Returns `false` if creation fails for any reason (e.g.,
  /// permission denied), catching all exceptions internally.
  Future<bool> ensureExists(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) return true;
      await dir.create(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
