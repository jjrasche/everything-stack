/// Stub implementation for conditional import.
/// This file is never imported directly - it's replaced by platform-specific
/// implementations via conditional imports.
library;

import 'package:everything_stack_template/bootstrap/persistence_factory.dart';

/// Initialize platform-specific test persistence.
/// This stub throws - real implementations in _io.dart and _web.dart.
Future<PersistenceFactory> initTestPersistence() {
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
