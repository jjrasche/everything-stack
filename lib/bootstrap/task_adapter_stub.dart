/// # Task Adapter Stub (Web)
///
/// Stub implementation of TaskObjectBoxAdapter for web platform.
/// On web, we use TaskIndexedDBAdapter instead.

// Dummy class to satisfy import statement on web platform
class TaskObjectBoxAdapter {
  TaskObjectBoxAdapter(dynamic store) {
    throw UnsupportedError('TaskObjectBoxAdapter is not available on web');
  }
}
