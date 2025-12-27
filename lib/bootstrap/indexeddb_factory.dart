/// # IndexedDB Factory
///
/// Single point for IndexedDB initialization.
/// Called by bootstrap on web platform.

import 'package:idb_shim/idb.dart';
import 'package:idb_shim/idb_browser.dart';
import '../persistence/indexeddb/database_schema.dart';

/// Initialize and open IndexedDB database.
///
/// On web, opens or creates database with required schema.
/// Returns: Database instance ready for use.
Future<Database> openIndexedDB() async {
  try {
    // idbFactory is a global from idb_browser.dart on web platform
    final factory = getIdbFactory();
    if (factory == null) {
      throw Exception('IndexedDB not available on this platform');
    }
    final db = await factory.open(
      'everything_stack_db',
      version: 1,
      onUpgradeNeeded: (VersionChangeEvent e) {
        final db = e.database;

        // Create object stores
        _createObjectStores(db);
      },
    );

    print('✅ IndexedDB initialized');
    return db;
  } catch (e) {
    print('❌ IndexedDB initialization failed: $e');
    rethrow;
  }
}

/// Create all required IndexedDB object stores.
void _createObjectStores(Database db) {
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
  if (!db.objectStoreNames.contains(ObjectStores.turns)) {
    db.createObjectStore(ObjectStores.turns, keyPath: 'uuid');
  }
}
