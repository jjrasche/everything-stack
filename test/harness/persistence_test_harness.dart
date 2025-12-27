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

// NOTE: PersistenceFactory deleted in refactoring Phase 1
// Test harness will be refactored in Phase 9
//import 'package:everything_stack_template/bootstrap/persistence_factory.dart';

// Conditional import for platform-specific persistence
import 'test_persistence_stub.dart'
    if (dart.library.io) 'test_persistence_io.dart'
    if (dart.library.html) 'test_persistence_web.dart' as persistence;

/// Test harness for persistence layer
/// Note: PersistenceFactory deleted in Phase 1 refactoring
class PersistenceTestHarness {
  bool _initialized = false;

  /// Detect if running on web platform
  /// Note: This is a compile-time check based on conditional imports.
  /// The platform-specific implementation will be selected at compile time.
  bool get isWeb {
    // This function is defined in the conditionally-imported files:
    // - test_persistence_io.dart: returns false (native)
    // - test_persistence_web.dart: returns true (web)
    return persistence.detectWebPlatform();
  }

  /// Initialize persistence layer
  Future<void> initialize() async {
    await persistence.initializeTestPersistence();
    _initialized = true;
  }

  /// Clean up and close persistence layer
  Future<void> dispose() async {
    if (_initialized) {
      await persistence.cleanupTestPersistence();
      _initialized = false;
    }
  }
}

// Platform detection is exported from conditional imports
// This function is defined in test_persistence_io.dart (returns false)
// and test_persistence_web.dart (returns true)
