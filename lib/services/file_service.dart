/// # FileService
///
/// ## What it does
/// Platform-agnostic file input, processing, and storage.
/// Wraps platform-specific packages (image_picker, record, file_picker, image)
/// with unified API across web, mobile, desktop.
///
/// ## Key Design
/// FileService takes a BlobStore dependency and handles the complete workflow:
/// pick/record → process → store bytes → return metadata with valid UUID.
/// Callers get metadata with UUID already pointing to stored blob.
///
/// ## What it enables
/// - Pick photos from camera or gallery (auto-stored)
/// - Record audio with start/stop control (auto-stored)
/// - Pick any file type from device storage (auto-stored)
/// - Compress images (with quality control)
/// - Generate thumbnails with base64 encoding
/// - Automatic MIME type detection
///
/// ## Implementations
/// - MockFileService: Safe defaults for testing (stores mock bytes)
/// - RealFileService: Wraps actual platform packages
///
/// ## Usage
/// ```dart
/// // Setup with BlobStore dependency
/// final blobStore = MockBlobStore(); // or FileSystemBlobStore, IndexedDBBlobStore
/// await blobStore.initialize();
///
/// final fileService = RealFileService(blobStore: blobStore);
/// await fileService.initialize();
///
/// // Pick photo - bytes auto-stored to BlobStore
/// final photo = await fileService.pickPhoto(source: PhotoSource.gallery);
/// if (photo != null) {
///   print('Stored: ${photo.filename} (${photo.sizeBytes}b) at ${photo.uuid}');
///   // Bytes already in blobStore, use photo.uuid to retrieve
///   final bytes = await blobStore.load(photo.uuid);
/// }
///
/// // Record audio - start/stop pattern
/// await fileService.startRecording();
/// // ... user records ...
/// final audio = await fileService.stopRecording();
///
/// // Or record for specific duration
/// final audio2 = await fileService.recordAudio(duration: Duration(seconds: 10));
/// ```
///
/// ## Testing approach
/// Mock implementation generates synthetic bytes and stores to BlobStore.
/// Real implementations tested on actual platforms (manual verification).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:everything_stack_template/patterns/file_storable.dart';
import 'package:everything_stack_template/services/blob_store.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

// ============ Enums ============

/// Source for photo input
enum PhotoSource {
  camera,
  gallery,
}

/// Source for video input
enum VideoSource {
  camera,
  gallery,
}

/// Recording state for audio
enum RecordingState {
  idle,
  recording,
  paused,
}

// ============ Abstract Interface ============

/// Platform-agnostic file input, processing, and storage service.
/// Takes BlobStore dependency - all file bytes are auto-stored.
abstract class FileService {
  /// Global singleton instance (defaults to mock for safe testing)
  static FileService instance = MockFileService(blobStore: MockBlobStore());

  /// The blob store used for storing file bytes
  BlobStore get blobStore;

  /// Pick photo from camera or gallery.
  /// Bytes are automatically stored to BlobStore.
  /// Returns FileMetadata with UUID pointing to stored blob, or null if cancelled.
  Future<FileMetadata?> pickPhoto({PhotoSource source = PhotoSource.gallery});

  /// Pick video from camera or gallery.
  /// Bytes are automatically stored to BlobStore.
  /// Returns FileMetadata with UUID pointing to stored blob, or null if cancelled.
  Future<FileMetadata?> pickVideo({VideoSource source = VideoSource.gallery});

  /// Record audio for specified duration.
  /// Bytes are automatically stored to BlobStore.
  /// Returns FileMetadata with UUID pointing to stored blob, or null if failed.
  Future<FileMetadata?> recordAudio({required Duration duration});

  /// Start recording audio. Call stopRecording() to finish.
  /// Returns true if recording started successfully.
  Future<bool> startRecording();

  /// Stop recording and save to BlobStore.
  /// Returns FileMetadata with UUID pointing to stored blob, or null if failed.
  Future<FileMetadata?> stopRecording();

  /// Get current recording state
  RecordingState get recordingState;

  /// Pick any file type.
  /// Optional allowedTypes filters by extension (e.g., ['pdf', 'doc']).
  /// Bytes are automatically stored to BlobStore.
  /// Returns FileMetadata with UUID pointing to stored blob, or null if cancelled.
  Future<FileMetadata?> pickFile({List<String>? allowedTypes});

  /// Compress image bytes.
  /// Quality: 0-100 (100 = highest quality, largest size).
  /// Returns compressed bytes, or null if invalid.
  Future<Uint8List?> compress(Uint8List bytes, {int quality = 80});

  /// Generate thumbnail from image bytes.
  /// Returns base64-encoded data URI (e.g., "data:image/jpeg;base64,...").
  /// Returns null if invalid.
  Future<String?> generateThumbnail(Uint8List bytes, {int width = 200});

  /// Detect MIME type from filename.
  /// Returns standard MIME type (e.g., "image/jpeg", "application/pdf").
  /// Returns "application/octet-stream" for unknown types.
  String detectMimeType(String filename);

  /// Initialize service (request permissions, setup).
  Future<void> initialize();

  /// Dispose and cleanup resources.
  Future<void> dispose();
}

// ============ Mock Implementation ============

/// Mock file service for testing without platform dependencies.
/// Stores synthetic bytes to the provided BlobStore.
class MockFileService extends FileService {
  @override
  final BlobStore blobStore;

  bool _cancelNext = false;
  RecordingState _recordingState = RecordingState.idle;
  DateTime? _recordingStartTime;
  static const _uuidGen = Uuid();

  MockFileService({required this.blobStore});

  /// Simulate cancelling next pick operation
  void setCancelNextPick() {
    _cancelNext = true;
  }

  @override
  RecordingState get recordingState => _recordingState;

  /// Generate mock bytes of specified size
  Uint8List _generateMockBytes(int size) {
    return Uint8List.fromList(List.generate(size, (i) => i % 256));
  }

  Future<FileMetadata> _createAndStoreMockFile({
    required String filename,
    required String mimeType,
    required int size,
    String? thumbnailBase64,
  }) async {
    final uuid = _uuidGen.v4();
    final bytes = _generateMockBytes(size);

    // Store to blob store
    await blobStore.save(uuid, bytes);

    final metadata = FileMetadata(
      uuid: uuid,
      filename: filename,
      mimeType: mimeType,
      sizeBytes: size,
      thumbnailBase64: thumbnailBase64,
    );
    metadata.createdAt = DateTime.now();
    return metadata;
  }

  @override
  Future<FileMetadata?> pickPhoto(
      {PhotoSource source = PhotoSource.gallery}) async {
    if (_cancelNext) {
      _cancelNext = false;
      return null;
    }

    const thumbnail =
        'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDA==';

    return _createAndStoreMockFile(
      filename: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      mimeType: 'image/jpeg',
      size: 2048,
      thumbnailBase64: thumbnail,
    );
  }

  @override
  Future<FileMetadata?> pickVideo(
      {VideoSource source = VideoSource.gallery}) async {
    if (_cancelNext) {
      _cancelNext = false;
      return null;
    }

    return _createAndStoreMockFile(
      filename: 'video_${DateTime.now().millisecondsSinceEpoch}.mp4',
      mimeType: 'video/mp4',
      size: 8192,
    );
  }

  @override
  Future<FileMetadata?> recordAudio({required Duration duration}) async {
    if (_cancelNext) {
      _cancelNext = false;
      return null;
    }

    // Simulate recording delay (capped at 100ms for tests)
    await Future.delayed(
        Duration(milliseconds: duration.inMilliseconds.clamp(0, 100)));

    // Mock: ~16KB per second of audio
    final size = (duration.inSeconds * 16 * 1024).clamp(512, 10 * 1024 * 1024);

    return _createAndStoreMockFile(
      filename: 'recording_${DateTime.now().millisecondsSinceEpoch}.m4a',
      mimeType: 'audio/mp4',
      size: size,
    );
  }

  @override
  Future<bool> startRecording() async {
    if (_recordingState != RecordingState.idle) return false;
    _recordingState = RecordingState.recording;
    _recordingStartTime = DateTime.now();
    return true;
  }

  @override
  Future<FileMetadata?> stopRecording() async {
    if (_recordingState != RecordingState.recording) return null;

    final duration = DateTime.now().difference(_recordingStartTime!);
    _recordingState = RecordingState.idle;
    _recordingStartTime = null;

    // Mock: ~16KB per second of audio
    final size = (duration.inSeconds * 16 * 1024).clamp(512, 10 * 1024 * 1024);

    return _createAndStoreMockFile(
      filename: 'recording_${DateTime.now().millisecondsSinceEpoch}.m4a',
      mimeType: 'audio/mp4',
      size: size,
    );
  }

  @override
  Future<FileMetadata?> pickFile({List<String>? allowedTypes}) async {
    if (_cancelNext) {
      _cancelNext = false;
      return null;
    }

    final ext = allowedTypes?.first ?? 'pdf';
    return _createAndStoreMockFile(
      filename: 'document_${DateTime.now().millisecondsSinceEpoch}.$ext',
      mimeType: detectMimeType('file.$ext'),
      size: 4096,
    );
  }

  @override
  Future<Uint8List?> compress(Uint8List bytes, {int quality = 80}) async {
    if (bytes.isEmpty) return null;

    // Mock: reduce by quality percentage
    final ratio = quality / 100.0;
    final newSize = (bytes.length * ratio).toInt();
    return Uint8List.fromList(bytes.sublist(0, newSize.clamp(1, bytes.length)));
  }

  @override
  Future<String?> generateThumbnail(Uint8List bytes, {int width = 200}) async {
    if (bytes.isEmpty) return null;

    // Mock: return data URI with mock base64 content
    return 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDA==';
  }

  @override
  String detectMimeType(String filename) {
    final lower = filename.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';

    switch (ext) {
      // Image types
      case 'jpg' || 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';

      // Audio types
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';

      // Video types
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';

      // Document types
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'html' || 'htm':
        return 'text/html';
      case 'xml':
        return 'text/xml';
      case 'json':
        return 'application/json';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/x-rar-compressed';

      default:
        return 'application/octet-stream';
    }
  }

  @override
  Future<void> initialize() async {
    // Ensure blob store is initialized
    await blobStore.initialize();
  }

  @override
  Future<void> dispose() async {
    _recordingState = RecordingState.idle;
    _recordingStartTime = null;
  }
}

// ============ Real Implementation ============

/// Real file service wrapping platform packages.
/// All picked/recorded files are automatically stored to the provided BlobStore.
class RealFileService extends FileService {
  @override
  final BlobStore blobStore;

  static const _uuidGen = Uuid();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();

  RecordingState _recordingState = RecordingState.idle;
  String? _currentRecordingFilename;

  RealFileService({required this.blobStore});

  @override
  RecordingState get recordingState => _recordingState;

  @override
  Future<FileMetadata?> pickPhoto(
      {PhotoSource source = PhotoSource.gallery}) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return null;

      final bytes = await image.readAsBytes();
      final uuid = _uuidGen.v4();

      // Store bytes to blob store
      await blobStore.save(uuid, bytes);

      // Generate thumbnail
      final thumbnail = await generateThumbnail(bytes, width: 200);

      final metadata = FileMetadata(
        uuid: uuid,
        filename: image.name,
        mimeType: detectMimeType(image.name),
        sizeBytes: bytes.length,
        thumbnailBase64: thumbnail,
      );
      metadata.createdAt = DateTime.now();

      return metadata;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<FileMetadata?> pickVideo(
      {VideoSource source = VideoSource.gallery}) async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: source == VideoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxDuration: const Duration(minutes: 10),
      );

      if (video == null) return null;

      final bytes = await video.readAsBytes();
      final uuid = _uuidGen.v4();

      // Store bytes to blob store
      await blobStore.save(uuid, bytes);

      final metadata = FileMetadata(
        uuid: uuid,
        filename: video.name,
        mimeType: detectMimeType(video.name),
        sizeBytes: bytes.length,
      );
      metadata.createdAt = DateTime.now();

      return metadata;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<FileMetadata?> recordAudio({required Duration duration}) async {
    try {
      if (!await _audioRecorder.hasPermission()) {
        return null;
      }

      final filename = 'recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: '', // Empty path uses temp directory
      );

      // Wait for specified duration
      await Future.delayed(duration);

      final path = await _audioRecorder.stop();
      if (path == null) return null;

      // Read the recorded file and store to blob store
      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final uuid = _uuidGen.v4();

      await blobStore.save(uuid, bytes);

      // Clean up temp file
      try {
        await file.delete();
      } catch (_) {}

      final metadata = FileMetadata(
        uuid: uuid,
        filename: filename,
        mimeType: 'audio/mp4',
        sizeBytes: bytes.length,
      );
      metadata.createdAt = DateTime.now();

      return metadata;
    } catch (e) {
      await _audioRecorder.stop();
      return null;
    }
  }

  @override
  Future<bool> startRecording() async {
    try {
      if (_recordingState != RecordingState.idle) return false;

      if (!await _audioRecorder.hasPermission()) {
        return false;
      }

      _currentRecordingFilename =
          'recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: '', // Empty path uses temp directory
      );

      _recordingState = RecordingState.recording;
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<FileMetadata?> stopRecording() async {
    try {
      if (_recordingState != RecordingState.recording) return null;

      final path = await _audioRecorder.stop();
      _recordingState = RecordingState.idle;

      if (path == null) return null;

      // Read the recorded file and store to blob store
      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final uuid = _uuidGen.v4();

      await blobStore.save(uuid, bytes);

      // Clean up temp file
      try {
        await file.delete();
      } catch (_) {}

      final filename = _currentRecordingFilename ??
          'recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingFilename = null;

      final metadata = FileMetadata(
        uuid: uuid,
        filename: filename,
        mimeType: 'audio/mp4',
        sizeBytes: bytes.length,
      );
      metadata.createdAt = DateTime.now();

      return metadata;
    } catch (e) {
      _recordingState = RecordingState.idle;
      return null;
    }
  }

  @override
  Future<FileMetadata?> pickFile({List<String>? allowedTypes}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: allowedTypes != null ? FileType.custom : FileType.any,
        allowedExtensions: allowedTypes,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;
      if (file.bytes == null) return null;

      final uuid = _uuidGen.v4();

      // Store bytes to blob store
      await blobStore.save(uuid, file.bytes!);

      final metadata = FileMetadata(
        uuid: uuid,
        filename: file.name,
        mimeType: detectMimeType(file.name),
        sizeBytes: file.size,
      );
      metadata.createdAt = DateTime.now();

      return metadata;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Uint8List?> compress(Uint8List bytes, {int quality = 80}) async {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final compressed = img.encodeJpg(image, quality: quality);
      return Uint8List.fromList(compressed);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<String?> generateThumbnail(Uint8List bytes, {int width = 200}) async {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final height = (image.height * width / image.width).round();
      final thumbnail = img.copyResize(image, width: width, height: height);
      final thumbnailBytes = img.encodeJpg(thumbnail, quality: 75);

      final base64 = base64Encode(thumbnailBytes);
      return 'data:image/jpeg;base64,$base64';
    } catch (e) {
      return null;
    }
  }

  @override
  String detectMimeType(String filename) {
    // Reuse the comprehensive detection from MockFileService
    return MockFileService(blobStore: blobStore).detectMimeType(filename);
  }

  @override
  Future<void> initialize() async {
    // Ensure blob store is initialized
    await blobStore.initialize();
  }

  @override
  Future<void> dispose() async {
    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }
    _audioRecorder.dispose();
    _recordingState = RecordingState.idle;
  }
}
