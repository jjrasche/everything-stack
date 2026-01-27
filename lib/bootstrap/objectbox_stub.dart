/// Stub for ObjectBox types on Web platform.
///
/// Provides dummy types so code can compile on Web even though
/// ObjectBox (which uses dart:ffi) is not available.
///
/// ChunkingService is disabled on Web - semantic search not available.
library;

/// Stub Store type for Web (ObjectBox not available on Web).
class Store {
  /// Stub method - throws on Web.
  Box<T> box<T>() {
    throw UnsupportedError(
      'ObjectBox Store not available on Web platform. '
      'Semantic search (ChunkingService) is disabled on Web.',
    );
  }
}

/// Stub Box type for Web (ObjectBox not available on Web).
class Box<T> {}
