/// # FileSystemBlobStore
///
/// Platform-specific implementation for mobile and desktop.
/// Uses dart:io File operations and path_provider for directories.
///
/// Stores blobs in app documents directory:
/// - iOS: Documents/
/// - Android: getFilesDir()/
/// - Desktop: home/.appname/

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'blob_store.dart';

/// Filesystem-based blob store for mobile and desktop platforms.
class FileSystemBlobStore extends BlobStore {
  late Directory _blobDirectory;

  /// Get the blob file for an id
  Future<File> _getBlobFile(String id) async {
    return File('${_blobDirectory.path}/$id.blob');
  }

  @override
  Future<void> initialize() async {
    try {
      // Use application documents directory
      final appDir = await getApplicationDocumentsDirectory();
      _blobDirectory = Directory('${appDir.path}/blobs');

      // Create directory if it doesn't exist
      if (!await _blobDirectory.exists()) {
        await _blobDirectory.create(recursive: true);
      }
    } catch (e) {
      throw Exception('Failed to initialize FileSystemBlobStore: $e');
    }
  }

  @override
  Future<void> save(String id, Uint8List bytes) async {
    try {
      final file = await _getBlobFile(id);
      await file.writeAsBytes(bytes);
    } catch (e) {
      throw Exception('Failed to save blob $id: $e');
    }
  }

  @override
  Future<Uint8List?> load(String id) async {
    try {
      final file = await _getBlobFile(id);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (e) {
      throw Exception('Failed to load blob $id: $e');
    }
  }

  @override
  Future<bool> delete(String id) async {
    try {
      final file = await _getBlobFile(id);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      throw Exception('Failed to delete blob $id: $e');
    }
  }

  @override
  Stream<Uint8List> streamRead(String id, {int chunkSize = 64 * 1024}) async* {
    try {
      final file = await _getBlobFile(id);
      if (!await file.exists()) {
        return;
      }

      // Open file for streaming
      final raf = await file.open();

      try {
        while (true) {
          final chunk = await raf.read(chunkSize);
          if (chunk.isEmpty) break;

          yield Uint8List.fromList(chunk);
        }
      } finally {
        await raf.close();
      }
    } catch (e) {
      throw Exception('Failed to stream blob $id: $e');
    }
  }

  @override
  bool contains(String id) {
    try {
      final filePath = '${_blobDirectory.path}/$id.blob';
      final file = File(filePath);
      return file.existsSync();
    } catch (e) {
      return false;
    }
  }

  @override
  int size(String id) {
    try {
      final filePath = '${_blobDirectory.path}/$id.blob';
      final file = File(filePath);
      if (file.existsSync()) {
        return file.lengthSync();
      }
      return -1;
    } catch (e) {
      return -1;
    }
  }

  @override
  void dispose() {
    // File handles are closed automatically
    // No cleanup needed for FileSystemBlobStore
  }
}
