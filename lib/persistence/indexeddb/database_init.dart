/// # IndexedDB Database Initialization
///
/// ## What it does
/// Handles IndexedDB database initialization, schema creation, and version upgrades.
///
/// ## Usage
/// ```dart
/// // In app initialization:
/// final db = await openIndexedDatabase();
///
/// // Create adapters:
/// final noteAdapter = NoteIndexedDBAdapter(db);
/// final edgeAdapter = EdgeIndexedDBAdapter(db);
/// final versionAdapter = EntityVersionIndexedDBAdapter(db);
/// ```
///
/// ## Version Management
/// - Version 1: Initial schema (notes, edges, entity_versions, _hnsw_index)
/// - Future versions: Add upgrade logic in onUpgradeNeeded
///
/// ## Error Handling
/// - QuotaExceededError: User needs to grant storage permission
/// - InvalidStateError: Database already open (reuse connection)
/// - VersionError: Schema version mismatch (clear data or migrate)

import 'package:idb_shim/idb.dart';
import 'package:idb_shim/idb_browser.dart';
import 'database_schema.dart';
import '../../core/exceptions/persistence_exceptions.dart';

/// Open or create the IndexedDB database.
///
/// Handles:
/// - Schema creation on first run
/// - Version upgrades on schema changes
/// - Error translation to typed exceptions
///
/// Returns the opened Database instance.
/// Throws PersistenceException on failure.
Future<Database> openIndexedDatabase({
  IdbFactory? idbFactory,
}) async {
  // Use browser IDB factory by default
  final factory = idbFactory ?? getIdbFactory();

  if (factory == null) {
    throw PersistenceException(
      'IndexedDB not supported in this environment',
    );
  }

  try {
    final db = await factory.open(
      DatabaseSchema.name,
      version: DatabaseSchema.version,
      onUpgradeNeeded: (VersionChangeEvent event) {
        _onUpgradeNeeded(event);
      },
    );

    return db;
  } catch (error, stackTrace) {
    _translateDatabaseError(error, stackTrace);
  }
}

/// Handle database version upgrades.
///
/// Called when:
/// - Database doesn't exist (oldVersion == 0)
/// - Database version < requested version
///
/// Creates object stores and indexes based on version transitions.
void _onUpgradeNeeded(VersionChangeEvent event) {
  final db = event.database;
  final oldVersion = event.oldVersion;
  final newVersion = event.newVersion ?? DatabaseSchema.version;

  print('IndexedDB upgrade: v$oldVersion → v$newVersion');

  // Version 0 → 1: Create initial schema
  if (oldVersion < 1) {
    _createSchemaV1(db);
  }

  // Future version upgrades go here:
  // if (oldVersion < 2) { _upgradeToV2(db); }
  // if (oldVersion < 3) { _upgradeToV3(db); }
}

/// Create version 1 schema.
///
/// Object stores:
/// - notes: User notes with semantic search
/// - edges: Entity-to-entity connections
/// - entity_versions: Version history for all entities
/// - _hnsw_index: Serialized HNSW index for semantic search
void _createSchemaV1(Database db) {
  print('Creating IndexedDB schema v1...');

  // Create all object stores with their indexes
  for (final storeDef in DatabaseSchema.objectStores) {
    _createObjectStore(db, storeDef);
  }

  print('IndexedDB schema v1 created successfully');
}

/// Create a single object store with indexes.
void _createObjectStore(Database db, ObjectStoreDefinition storeDef) {
  print('  Creating object store: ${storeDef.name}');

  // Create object store
  final store = db.createObjectStore(
    storeDef.name,
    keyPath: storeDef.keyPath,
    autoIncrement: storeDef.autoIncrement,
  );

  // Create indexes
  for (final indexDef in storeDef.indexes) {
    print('    Creating index: ${indexDef.name} on ${indexDef.keyPath}');
    store.createIndex(
      indexDef.name,
      indexDef.keyPath,
      unique: indexDef.unique,
    );
  }
}

/// Translate IndexedDB database errors to typed exceptions.
Never _translateDatabaseError(Object error, StackTrace stackTrace) {
  final errorString = error.toString();

  // Quota exceeded
  if (errorString.contains('QuotaExceededError') ||
      errorString.contains('quota')) {
    throw StorageLimitException(
      'IndexedDB storage quota exceeded. User needs to grant permission.',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  // Invalid state (database already open)
  if (errorString.contains('InvalidStateError')) {
    throw PersistenceException(
      'IndexedDB in invalid state: $errorString',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  // Version error (schema mismatch)
  if (errorString.contains('VersionError')) {
    throw PersistenceException(
      'IndexedDB version mismatch: $errorString',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  // Unknown error
  throw PersistenceException(
    'Failed to open IndexedDB: $errorString',
    cause: error,
    stackTrace: stackTrace,
  );
}

/// Close the database connection.
///
/// Should be called on app shutdown to ensure proper cleanup.
Future<void> closeIndexedDatabase(Database db) async {
  db.close();
}

/// Delete the entire database.
///
/// WARNING: This deletes all data permanently.
/// Use for testing, data reset, or uninstall flows.
Future<void> deleteIndexedDatabase({
  IdbFactory? idbFactory,
}) async {
  final factory = idbFactory ?? getIdbFactory();

  if (factory == null) {
    throw PersistenceException(
      'IndexedDB not supported in this environment',
    );
  }

  try {
    await factory.deleteDatabase(DatabaseSchema.name);
  } catch (error, stackTrace) {
    _translateDatabaseError(error, stackTrace);
  }
}
