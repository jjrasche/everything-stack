/// Stub implementation for conditional import.
/// This file is never imported directly - it's replaced by platform-specific
/// implementations via conditional imports.
library;

// import 'package:everything_stack_template/bootstrap/persistence_factory.dart'; // Deleted in Phase 1

/// Platform detection - stub always throws
bool detectWebPlatform() {
  throw UnsupportedError(
    'Cannot detect platform without dart:io or dart:html',
  );
}

/// Initialize platform-specific test persistence.
/// This stub throws - real implementations in _io.dart and _web.dart.
/// Note: PersistenceFactory was removed in Phase 1 refactoring
Future<void> initializeTestPersistence() {
  throw UnsupportedError(
    'Cannot initialize test persistence without dart:io or dart:html',
  );
}

/// Cleanup test persistence.
/// This stub throws - real implementations in _io.dart and _web.dart.
Future<void> cleanupTestPersistence() {
  throw UnsupportedError(
    'Cannot cleanup test persistence without dart:io or dart:html',
  );
}
