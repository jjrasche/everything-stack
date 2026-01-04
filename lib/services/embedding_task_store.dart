/// # EmbeddingTaskStore
///
/// Abstract interface for persistent embedding task queue storage.
/// Platform-specific implementations: ObjectBox (native), IndexedDB (web).
library;

/// Status of an embedding task in the queue.
enum TaskStatus {
  pending, // Waiting to be processed
  processing, // Currently being processed
  completed, // Successfully completed
  failed, // Failed after max retries
}

/// Embedding task entity (pure Dart, no ORM decorators)
class EmbeddingTaskData {
  /// Auto-generated ID (managed by store)
  int id;

  /// UUID of the entity this embedding is for (Note, Message, etc.)
  final String entityUuid;

  /// Type of entity (for debugging/monitoring)
  final String entityType;

  /// Text to embed
  final String text;

  /// Current status
  TaskStatus status;

  /// Number of times we've tried to process this task
  int retryCount;

  /// When this task was added to the queue
  final DateTime enqueuedAt;

  /// When this task was last attempted (null if never attempted)
  DateTime? lastAttemptAt;

  /// Error message from last failure (null if no error)
  String? lastError;

  EmbeddingTaskData({
    this.id = 0,
    required this.entityUuid,
    required this.entityType,
    required this.text,
    this.status = TaskStatus.pending,
    this.retryCount = 0,
    DateTime? enqueuedAt,
    this.lastAttemptAt,
    this.lastError,
  }) : enqueuedAt = enqueuedAt ?? DateTime.now();

  /// Whether this task should be processed
  bool get isPending => status == TaskStatus.pending;

  /// Whether this task is currently being processed
  bool get isProcessing => status == TaskStatus.processing;

  /// Whether this task completed successfully
  bool get isCompleted => status == TaskStatus.completed;

  /// Whether this task failed permanently
  bool get isFailed => status == TaskStatus.failed;

  /// Whether we should retry (not completed, not failed, under max retries)
  bool get shouldRetry => !isCompleted && !isFailed && retryCount < 3;
}

/// Abstract store for embedding tasks.
/// Implementations handle platform-specific persistence.
abstract class EmbeddingTaskStore {
  /// Find a task by entity UUID
  Future<EmbeddingTaskData?> findByEntityUuid(String entityUuid);

  /// Get count of pending tasks
  Future<int> getPendingCount();

  /// Get a batch of pending tasks
  Future<List<EmbeddingTaskData>> getPendingTasks(int limit);

  /// Save a task (insert or update)
  Future<void> save(EmbeddingTaskData task);

  /// Delete a task
  Future<void> delete(EmbeddingTaskData task);
}
