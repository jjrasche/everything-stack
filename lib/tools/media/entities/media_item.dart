/// # MediaItem
///
/// ## What it does
/// Represents a downloaded video or audio file from YouTube.
/// Tracks metadata: title, URL, channel, format, size, date downloaded.
/// Can be searched semantically (implements Embeddable).
///
/// ## Key features
/// - Links to Channel via channelId
/// - Tracks download status and format (audio/video)
/// - Stores YouTube URL for reference
/// - File size and download timestamp
/// - Searchable via semantic embeddings
///
/// ## Usage
/// ```dart
/// final media = MediaItem(
///   title: 'Why Semantic Search Matters',
///   youtubeUrl: 'https://www.youtube.com/watch?v=...',
///   channelId: channel.uuid,
///   format: 'mp4', // or 'mp3'
/// );
///
/// await mediaRepo.save(media);
/// ```

import '../../../core/base_entity.dart';
import '../../../services/sync_service.dart' show SyncStatus;
import '../../../patterns/embeddable.dart';

class MediaItem extends BaseEntity with Embeddable {
  // ============ BaseEntity field overrides ============
  @override
  int id = 0;

  // NOTE: uuid, createdAt, updatedAt inherited from BaseEntity
  // Do NOT override - let auto-generation work

  @override
  DateTime createdAt = DateTime.now();

  @override
  DateTime updatedAt = DateTime.now();

  @override
  String? syncId;

  @override
  SyncStatus syncStatus = SyncStatus.local;

  // ============ MediaItem fields ============

  /// Video/audio title
  String title;

  /// YouTube URL (reference to source)
  String youtubeUrl;

  /// YouTube video ID
  String youtubeVideoId;

  /// Channel this came from (FK to Channel)
  String channelId;

  /// Format: 'mp4', 'mp3', 'webm', etc.
  String format;

  /// File size in bytes
  int fileSizeBytes;

  /// Local blob storage path/ID (if stored)
  String? blobId;

  /// Download status: 'pending', 'downloading', 'completed', 'failed'
  String downloadStatus;

  /// Optional error message if failed
  String? downloadError;

  /// When it was downloaded
  DateTime? downloadedAt;

  /// Optional description from YouTube
  String? description;

  /// Video duration in seconds
  int? durationSeconds;

  /// YouTube publish date
  DateTime? publishedAt;

  /// View count (cached from YouTube)
  int? viewCount;

  // ============ Embeddable mixin fields ============

  @override
  String? embeddingModel;

  @override
  String? embeddingId;

  @override
  DateTime? embeddedAt;

  // ============ Constructor ============

  MediaItem({
    required this.title,
    required this.youtubeUrl,
    required this.youtubeVideoId,
    required this.channelId,
    required this.format,
    this.fileSizeBytes = 0,
    this.blobId,
    this.downloadStatus = 'pending',
    this.downloadError,
    this.downloadedAt,
    this.description,
    this.durationSeconds,
    this.publishedAt,
    this.viewCount,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Computed properties ============

  /// Is this media downloaded and ready?
  bool get isDownloaded => downloadStatus == 'completed' && blobId != null;

  /// Is download in progress?
  bool get isDownloading => downloadStatus == 'downloading';

  /// Is this audio format?
  bool get isAudio => ['mp3', 'm4a', 'aac'].contains(format.toLowerCase());

  /// Is this video format?
  bool get isVideo => ['mp4', 'webm', 'mkv'].contains(format.toLowerCase());

  /// File size in MB
  double get fileSizeMB => fileSizeBytes / (1024 * 1024);

  // ============ Actions ============

  /// Mark download as in progress
  void startDownload() {
    downloadStatus = 'downloading';
    downloadError = null;
    touch();
  }

  /// Mark download complete
  void completeDownload(String blobId, int sizeBytes) {
    downloadStatus = 'completed';
    downloadedAt = DateTime.now();
    this.blobId = blobId;
    fileSizeBytes = sizeBytes;
    downloadError = null;
    touch();
  }

  /// Mark download failed
  void failDownload(String error) {
    downloadStatus = 'failed';
    downloadError = error;
    touch();
  }

  // ============ Embeddable Implementation ============

  @override
  String get textForEmbedding =>
      '$title\n${description ?? ''}\n$youtubeUrl'.trim();

  @override
  String toEmbeddingInput() => textForEmbedding;

  // ============ Serialization ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'title': title,
        'youtubeUrl': youtubeUrl,
        'youtubeVideoId': youtubeVideoId,
        'channelId': channelId,
        'format': format,
        'fileSizeBytes': fileSizeBytes,
        'blobId': blobId,
        'downloadStatus': downloadStatus,
        'downloadError': downloadError,
        'downloadedAt': downloadedAt?.toIso8601String(),
        'description': description,
        'durationSeconds': durationSeconds,
        'publishedAt': publishedAt?.toIso8601String(),
        'viewCount': viewCount,
        'embeddingModel': embeddingModel,
        'embeddingId': embeddingId,
        'embeddedAt': embeddedAt?.toIso8601String(),
      };

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final item = MediaItem(
      title: json['title'] as String,
      youtubeUrl: json['youtubeUrl'] as String,
      youtubeVideoId: json['youtubeVideoId'] as String,
      channelId: json['channelId'] as String,
      format: json['format'] as String,
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      blobId: json['blobId'] as String?,
      downloadStatus: json['downloadStatus'] as String? ?? 'pending',
      downloadError: json['downloadError'] as String?,
      downloadedAt: json['downloadedAt'] != null
          ? DateTime.parse(json['downloadedAt'] as String)
          : null,
      description: json['description'] as String?,
      durationSeconds: json['durationSeconds'] as int?,
      publishedAt: json['publishedAt'] != null
          ? DateTime.parse(json['publishedAt'] as String)
          : null,
      viewCount: json['viewCount'] as int?,
    );
    item.id = json['id'] as int? ?? 0;
    item.uuid = json['uuid'] as String? ?? '';
    item.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    item.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    item.syncId = json['syncId'] as String?;
    item.embeddingModel = json['embeddingModel'] as String?;
    item.embeddingId = json['embeddingId'] as String?;
    item.embeddedAt = json['embeddedAt'] != null
        ? DateTime.parse(json['embeddedAt'] as String)
        : null;
    return item;
  }
}
