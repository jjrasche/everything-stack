/// # BlobStore
///
/// ## What it does
/// Platform-agnostic interface for binary blob storage.
/// Abstracts filesystem (mobile/desktop) and IndexedDB (web).
///
/// ## What it enables
/// - Store file bytes without permission issues
/// - Efficient streaming for large files
/// - Cross-platform consistency
/// - Offline availability of attachments
///
/// ## Implementations
/// - MockBlobStore: In-memory storage for testing
/// - FileSystemBlobStore: Mobile/Desktop filesystem via path_provider
/// - IndexedDBBlobStore: Web IndexedDB
///
/// ## Usage
/// ```dart
/// // Setup platform-specific store
/// BlobStore.instance = FileSystemBlobStore(); // mobile/desktop
/// BlobStore.instance = IndexedDBBlobStore();   // web
/// await BlobStore.instance.initialize();
///
/// // Save blob
/// final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
/// await BlobStore.instance.save('file-uuid', bytes);
///
/// // Load blob
/// final loaded = await BlobStore.instance.load('file-uuid');
///
/// // Stream for large files
/// await BlobStore.instance.streamRead('file-uuid', chunkSize: 64*1024)
///   .forEach((chunk) => processChunk(chunk));
///
/// // Clean up
/// await BlobStore.instance.delete('file-uuid');
/// ```
///
/// ## Testing approach
/// Mock implementation works without platform setup.
/// Real implementations tested on actual platforms.

import 'dart:async';
import 'dart:typed_data';

// ============ Abstract Interface ============

/// Platform-agnostic binary blob storage.
abstract class BlobStore {
  /// Global singleton instance (defaults to mock for safe testing)
  static BlobStore instance = MockBlobStore();

  /// Save blob with unique identifier
  /// Overwrites if blob with same id already exists
  Future<void> save(String id, Uint8List bytes);

  /// Load blob by id
  /// Returns null if not found
  Future<Uint8List?> load(String id);

  /// Delete blob by id
  /// Returns true if deleted, false if not found
  Future<bool> delete(String id);

  /// Stream blob content in chunks
  /// Useful for large files to avoid loading fully into memory
  Stream<Uint8List> streamRead(String id, {int chunkSize = 64 * 1024});

  /// Check if blob exists
  bool contains(String id);

  /// Get blob size in bytes
  /// Returns -1 if not found
  int size(String id);

  /// Initialize storage (platform-specific setup)
  Future<void> initialize();

  /// Dispose and cleanup resources
  void dispose();
}

// ============ Mock Implementation ============

/// Mock blob store for testing without platform dependencies.
class MockBlobStore extends BlobStore {
  final Map<String, Uint8List> _blobs = {};

  @override
  Future<void> save(String id, Uint8List bytes) async {
    _blobs[id] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> load(String id) async {
    final blob = _blobs[id];
    if (blob == null) return null;
    return Uint8List.fromList(blob);
  }

  @override
  Future<bool> delete(String id) async {
    return _blobs.remove(id) != null;
  }

  @override
  Stream<Uint8List> streamRead(String id, {int chunkSize = 64 * 1024}) async* {
    final blob = _blobs[id];
    if (blob == null) return;

    for (int i = 0; i < blob.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, blob.length);
      yield blob.sublist(i, end);
    }
  }

  @override
  bool contains(String id) => _blobs.containsKey(id);

  @override
  int size(String id) {
    final blob = _blobs[id];
    return blob != null ? blob.length : -1;
  }

  @override
  Future<void> initialize() async {
    // No-op: mock is always ready
  }

  @override
  void dispose() {
    _blobs.clear();
  }
}

// ============ Platform Implementations ============

/// Filesystem-based blob store for mobile and desktop.
/// Uses path_provider to get platform-specific directories.
class FileSystemBlobStore extends BlobStore {
  // Implementation placeholder - will be implemented with conditional imports
  // Real implementation uses:
  // - getTemporaryDirectory() for temporary files
  // - getApplicationDocumentsDirectory() for persistent files
  // - File I/O for saving/loading

  @override
  Future<void> save(String id, Uint8List bytes) async {
    throw UnimplementedError('FileSystemBlobStore requires platform-specific implementation');
  }

  @override
  Future<Uint8List?> load(String id) async {
    throw UnimplementedError('FileSystemBlobStore requires platform-specific implementation');
  }

  @override
  Future<bool> delete(String id) async {
    throw UnimplementedError('FileSystemBlobStore requires platform-specific implementation');
  }

  @override
  Stream<Uint8List> streamRead(String id, {int chunkSize = 64 * 1024}) {
    throw UnimplementedError('FileSystemBlobStore requires platform-specific implementation');
  }

  @override
  bool contains(String id) {
    throw UnimplementedError('FileSystemBlobStore requires platform-specific implementation');
  }

  @override
  int size(String id) {
    throw UnimplementedError('FileSystemBlobStore requires platform-specific implementation');
  }

  @override
  Future<void> initialize() async {
    // Verify directories are writable
  }

  @override
  void dispose() {
    // Cleanup temporary files if needed
  }
}

/// IndexedDB-based blob store for web.
/// Uses browser's IndexedDB for persistent client-side storage.
class IndexedDBBlobStore extends BlobStore {
  // Implementation placeholder - will be implemented with js interop or package
  // Real implementation uses:
  // - indexed_db package or dart:indexed_db (if available)
  // - Database transactions for save/load/delete
  // - Object stores for blob data

  @override
  Future<void> save(String id, Uint8List bytes) async {
    throw UnimplementedError('IndexedDBBlobStore requires web-specific implementation');
  }

  @override
  Future<Uint8List?> load(String id) async {
    throw UnimplementedError('IndexedDBBlobStore requires web-specific implementation');
  }

  @override
  Future<bool> delete(String id) async {
    throw UnimplementedError('IndexedDBBlobStore requires web-specific implementation');
  }

  @override
  Stream<Uint8List> streamRead(String id, {int chunkSize = 64 * 1024}) {
    throw UnimplementedError('IndexedDBBlobStore requires web-specific implementation');
  }

  @override
  bool contains(String id) {
    throw UnimplementedError('IndexedDBBlobStore requires web-specific implementation');
  }

  @override
  int size(String id) {
    throw UnimplementedError('IndexedDBBlobStore requires web-specific implementation');
  }

  @override
  Future<void> initialize() async {
    // Open IndexedDB database
  }

  @override
  void dispose() {
    // Close IndexedDB connection
  }
}
