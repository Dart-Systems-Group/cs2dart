/// The Orchestrator-facing interface for output directory management.
///
/// Provides a safe wrapper around directory creation that returns a boolean
/// result instead of propagating errors.
abstract interface class IDirectoryManager {
  /// Ensures the directory at [path] exists, creating it (and any intermediate
  /// directories) if necessary.
  ///
  /// Returns `true` if the directory already exists or was successfully
  /// created. Returns `false` if creation fails for any reason (e.g.,
  /// permission denied).
  Future<bool> ensureExists(String path);
}
