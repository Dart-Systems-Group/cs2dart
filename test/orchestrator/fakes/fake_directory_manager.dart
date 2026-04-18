import 'package:cs2dart/src/orchestrator/interfaces/i_directory_manager.dart';

/// A test double for [IDirectoryManager] that records whether it was called
/// and returns a pre-configured boolean result.
///
/// By default returns `true` (directory creation succeeded), so that the
/// pipeline does not trigger an OR0004 early exit.
///
/// Set [result] to `false` to simulate a directory creation failure, which
/// exercises the Orchestrator's OR0004 error path.
final class FakeDirectoryManager implements IDirectoryManager {
  /// Whether [ensureExists] has been called at least once.
  bool wasCalled = false;

  /// The value returned by [ensureExists]. Defaults to `true` (success).
  bool result = true;

  @override
  Future<bool> ensureExists(String path) async {
    wasCalled = true;
    return result;
  }
}
