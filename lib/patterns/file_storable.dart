/// # FileStorable
///
/// ## What it does
/// Enables entities to have file attachments (images, audio, video, documents).
/// Stores metadata (filename, MIME type, thumbnail) inline.
/// Actual file bytes managed by BlobStore service.
///
/// ## What it enables
/// - Notes with images/attachments
/// - Posts with media files
/// - Documents with thumbnails
/// - Forms with file uploads
/// - Voice notes with audio
///
/// ## Schema addition
/// ```dart
/// @Embedded()
/// class FileMetadata {
///   String uuid;                    // Blob identifier
///   String filename;                // Original filename
///   String mimeType;                // image/jpeg, audio/mp3, etc.
///   int size;                       // File size in bytes
///   String? thumbnailBase64;        // Small preview for images
///   DateTime createdAt;
/// }
///
/// class Note extends BaseEntity with FileStorable {
///   List<FileMetadata> attachments = [];
/// }
/// ```
///
/// ## Usage
/// ```dart
/// final note = Note(title: 'Meeting');
///
/// // Add attachment
/// final fileMetadata = FileMetadata(
///   uuid: 'file-uuid',
///   filename: 'screenshot.png',
///   mimeType: 'image/png',
///   size: 1024,
///   thumbnailBase64: 'data:image/png;base64,abc123==',
///   createdAt: DateTime.now(),
/// );
/// note.addAttachment(fileMetadata);
///
/// // Query attachments
/// if (note.hasAttachments) {
///   final images = note.imageAttachments;
///   final totalSize = note.totalAttachmentSize;
/// }
///
/// // Find specific attachment
/// final audio = note.getAttachment('uuid-123');
///
/// // Remove attachment
/// note.removeAttachment('uuid-123');
/// ```
///
/// ## File operations
/// File picking, compression, thumbnail generation handled by FileService.
/// This mixin only manages metadata.
///
/// ## Testing approach
/// Test attachment CRUD, queries, filters.
/// File operations tested in FileService.
///
/// ## Integrates with
/// - BlobStore: Stores actual file bytes
/// - FileService: Picks/processes files, updates metadata

import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';

part 'file_storable.g.dart';

/// File attachment metadata
/// Stored as JSON in database (not embedded object)
@JsonSerializable()
class FileMetadata {
  /// Unique identifier (UUID) for blob in BlobStore
  String uuid;

  /// Original filename with extension
  String filename;

  /// MIME type (image/jpeg, audio/mp3, etc.)
  String mimeType;

  /// File size in bytes
  int sizeBytes;

  /// Optional base64-encoded thumbnail for images
  /// Format: "data:image/jpeg;base64,abc123=="
  String? thumbnailBase64;

  /// When attachment was created
  DateTime createdAt = DateTime(1970);

  FileMetadata({
    this.uuid = '',
    this.filename = '',
    this.mimeType = '',
    this.sizeBytes = 0,
    this.thumbnailBase64,
  });

  /// Check if this is an image file
  bool get isImage => mimeType.startsWith('image/');

  /// Check if this is an audio file
  bool get isAudio => mimeType.startsWith('audio/');

  /// Check if this is a video file
  bool get isVideo => mimeType.startsWith('video/');

  /// Get file extension from filename
  String get extension {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot == -1) return '';
    return filename.substring(lastDot + 1).toLowerCase();
  }

  @override
  String toString() =>
      'FileMetadata($filename, $mimeType, ${sizeBytes}b, created: $createdAt)';

  /// JSON serialization
  Map<String, dynamic> toJson() => _$FileMetadataToJson(this);
  factory FileMetadata.fromJson(Map<String, dynamic> json) =>
      _$FileMetadataFromJson(json);
}

/// Mixin for entities with file attachments
mixin FileStorable {
  /// List of attached files
  /// Stored as JSON string in database, excluded from entity JSON serialization
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<FileMetadata> attachments = [];

  /// Database storage for attachments as JSON string
  /// Override in entity class if using ObjectBox
  String get dbAttachments {
    if (attachments.isEmpty) return '';
    return jsonEncode(attachments.map((a) => a.toJson()).toList());
  }

  set dbAttachments(String value) {
    if (value.isEmpty) {
      attachments = [];
      return;
    }
    final List<dynamic> decoded = jsonDecode(value);
    attachments = decoded
        .map((json) => FileMetadata.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Add attachment to this entity
  void addAttachment(FileMetadata metadata) {
    attachments.add(metadata);
  }

  /// Remove attachment by UUID
  /// Returns true if found and removed, false if not found
  bool removeAttachment(String uuid) {
    final before = attachments.length;
    attachments.removeWhere((m) => m.uuid == uuid);
    return attachments.length < before;
  }

  /// Get attachment by UUID
  /// Returns null if not found
  FileMetadata? getAttachment(String uuid) {
    try {
      return attachments.firstWhere((m) => m.uuid == uuid);
    } catch (e) {
      return null;
    }
  }

  /// Does this entity have any attachments?
  bool get hasAttachments => attachments.isNotEmpty;

  /// Get all image attachments
  List<FileMetadata> get imageAttachments =>
      attachments.where((m) => m.isImage).toList();

  /// Get all audio attachments
  List<FileMetadata> get audioAttachments =>
      attachments.where((m) => m.isAudio).toList();

  /// Get all video attachments
  List<FileMetadata> get videoAttachments =>
      attachments.where((m) => m.isVideo).toList();

  /// Total size of all attachments in bytes
  int get totalAttachmentSize =>
      attachments.fold<int>(0, (sum, m) => sum + m.sizeBytes);

  /// Clear all attachments
  void clearAttachments() {
    attachments.clear();
  }
}
