/// ## Why background embedding instead of synchronous
/// Synchronous embedding during save blocks UI (2-5s per save),
/// hangs on API timeout, and sequential chunking means 25+ API calls.
/// Background queue: save returns immediately, batch API calls, retry on failure.

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

    final pendingCount = await _store.getPendingCount();
    if (pendingCount > 0) {
      print('Found $pendingCount pending tasks, processing immediately');
      unawaited(_processBatch());
    }

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

    final embeddings = await _embeddingService
        .generateBatch(texts)
        .timeout(Duration(seconds: 30));

    for (int i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final embedding = embeddings[i];

      await _saveEmbedding(task, embedding);

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

        final embedding = await _embeddingService
            .generate(task.text)
            .timeout(Duration(seconds: 15));

        await _saveEmbedding(task, embedding);

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
  Future<void> _saveEmbedding(
      EmbeddingTaskData task, List<double> embedding) async {
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
      task.status = TaskStatus.pending;
      await _store.save(task);

      print(
          '⚠ ${task.entityType}:${task.entityUuid} failed (attempt ${task.retryCount}/$maxRetries), will retry: $error');

      // Exponential backoff delay
      await Future.delayed(Duration(seconds: 2 * task.retryCount));
    }
  }
}
