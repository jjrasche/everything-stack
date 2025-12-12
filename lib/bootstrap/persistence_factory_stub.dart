/// Stub implementation for conditional import.
/// This file is never imported directly - it's replaced by platform-specific
/// implementations via conditional imports.
library;

import 'persistence_factory.dart';

/// Initialize platform-specific persistence layer.
/// This stub throws - real implementations in _io.dart and _web.dart.
Future<PersistenceFactory> initializePersistence() {
  throw UnsupportedError(
    'Cannot initialize persistence without dart:io or dart:html',
  );
}
