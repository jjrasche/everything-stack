/// # EmbeddingQueueService
///
/// Background service for processing embedding generation asynchronously.
/// Prevents blocking entity saves on API calls.
///
/// ## Why background
/// Synchronous embedding during save:
/// - Blocks UI (user waits 2-5 seconds per save)
/// - Hangs on API timeout (no recovery)
/// - Sequential chunking = 25+ API calls = 50+ seconds
///
/// Background embedding:
/// - Save returns immediately
/// - Batch API calls (efficient)
/// - Retry on failure (resilient)
/// - Persistent queue (survives crashes)
///
/// ## Lifecycle
/// 1. start() - Called on app init, starts timer
/// 2. Process batch every 2s OR when queue reaches 10 items
/// 3. flush() - Process all pending (on app shutdown, in tests)
/// 4. stop() - Cancel timer, optionally flush pending
///
/// ## Error handling
/// - Batch fails → Split into individual calls
/// - Individual call fails → Retry up to 3 times with backoff
/// - After 3 retries → Mark as failed, log, remove from queue
/// - Entity deleted → Mark as completed, skip
///
/// ## Implementation notes
/// - Persistent queue (EmbeddingTaskData stored via platform-specific adapter)
/// - Uses adapter.save(touch: false) to avoid updatedAt collision
/// - Direct adapter access bypasses repository handlers (intentional)

import 'dart:async';
import 'embedding_service.dart';
import 'embedding_task_store.dart';

class EmbeddingQueueService {
  final EmbeddingTaskStore _store;
  final EmbeddingService _embeddingService;

  Timer? _processingTimer;
  bool _isProcessing = false;

  // Configuration
  final int batchSize;
  final int processingIntervalSeconds;
  final int maxRetries;

  // Statistics
  int _completedCount = 0;
  int _failedCount = 0;
  DateTime? _lastProcessedAt;

  EmbeddingQueueService({
    required EmbeddingTaskStore store,
    required EmbeddingService embeddingService,
    this.batchSize = 10,
    this.processingIntervalSeconds = 2,
    this.maxRetries = 3,
  })  : _store = store,
        _embeddingService = embeddingService;

  /// Start background processing.
  /// Called on app init.
  Future<void> start() async {
    if (_processingTimer != null) {
      print('EmbeddingQueueService already started');
      return;
    }

    print('EmbeddingQueueService starting...');

    // Process immediately if queue has pending items
    final pendingCount = await _store.getPendingCount();
    if (pendingCount > 0) {
      print('Found $pendingCount pending tasks, processing immediately');
      unawaited(_processBatch());
    }

    // Start periodic timer
    _processingTimer = Timer.periodic(
      Duration(seconds: processingIntervalSeconds),
      (_) => _processBatch(),
    );

    print(
        'EmbeddingQueueService started (batch=$batchSize, interval=${processingIntervalSeconds}s)');
  }

  /// Stop background processing.
  /// If flushPending=true, processes all pending work before stopping.
  Future<void> stop({bool flushPending = true}) async {
    print('EmbeddingQueueService stopping (flush=$flushPending)...');

    _processingTimer?.cancel();
    _processingTimer = null;

    if (flushPending) {
      await flush();
    }

    print('EmbeddingQueueService stopped');
  }

  /// Process all pending tasks immediately.
  /// Used on app shutdown and in tests.
  Future<void> flush() async {
    print('EmbeddingQueueService flushing all pending tasks...');

    int iterations = 0;
    while (await _store.getPendingCount() > 0) {
      await _processBatch();

      iterations++;
      if (iterations > 100) {
        throw StateError(
            'Flush deadlock detected after $iterations iterations');
      }
    }

    print('EmbeddingQueueService flush complete');
  }

  /// Enqueue an entity for embedding generation.
  /// Returns immediately, embedding happens in background.
  Future<void> enqueue({
    required String entityUuid,
    required String entityType,
    required String text,
  }) async {
    if (text.trim().isEmpty) {
      print('Skipping empty text for $entityType:$entityUuid');
      return;
    }

    // Check if already queued
    final existing = await _store.findByEntityUuid(entityUuid);
    if (existing != null && !existing.isCompleted && !existing.isFailed) {
      print('$entityType:$entityUuid already queued, skipping');
      return;
    }

    final task = EmbeddingTaskData(
      entityUuid: entityUuid,
      entityType: entityType,
      text: text,
    );

    await _store.save(task);
    print(
        'Enqueued $entityType:$entityUuid (queue size: ${await _store.getPendingCount()})');

    // If queue reached batch size, process immediately
    if (await _store.getPendingCount() >= batchSize) {
      print('Queue reached batch size ($batchSize), processing immediately');
      unawaited(_processBatch());
    }
  }

  /// Get current queue statistics.
  Future<Map<String, dynamic>> getStats() async {
    return {
      'pending': await _store.getPendingCount(),
      'completed': _completedCount,
      'failed': _failedCount,
      'isProcessing': _isProcessing,
      'lastProcessedAt': _lastProcessedAt?.toIso8601String(),
    };
  }

  /// Process a batch of pending tasks.
  Future<void> _processBatch() async {
    if (_isProcessing) {
      return; // Already processing, skip this cycle
    }

    _isProcessing = true;
    _lastProcessedAt = DateTime.now();

    try {
      // Get next batch of pending tasks
      final tasks = await _store.getPendingTasks(batchSize);

      if (tasks.isEmpty) {
        return; // Nothing to process
      }

      print('Processing batch of ${tasks.length} tasks...');

      // Try batch embedding first (efficient)
      try {
        await _processBatchEmbeddings(tasks);
      } catch (e) {
        print('Batch embedding failed: $e');
        // Fall back to individual processing
        await _processIndividually(tasks);
      }

      print('Batch processing complete');
    } finally {
      _isProcessing = false;
    }
  }

  /// Process tasks as a batch (one API call).
  Future<void> _processBatchEmbeddings(List<EmbeddingTaskData> tasks) async {
    final texts = tasks.map((t) => t.text).toList();

    // Generate embeddings in batch
    final embeddings = await _embeddingService
        .generateBatch(texts)
        .timeout(Duration(seconds: 30));

    // Save embeddings to entities and mark tasks as completed
    for (int i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final embedding = embeddings[i];

      await _saveEmbedding(task, embedding);

      // Mark as completed
      task.status = TaskStatus.completed;
      await _store.save(task);
      _completedCount++;

      print('✓ ${task.entityType}:${task.entityUuid} embedded successfully');
    }
  }

  /// Process tasks individually (fallback on batch failure).
  Future<void> _processIndividually(List<EmbeddingTaskData> tasks) async {
    for (final task in tasks) {
      try {
        task.status = TaskStatus.processing;
        task.lastAttemptAt = DateTime.now();
        await _store.save(task);

        // Generate embedding
        final embedding = await _embeddingService
            .generate(task.text)
            .timeout(Duration(seconds: 15));

        // Save to entity
        await _saveEmbedding(task, embedding);

        // Mark as completed
        task.status = TaskStatus.completed;
        await _store.save(task);
        _completedCount++;

        print('✓ ${task.entityType}:${task.entityUuid} embedded successfully');
      } catch (e) {
        await _handleTaskFailure(task, e);
      }
    }
  }

  /// Save embedding to entity.
  /// Uses adapter directly (bypasses repository) with touch=false.
  /// TODO: Phase 1 - Re-enable when Note entity is implemented
  Future<void> _saveEmbedding(
      EmbeddingTaskData task, List<double> embedding) async {
    // Fetch latest entity state
    // final note = await _noteAdapter.findByUuid(task.entityUuid);
    //
    // if (note == null) {
    //   // Entity was deleted - not a failure, just skip
    //   task.status = TaskStatus.completed;
    //   await _store.save(task);
    //   print('Entity ${task.entityUuid} was deleted, skipping embedding');
    //   return;
    // }
    //
    // // Apply embedding
    // note.embedding = embedding;
    //
    // // Save with touch=false to preserve updatedAt timestamp
    // // This is a background side-effect, not a user edit
    // await _noteAdapter.save(note, touch: false);
    //
    // print('Saved embedding for ${task.entityType}:${task.entityUuid}');

    // For now, just mark as completed
    task.status = TaskStatus.completed;
    await _store.save(task);
  }

  /// Handle task failure with retry logic.
  Future<void> _handleTaskFailure(EmbeddingTaskData task, Object error) async {
    task.retryCount++;
    task.lastError = error.toString();

    if (task.retryCount >= maxRetries) {
      // Give up after max retries
      task.status = TaskStatus.failed;
      await _store.save(task);
      _failedCount++;

      print(
          '✗ ${task.entityType}:${task.entityUuid} failed after $maxRetries retries: $error');
    } else {
      // Retry on next cycle
      task.status = TaskStatus.pending;
      await _store.save(task);

      print(
          '⚠ ${task.entityType}:${task.entityUuid} failed (attempt ${task.retryCount}/$maxRetries), will retry: $error');

      // Exponential backoff delay
      await Future.delayed(Duration(seconds: 2 * task.retryCount));
    }
  }
}
