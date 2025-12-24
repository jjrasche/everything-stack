/// # IndexedDB Database Schema
///
/// ## What it does
/// Defines the IndexedDB database schema for web platform persistence.
/// Mirrors ObjectBox schema but adapted for IndexedDB capabilities.
///
/// ## Design decisions
///
/// ### HNSW Semantic Search
/// ObjectBox has native HNSW indexing. IndexedDB doesn't.
///
/// **Solution: Persisted In-Memory Index**
/// - Embeddings stored in IndexedDB as part of note JSON
/// - HNSW index built in memory using local_hnsw package
/// - Index serialized and persisted in _hnsw_index object store
/// - On app load: Deserialize from IndexedDB (fast)
/// - On save/delete: Update in-memory + mark dirty
/// - On close/periodically: Serialize back to IndexedDB
/// - Fallback: If index missing/corrupt, rebuild from embeddings
///
/// ### Why persist HNSW?
/// - Fast app startup (deserialize vs rebuild)
/// - Better UX from day 1
/// - local_hnsw supports serialization
/// - "Infrastructure completeness over simplicity" principle
/// - Complexity paid once, not on every app load
///
/// ### Object Store Keys
/// - All stores use `uuid` as primary key (strings)
/// - Integer `id` stored in JSON but not used as key
/// - UUIDs are better for sync and cross-device consistency
///
/// ## Schema Version History
/// - Version 1 (initial): notes, edges, entity_versions, _hnsw_index

/// Database name
const String kDatabaseName = 'everything_stack';

/// Current schema version
const int kDatabaseVersion = 1;

/// Object store names
class ObjectStores {
  static const String notes = 'notes';
  static const String mediaItems = 'mediaItems';
  static const String channels = 'channels';
  static const String edges = 'edges';
  static const String entityVersions = 'entity_versions';
  static const String hnswIndex = '_hnsw_index'; // Metadata store for HNSW
}

/// Index names for each object store
class Indexes {
  // Notes indexes
  static const String notesId = 'id'; // For efficient findById()
  static const String notesUuid = 'uuid';
  static const String notesSyncStatus = 'dbSyncStatus';
  static const String notesPinned = 'isPinned';
  static const String notesArchived = 'isArchived';

  // MediaItems indexes
  static const String mediaItemsId = 'id';
  static const String mediaItemsUuid = 'uuid';
  static const String mediaItemsSyncStatus = 'dbSyncStatus';
  static const String mediaItemsDownloadStatus = 'downloadStatus';
  static const String mediaItemsChannelId = 'channelId';

  // Channels indexes
  static const String channelsId = 'id';
  static const String channelsUuid = 'uuid';
  static const String channelsSyncStatus = 'dbSyncStatus';
  static const String channelsSubscribed = 'isSubscribed';

  // Edges indexes
  static const String edgesId = 'id';
  static const String edgesUuid = 'uuid';
  static const String edgesSyncStatus = 'dbSyncStatus';
  static const String edgesSourceUuid = 'sourceUuid';
  static const String edgesTargetUuid = 'targetUuid';
  static const String edgesEdgeType = 'edgeType';

  // EntityVersion indexes
  static const String versionsId = 'id';
  static const String versionsUuid = 'uuid';
  static const String versionsSyncStatus = 'dbSyncStatus';
  static const String versionsEntityUuid = 'entityUuid';
  static const String versionsEntityType = 'entityType';
}

/// Schema definition for notes object store
class NotesStoreSchema {
  /// Object store configuration
  static const String storeName = ObjectStores.notes;
  static const String keyPath = 'uuid'; // Primary key
  static const bool autoIncrement = false; // We provide UUIDs

  /// Index definitions
  /// Format: (indexName, keyPath, unique)
  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.notesId,
      keyPath: 'id',
      unique: true, // Integer IDs are unique within entity type
    ),
    IndexDefinition(
      name: Indexes.notesUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.notesSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.notesPinned,
      keyPath: 'isPinned',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.notesArchived,
      keyPath: 'isArchived',
      unique: false,
    ),
  ];

  /// HNSW semantic search
  /// - Embeddings stored in 'embedding' field (array of doubles)
  /// - No IndexedDB index on embeddings (not supported)
  /// - NoteIndexedDBAdapter builds in-memory HNSW index using local_hnsw
  /// - Index rebuilt on app load and incrementally updated
}

/// Schema definition for mediaItems object store
class MediaItemsStoreSchema {
  static const String storeName = ObjectStores.mediaItems;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.mediaItemsId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.mediaItemsUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.mediaItemsSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.mediaItemsDownloadStatus,
      keyPath: 'downloadStatus',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.mediaItemsChannelId,
      keyPath: 'channelId',
      unique: false,
    ),
  ];

  /// HNSW semantic search
  /// - Embeddings stored in 'embedding' field (array of doubles)
  /// - No IndexedDB index on embeddings (not supported)
  /// - MediaItemIndexedDBAdapter builds in-memory HNSW index using local_hnsw
  /// - Index rebuilt on app load and incrementally updated
}

/// Schema definition for channels object store
class ChannelsStoreSchema {
  static const String storeName = ObjectStores.channels;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.channelsId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.channelsUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.channelsSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.channelsSubscribed,
      keyPath: 'isSubscribed',
      unique: false,
    ),
  ];
}

/// Schema definition for edges object store
class EdgesStoreSchema {
  static const String storeName = ObjectStores.edges;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.edgesId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.edgesUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.edgesSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.edgesSourceUuid,
      keyPath: 'sourceUuid',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.edgesTargetUuid,
      keyPath: 'targetUuid',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.edgesEdgeType,
      keyPath: 'edgeType',
      unique: false,
    ),
  ];

  /// Composite key enforcement
  /// - ObjectBox: Composite unique constraint at DB level
  /// - IndexedDB: No native composite unique constraints
  /// - Solution: EdgeRepository checks uniqueness before insert
  ///   using compound query: sourceUuid + targetUuid + edgeType
}

/// Schema definition for entity_versions object store
class EntityVersionsStoreSchema {
  static const String storeName = ObjectStores.entityVersions;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.versionsId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.versionsUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.versionsSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.versionsEntityUuid,
      keyPath: 'entityUuid',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.versionsEntityType,
      keyPath: 'entityType',
      unique: false,
    ),
  ];
}

/// Schema definition for HNSW index metadata store
class HnswIndexStoreSchema {
  static const String storeName = ObjectStores.hnswIndex;
  static const String keyPath = 'key'; // String key: 'notes_index'
  static const bool autoIncrement = false;

  /// No indexes needed - this is a metadata store with single record
  static const List<IndexDefinition> indexes = [];

  /// Record structure:
  /// {
  ///   key: 'notes_index',
  ///   bytes: Uint8List,       // Serialized HNSW graph
  ///   version: int,            // For invalidation (increment on rebuild)
  ///   entityCount: int,        // For validation
  ///   lastUpdated: int,        // Timestamp (milliseconds since epoch)
  /// }
}

/// Index definition
class IndexDefinition {
  final String name;
  final String keyPath;
  final bool unique;

  const IndexDefinition({
    required this.name,
    required this.keyPath,
    required this.unique,
  });
}

/// Complete schema for all object stores
class DatabaseSchema {
  static const int version = kDatabaseVersion;
  static const String name = kDatabaseName;

  /// All object stores in the database
  static const List<ObjectStoreDefinition> objectStores = [
    ObjectStoreDefinition(
      name: NotesStoreSchema.storeName,
      keyPath: NotesStoreSchema.keyPath,
      autoIncrement: NotesStoreSchema.autoIncrement,
      indexes: NotesStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: MediaItemsStoreSchema.storeName,
      keyPath: MediaItemsStoreSchema.keyPath,
      autoIncrement: MediaItemsStoreSchema.autoIncrement,
      indexes: MediaItemsStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: ChannelsStoreSchema.storeName,
      keyPath: ChannelsStoreSchema.keyPath,
      autoIncrement: ChannelsStoreSchema.autoIncrement,
      indexes: ChannelsStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: EdgesStoreSchema.storeName,
      keyPath: EdgesStoreSchema.keyPath,
      autoIncrement: EdgesStoreSchema.autoIncrement,
      indexes: EdgesStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: EntityVersionsStoreSchema.storeName,
      keyPath: EntityVersionsStoreSchema.keyPath,
      autoIncrement: EntityVersionsStoreSchema.autoIncrement,
      indexes: EntityVersionsStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: HnswIndexStoreSchema.storeName,
      keyPath: HnswIndexStoreSchema.keyPath,
      autoIncrement: HnswIndexStoreSchema.autoIncrement,
      indexes: HnswIndexStoreSchema.indexes,
    ),
  ];
}

/// Object store definition
class ObjectStoreDefinition {
  final String name;
  final String keyPath;
  final bool autoIncrement;
  final List<IndexDefinition> indexes;

  const ObjectStoreDefinition({
    required this.name,
    required this.keyPath,
    required this.autoIncrement,
    required this.indexes,
  });
}
