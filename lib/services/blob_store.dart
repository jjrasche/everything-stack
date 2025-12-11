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
import 'package:supabase_flutter/supabase_flutter.dart';

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
//
// Real implementations are in separate files for conditional imports:
// - blob_store_io.dart: FileSystemBlobStore for mobile/desktop
// - blob_store_web.dart: IndexedDBBlobStore for web
//
// Usage with conditional imports:
// ```dart
// import 'blob_store.dart';
// import 'blob_store_io.dart' if (dart.library.html) 'blob_store_web.dart';
//
// void main() {
//   BlobStore.instance = FileSystemBlobStore(); // or IndexedDBBlobStore on web
// }
// ```

// ============ Supabase Storage Implementation ============

/// Supabase Storage-based blob store for cloud sync.
/// Stores blobs in Supabase Storage bucket, metadata in blob_metadata table.
class SupabaseBlobStore extends BlobStore {
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String bucketName;

  SupabaseClient? _client;
  bool _isReady = false;

  /// Local cache for contains/size checks
  final Map<String, int> _metadataCache = {};

  SupabaseBlobStore({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.bucketName = 'blobs',
  });

  @override
  Future<void> initialize() async {
    if (_isReady) return;

    _client = SupabaseClient(supabaseUrl, supabaseAnonKey);
    _isReady = true;
  }

  @override
  Future<void> save(String id, Uint8List bytes) async {
    // Local save delegates to uploadRemote for this implementation
    await uploadRemote(id, bytes);
  }

  @override
  Future<Uint8List?> load(String id) async {
    // Local load delegates to downloadRemote for this implementation
    return await downloadRemote(id);
  }

  @override
  Future<bool> delete(String id) async {
    return await deleteRemote(id);
  }

  @override
  Stream<Uint8List> streamRead(String id, {int chunkSize = 64 * 1024}) async* {
    // For Supabase, we download the whole file then stream chunks
    final bytes = await downloadRemote(id);
    if (bytes == null) return;

    for (int i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, bytes.length);
      yield bytes.sublist(i, end);
    }
  }

  @override
  bool contains(String id) {
    return _metadataCache.containsKey(id);
  }

  @override
  int size(String id) {
    return _metadataCache[id] ?? -1;
  }

  @override
  void dispose() {
    _client?.dispose();
    _client = null;
    _isReady = false;
    _metadataCache.clear();
  }

  // ============ Remote operations for sync ============

  /// Upload blob to Supabase Storage.
  /// Returns true if upload succeeded.
  Future<bool> uploadRemote(String id, Uint8List bytes) async {
    if (!_isReady) await initialize();

    try {
      final storagePath = 'blobs/$id';

      // Upload to storage
      await _client!.storage.from(bucketName).uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      // Save metadata
      await _client!.from('blob_metadata').upsert({
        'uuid': id,
        'storage_path': storagePath,
        'size_bytes': bytes.length,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Update local cache
      _metadataCache[id] = bytes.length;

      return true;
    } catch (e) {
      print('SupabaseBlobStore.uploadRemote error: $e');
      return false;
    }
  }

  /// Download blob from Supabase Storage.
  /// Returns null if not found.
  Future<Uint8List?> downloadRemote(String id) async {
    if (!_isReady) await initialize();

    try {
      final storagePath = 'blobs/$id';

      final bytes =
          await _client!.storage.from(bucketName).download(storagePath);

      // Update cache
      _metadataCache[id] = bytes.length;

      return bytes;
    } catch (e) {
      return null;
    }
  }

  /// Check if blob exists in Supabase Storage.
  Future<bool> existsRemote(String id) async {
    if (!_isReady) await initialize();

    try {
      final result = await _client!
          .from('blob_metadata')
          .select('uuid')
          .eq('uuid', id)
          .maybeSingle();

      return result != null;
    } catch (e) {
      return false;
    }
  }

  /// Delete blob from Supabase Storage and metadata table.
  /// Returns true if deleted, false if not found or error.
  Future<bool> deleteRemote(String id) async {
    if (!_isReady) await initialize();

    try {
      final storagePath = 'blobs/$id';

      // Delete from storage
      await _client!.storage.from(bucketName).remove([storagePath]);

      // Delete metadata
      await _client!.from('blob_metadata').delete().eq('uuid', id);

      // Update cache
      _metadataCache.remove(id);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get metadata for a blob from Supabase.
  Future<Map<String, dynamic>?> getMetadata(String id) async {
    if (!_isReady) await initialize();

    try {
      final result = await _client!
          .from('blob_metadata')
          .select()
          .eq('uuid', id)
          .maybeSingle();

      if (result != null) {
        _metadataCache[id] = result['size_bytes'] as int? ?? 0;
      }

      return result;
    } catch (e) {
      return null;
    }
  }
}
