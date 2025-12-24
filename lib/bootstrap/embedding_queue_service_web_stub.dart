/// Web stub for EmbeddingQueueService
///
/// EmbeddingQueueService uses ObjectBox (native-only database).
/// On web, we provide a stub that does nothing.
library;

/// Stub EmbeddingQueueService for web platform (does nothing)
class EmbeddingQueueService {
  EmbeddingQueueService({
    required Object store,
    required Object embeddingService,
    required Object noteAdapter,
    int batchSize = 10,
    int processingIntervalSeconds = 2,
    int maxRetries = 3,
  });

  Future<void> start() async {}
  Future<void> stop({bool flushPending = false}) async {}
  Future<void> flush() async {}
}
