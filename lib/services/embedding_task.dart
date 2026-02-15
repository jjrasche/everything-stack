/// Persistent embedding task queue entry (native only, ObjectBox).
/// Why persistent: in-memory queue loses data on crash.
import 'package:objectbox/objectbox.dart';
import 'embedding_task_store.dart' show TaskStatus;

@Entity()
class EmbeddingTask {
  /// ObjectBox auto-generated ID
  @Id()
  int id = 0;

  /// UUID of the entity this embedding is for (Note, Message, etc.)
  @Index()
  String entityUuid;

  /// Type of entity (for debugging/monitoring)
  String entityType;

  /// Text to embed
  String text;

  /// Current status
  @Property(type: PropertyType.byte)
  int dbTaskStatus; // Maps to TaskStatus enum

  /// Number of times we've tried to process this task
  int retryCount;

  /// When this task was added to the queue
  @Property(type: PropertyType.date)
  DateTime enqueuedAt;

  /// When this task was last attempted (null if never attempted)
  @Property(type: PropertyType.date)
  DateTime? lastAttemptAt;

  /// Error message from last failure (null if no error)
  String? lastError;

  EmbeddingTask({
    required this.entityUuid,
    required this.entityType,
    required this.text,
    TaskStatus status = TaskStatus.pending,
    this.retryCount = 0,
    DateTime? enqueuedAt,
    this.lastAttemptAt,
    this.lastError,
  })  : dbTaskStatus = status.index,
        enqueuedAt = enqueuedAt ?? DateTime.now();

  /// Get status as enum
  TaskStatus get status => TaskStatus.values[dbTaskStatus];

  /// Set status as enum
  set status(TaskStatus value) {
    dbTaskStatus = value.index;
  }

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
