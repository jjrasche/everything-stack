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
const int kDatabaseVersion = 2;

/// Object store names
class ObjectStores {
  static const String notes = 'notes';
  static const String edges = 'edges';
  static const String entityVersions = 'entity_versions';
  static const String hnswIndex = '_hnsw_index'; // Metadata store for HNSW
  static const String adaptation_state = 'adaptation_state';
  static const String feedback = 'feedback';
  static const String events = 'events';
  static const String invocations = 'invocations';
  static const String embeddingTasks = 'embedding_tasks';
  static const String enrichmentQueue = 'enrichment_queue';
  static const String trials = 'trials';
  static const String persons = 'persons';
  static const String regulationEntries = 'regulation_entries';
  static const String commitments = 'commitments';
  static const String commitmentLogs = 'commitment_logs';
  static const String audioFiles = 'audio_files';
  static const String atomicInsights = 'atomic_insights';
  static const String chunks = 'chunks';
  static const String promptVersions = 'prompt_versions';
}

/// Index names for each object store
class Indexes {
  // Notes indexes
  static const String notesId = 'id'; // For efficient findById()
  static const String notesUuid = 'uuid';
  static const String notesSyncStatus = 'dbSyncStatus';
  static const String notesPinned = 'isPinned';
  static const String notesArchived = 'isArchived';

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

  // AdaptationState indexes
  static const String adaptationStateId = 'id';
  static const String adaptationStateUuid = 'uuid';
  static const String adaptationStateSyncStatus = 'dbSyncStatus';

  // Feedback indexes
  static const String feedbackId = 'id';
  static const String feedbackUuid = 'uuid';
  static const String feedbackSyncStatus = 'dbSyncStatus';

  // Events indexes
  static const String eventsId = 'id';
  static const String eventsUuid = 'uuid';
  static const String eventsCorrelationId = 'correlationId';
  static const String eventsEventType = 'eventType';

  // Invocations indexes
  static const String invocationsId = 'id';
  static const String invocationsUuid = 'uuid';
  static const String invocationsSyncStatus = 'dbSyncStatus';
  static const String invocationsCorrelationId = 'correlationId';

  // EmbeddingTasks indexes
  static const String embeddingTasksId = 'id';
  static const String embeddingTasksEntityUuid = 'entityUuid';
  static const String embeddingTasksStatus = 'status';

  // EnrichmentQueue indexes
  static const String enrichmentQueueId = 'id';
  static const String enrichmentQueueUuid = 'uuid';
  static const String enrichmentQueueEntityUuid = 'entityUuid';
  static const String enrichmentQueueCurrentStep = 'currentStep';

  // Trials indexes
  static const String trialsId = 'id';
  static const String trialsUuid = 'uuid';
  static const String trialsSyncStatus = 'dbSyncStatus';
  static const String trialsComponentType = 'componentType';

  // Person indexes
  static const String personsId = 'id';
  static const String personsUuid = 'uuid';
  static const String personsSyncStatus = 'dbSyncStatus';

  // RegulationEntry indexes
  static const String regulationEntriesId = 'id';
  static const String regulationEntriesUuid = 'uuid';
  static const String regulationEntriesSyncStatus = 'dbSyncStatus';

  // Commitment indexes
  static const String commitmentsId = 'id';
  static const String commitmentsUuid = 'uuid';
  static const String commitmentsSyncStatus = 'dbSyncStatus';

  // CommitmentLog indexes
  static const String commitmentLogsId = 'id';
  static const String commitmentLogsUuid = 'uuid';
  static const String commitmentLogsSyncStatus = 'dbSyncStatus';

  // AudioFile indexes
  static const String audioFilesId = 'id';
  static const String audioFilesUuid = 'uuid';
  static const String audioFilesSyncStatus = 'dbSyncStatus';
  static const String audioFilesEventId = 'eventId';

  // AtomicInsight indexes
  static const String atomicInsightsId = 'id';
  static const String atomicInsightsUuid = 'uuid';
  static const String atomicInsightsSyncStatus = 'dbSyncStatus';
  static const String atomicInsightsScope = 'scope';
  static const String atomicInsightsProjectId = 'projectId';
  static const String atomicInsightsIsArchived = 'isArchived';

  // Chunk indexes
  static const String chunksId = 'id';
  static const String chunksChunkId = 'chunkId';
  static const String chunksSourceEntityId = 'sourceEntityId';

  // PromptVersion indexes
  static const String promptVersionsId = 'id';
  static const String promptVersionsUuid = 'uuid';
  static const String promptVersionsSyncStatus = 'dbSyncStatus';
  static const String promptVersionsComponentType = 'componentType';
  static const String promptVersionsVersion = 'version';
  static const String promptVersionsIsActive = 'isActive';
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

/// Schema definition for adaptationState object store
class AdaptationStateStoreSchema {
  static const String storeName = ObjectStores.adaptation_state;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.adaptationStateId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.adaptationStateUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.adaptationStateSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
  ];
}

/// Schema definition for feedback object store
class FeedbackStoreSchema {
  static const String storeName = ObjectStores.feedback;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.feedbackId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.feedbackUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.feedbackSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
  ];
}

/// Schema definition for events object store
class EventsStoreSchema {
  static const String storeName = ObjectStores.events;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.eventsId,
      keyPath: 'id',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.eventsUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.eventsCorrelationId,
      keyPath: 'correlationId',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.eventsEventType,
      keyPath: 'eventType',
      unique: false,
    ),
  ];
}

/// Schema definition for invocations object store
class InvocationsStoreSchema {
  static const String storeName = ObjectStores.invocations;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.invocationsId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.invocationsUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.invocationsSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.invocationsCorrelationId,
      keyPath: 'correlationId',
      unique: false,
    ),
  ];
}

/// Schema definition for embedding_tasks object store
class EmbeddingTasksStoreSchema {
  static const String storeName = ObjectStores.embeddingTasks;
  static const String keyPath = 'id'; // Integer auto-increment key
  static const bool autoIncrement = true;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.embeddingTasksId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.embeddingTasksEntityUuid,
      keyPath: 'entityUuid',
      unique: false, // Same entity can be re-enqueued after completion
    ),
    IndexDefinition(
      name: Indexes.embeddingTasksStatus,
      keyPath: 'status',
      unique: false,
    ),
  ];
}

/// Schema definition for enrichment_queue object store
class EnrichmentQueueStoreSchema {
  static const String storeName = ObjectStores.enrichmentQueue;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.enrichmentQueueId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.enrichmentQueueUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.enrichmentQueueEntityUuid,
      keyPath: 'entityUuid',
      unique: false, // Entity can be re-enqueued after completion
    ),
    IndexDefinition(
      name: Indexes.enrichmentQueueCurrentStep,
      keyPath: 'currentStep',
      unique: false, // Multiple items can have same step (or null)
    ),
  ];
}

/// Schema definition for trials object store
class TrialsStoreSchema {
  static const String storeName = ObjectStores.trials;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.trialsId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.trialsUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.trialsSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.trialsComponentType,
      keyPath: 'componentType',
      unique: false,
    ),
  ];
}

/// Schema definition for persons object store
class PersonsStoreSchema {
  static const String storeName = ObjectStores.persons;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.personsId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.personsUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.personsSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
  ];
}

/// Schema definition for regulation_entries object store
class RegulationEntriesStoreSchema {
  static const String storeName = ObjectStores.regulationEntries;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.regulationEntriesId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.regulationEntriesUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.regulationEntriesSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
  ];
}

/// Schema definition for commitments object store
class CommitmentsStoreSchema {
  static const String storeName = ObjectStores.commitments;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.commitmentsId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.commitmentsUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.commitmentsSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
  ];
}

/// Schema definition for commitment_logs object store
class CommitmentLogsStoreSchema {
  static const String storeName = ObjectStores.commitmentLogs;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.commitmentLogsId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.commitmentLogsUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.commitmentLogsSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
  ];
}

/// Schema definition for audio_files object store
class AudioFilesStoreSchema {
  static const String storeName = ObjectStores.audioFiles;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.audioFilesId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.audioFilesUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.audioFilesSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.audioFilesEventId,
      keyPath: 'eventId',
      unique: false, // Multiple audio files can belong to same event
    ),
  ];
}

/// Schema definition for prompt_versions object store
class PromptVersionsStoreSchema {
  static const String storeName = ObjectStores.promptVersions;
  static const String keyPath = 'uuid';
  static const bool autoIncrement = false;

  static const List<IndexDefinition> indexes = [
    IndexDefinition(
      name: Indexes.promptVersionsId,
      keyPath: 'id',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.promptVersionsUuid,
      keyPath: 'uuid',
      unique: true,
    ),
    IndexDefinition(
      name: Indexes.promptVersionsSyncStatus,
      keyPath: 'dbSyncStatus',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.promptVersionsComponentType,
      keyPath: 'componentType',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.promptVersionsVersion,
      keyPath: 'version',
      unique: false,
    ),
    IndexDefinition(
      name: Indexes.promptVersionsIsActive,
      keyPath: 'isActive',
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
    ObjectStoreDefinition(
      name: AdaptationStateStoreSchema.storeName,
      keyPath: AdaptationStateStoreSchema.keyPath,
      autoIncrement: AdaptationStateStoreSchema.autoIncrement,
      indexes: AdaptationStateStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: FeedbackStoreSchema.storeName,
      keyPath: FeedbackStoreSchema.keyPath,
      autoIncrement: FeedbackStoreSchema.autoIncrement,
      indexes: FeedbackStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: EventsStoreSchema.storeName,
      keyPath: EventsStoreSchema.keyPath,
      autoIncrement: EventsStoreSchema.autoIncrement,
      indexes: EventsStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: InvocationsStoreSchema.storeName,
      keyPath: InvocationsStoreSchema.keyPath,
      autoIncrement: InvocationsStoreSchema.autoIncrement,
      indexes: InvocationsStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: EmbeddingTasksStoreSchema.storeName,
      keyPath: EmbeddingTasksStoreSchema.keyPath,
      autoIncrement: EmbeddingTasksStoreSchema.autoIncrement,
      indexes: EmbeddingTasksStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: EnrichmentQueueStoreSchema.storeName,
      keyPath: EnrichmentQueueStoreSchema.keyPath,
      autoIncrement: EnrichmentQueueStoreSchema.autoIncrement,
      indexes: EnrichmentQueueStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: TrialsStoreSchema.storeName,
      keyPath: TrialsStoreSchema.keyPath,
      autoIncrement: TrialsStoreSchema.autoIncrement,
      indexes: TrialsStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: PersonsStoreSchema.storeName,
      keyPath: PersonsStoreSchema.keyPath,
      autoIncrement: PersonsStoreSchema.autoIncrement,
      indexes: PersonsStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: RegulationEntriesStoreSchema.storeName,
      keyPath: RegulationEntriesStoreSchema.keyPath,
      autoIncrement: RegulationEntriesStoreSchema.autoIncrement,
      indexes: RegulationEntriesStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: CommitmentsStoreSchema.storeName,
      keyPath: CommitmentsStoreSchema.keyPath,
      autoIncrement: CommitmentsStoreSchema.autoIncrement,
      indexes: CommitmentsStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: CommitmentLogsStoreSchema.storeName,
      keyPath: CommitmentLogsStoreSchema.keyPath,
      autoIncrement: CommitmentLogsStoreSchema.autoIncrement,
      indexes: CommitmentLogsStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: AudioFilesStoreSchema.storeName,
      keyPath: AudioFilesStoreSchema.keyPath,
      autoIncrement: AudioFilesStoreSchema.autoIncrement,
      indexes: AudioFilesStoreSchema.indexes,
    ),
    ObjectStoreDefinition(
      name: PromptVersionsStoreSchema.storeName,
      keyPath: PromptVersionsStoreSchema.keyPath,
      autoIncrement: PromptVersionsStoreSchema.autoIncrement,
      indexes: PromptVersionsStoreSchema.indexes,
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
