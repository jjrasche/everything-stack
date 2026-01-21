/// # IndexedDB Factory
///
/// Single point for IndexedDB initialization.
/// Called by bootstrap on web platform.

library;

import 'package:flutter/foundation.dart';
import 'dart:indexed_db' as idb;
import 'dart:html' show window;
import '../persistence/indexeddb/database_schema.dart';

/// Initialize and open IndexedDB database.
///
/// On web, opens or creates database with required schema.
/// Returns: Database instance ready for use.
Future<idb.Database> openIndexedDB() async {
  try {
    // Use browser IndexedDB directly via dart:indexed_db
    final factory = window.indexedDB;
    if (factory == null) {
      throw Exception('IndexedDB not available on this platform');
    }
    final db = await factory.open(
      'everything_stack_db',
      version: 1,
      onUpgradeNeeded: (idb.VersionChangeEvent e) {
        final db = e.database;

        // Create object stores
        _createObjectStores(db);
      },
    );

    debugPrint('✅ IndexedDB initialized');
    return db;
  } catch (e) {
    debugPrint('❌ IndexedDB initialization failed: $e');
    rethrow;
  }
}

/// Create all required IndexedDB object stores.
void _createObjectStores(idb.Database db) {
  // Create stores if they don't exist
  if (!db.objectStoreNames.contains(ObjectStores.invocations)) {
    db.createObjectStore(ObjectStores.invocations, keyPath: 'uuid');
  }
  if (!db.objectStoreNames.contains(ObjectStores.adaptation_state)) {
    db.createObjectStore(ObjectStores.adaptation_state, keyPath: 'uuid');
  }
  if (!db.objectStoreNames.contains(ObjectStores.feedback)) {
    db.createObjectStore(ObjectStores.feedback, keyPath: 'uuid');
  }
  if (!db.objectStoreNames.contains(ObjectStores.embeddingTasks)) {
    final store = db.createObjectStore(
      ObjectStores.embeddingTasks,
      keyPath: 'id',
      autoIncrement: true,
    );
    store.createIndex('entityUuid', 'entityUuid', unique: false);
    store.createIndex('status', 'status', unique: false);
  }
}
