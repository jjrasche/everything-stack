/// Standardized timeout values for all network operations.
///
/// Use these constants to ensure consistent timeout behavior across services.
/// Organized by operation type for clarity.
///
/// ## Usage
/// ```dart
/// await http.get(url).timeout(TimeoutConfig.httpDefault);
/// await embeddings.generate(text).timeout(TimeoutConfig.embeddingGeneration);
/// ```
///
/// ## Timeout Layers (Defense in Depth)
/// 1. HTTP client layer: [httpDefault], [httpUpload]
/// 2. Service layer: [embeddingGeneration], [llmStreaming], etc.
/// 3. Caller layer: User-facing deadlines (set by caller)
class TimeoutConfig {
  // ========================================================================
  // Network Operations (HTTP Client Layer)
  // ========================================================================

  /// Default timeout for HTTP requests (GET, POST, etc.)
  ///
  /// Prevents connection leaks and socket exhaustion.
  static const httpDefault = Duration(seconds: 30);

  /// Timeout for file uploads and large payloads
  static const httpUpload = Duration(minutes: 5);

  // ========================================================================
  // AI Service Operations
  // ========================================================================

  /// Embedding generation (text → vector)
  ///
  /// Jina AI, OpenAI embeddings, etc.
  static const embeddingGeneration = Duration(seconds: 45);

  /// LLM streaming response (per token/chunk)
  ///
  /// Idle timeout - if no token received within this duration, connection is dead.
  /// Total timeout is managed by caller.
  static const llmStreamingIdle = Duration(seconds: 10);

  /// LLM connection timeout (initial request)
  static const llmConnection = Duration(seconds: 15);

  /// Text-to-speech generation (text → audio)
  static const ttsGeneration = Duration(seconds: 20);

  /// Text-to-speech streaming idle timeout (per audio chunk)
  static const ttsStreamingIdle = Duration(seconds: 5);

  /// Speech-to-text processing (audio → text)
  static const sttConnection = Duration(seconds: 10);

  /// Speech-to-text streaming idle timeout (no transcript for N seconds)
  static const sttStreamingIdle = Duration(seconds: 30);

  // ========================================================================
  // Sync Operations
  // ========================================================================

  /// Single entity push to remote
  static const entityPush = Duration(seconds: 15);

  /// Large file/blob push to remote
  static const blobPush = Duration(minutes: 10);

  /// Pull all entities from remote
  static const pullAll = Duration(minutes: 5);

  // ========================================================================
  // Background Jobs
  // ========================================================================

  /// Embedding queue processing (per batch)
  static const embeddingQueue = Duration(seconds: 30);

  /// Full semantic index rebuild
  static const indexRebuild = Duration(hours: 1);

  /// Version queue processing (per batch)
  static const versionQueue = Duration(seconds: 15);
}
