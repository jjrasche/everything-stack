/// # Persistence Test Harness
///
/// ## What it does
/// Unified test harness for both native (ObjectBox) and web (IndexedDB) platforms.
/// Handles platform-specific initialization and cleanup.
///
/// ## Usage
/// ```dart
/// final harness = PersistenceTestHarness();
/// await harness.initialize();
/// // Use harness.factory for adapters
/// await harness.dispose();
/// ```

import 'package:everything_stack_template/bootstrap/persistence_factory.dart';

// Conditional import for platform-specific persistence
import 'test_persistence_stub.dart'
    if (dart.library.io) 'test_persistence_io.dart'
    if (dart.library.html) 'test_persistence_web.dart';

/// Test harness for persistence layer
class PersistenceTestHarness {
  PersistenceFactory? _factory;

  /// Get the initialized persistence factory
  PersistenceFactory get factory {
    if (_factory == null) {
      throw StateError('PersistenceTestHarness not initialized. Call initialize() first.');
    }
    return _factory!;
  }

  /// Detect if running on web platform
  /// Note: This is a compile-time check based on conditional imports.
  /// The platform-specific implementation will be selected at compile time.
  bool get isWeb {
    // This function is defined in the conditionally-imported files:
    // - test_persistence_io.dart: returns false (native)
    // - test_persistence_web.dart: returns true (web)
    return detectWebPlatform();
  }

  /// Initialize persistence layer
  Future<void> initialize() async {
    _factory = await initializeTestPersistence();
  }

  /// Clean up and close persistence layer
  Future<void> dispose() async {
    if (_factory != null) {
      await _factory!.close();
      _factory = null;
    }
  }
}

// Platform detection is exported from conditional imports
// This function is defined in test_persistence_io.dart (returns false)
// and test_persistence_web.dart (returns true)
