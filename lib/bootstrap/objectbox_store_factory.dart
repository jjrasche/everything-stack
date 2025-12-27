/// # ObjectBox Store Factory
///
/// Single point for ObjectBox Store initialization.
/// Called by bootstrap on native platforms (Android/iOS/Desktop).

library;

import 'package:flutter/foundation.dart';
import '../objectbox.g.dart';

// Global Store reference to prevent multiple instances
Store? _globalStore;

/// Initialize and open ObjectBox Store.
///
/// On native platforms, creates schema and opens database.
/// Returns same Store instance on subsequent calls (idempotent).
/// Returns: Store instance ready for use.
Future<Store> openObjectBoxStore() async {
  // Return existing store if already initialized
  if (_globalStore != null) {
    debugPrint('ℹ️ ObjectBox Store already initialized, returning existing instance');
    return _globalStore!;
  }

  try {
    final store = await openStore();
    _globalStore = store;
    debugPrint('✅ ObjectBox Store initialized');
    return store;
  } catch (e) {
    // Handle ObjectBox schema mismatch errors (code 10001)
    // This can happen after schema changes (like UUID migration in Phase 6)
    if (e.toString().contains('10001') || e.toString().contains('index')) {
      debugPrint('⚠️ ObjectBox schema mismatch detected');
      debugPrint('   This typically happens after database schema changes');
      debugPrint('   Delete the ObjectBox database directory and restart the app');
      debugPrint('   Location: ~/Documents/objectbox/ or %APPDATA%/objectbox/');
    }

    debugPrint('❌ ObjectBox Store initialization failed: $e');
    rethrow;
  }
}
