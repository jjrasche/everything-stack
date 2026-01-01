/// # Download
///
/// ## What it does
/// Tracks a media download job: status, progress, parameters, errors.
/// Separate from MediaItem because downloads can be retried/resumed.
///
/// ## Key features
/// - Tracks download progress (%)
/// - Parameters: URL, format, quality
/// - Error tracking for failed downloads
/// - Links to resulting MediaItem once complete
///
/// ## Usage
/// ```dart
/// final download = Download(
///   youtubeUrl: 'https://www.youtube.com/watch?v=...',
///   format: 'mp4',
///   quality: '720p',
/// );
///
/// await downloadRepo.save(download);
/// // Later, update as it progresses
/// download.updateProgress(50);
/// ```

import 'package:objectbox/objectbox.dart';

import '../../../core/base_entity.dart';
import '../../../services/sync_service.dart' show SyncStatus;

@Entity()
class Download extends BaseEntity {
  // ============ BaseEntity field overrides ============
  @override
  @Id()
  int id = 0;

  // NOTE: uuid, createdAt, updatedAt inherited from BaseEntity
  // Do NOT override - let auto-generation work

  @override
  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @override
  DateTime updatedAt = DateTime.now();

  @override
  String? syncId;

  @override
  SyncStatus syncStatus = SyncStatus.local;

  // ============ Download fields ============

  /// YouTube URL to download from
  String youtubeUrl;

  /// YouTube video ID
  String youtubeVideoId;

  /// Desired output format: 'mp4', 'mp3', 'webm', etc.
  String format;

  /// Desired quality: '1080p', '720p', '480p', 'audio-only', etc.
  String quality;

  /// Download status: 'queued', 'downloading', 'processing', 'completed', 'failed'
  String status;

  /// Progress percentage (0-100)
  int progressPercent;

  /// Error message if failed
  String? errorMessage;

  /// Estimated time remaining (seconds)
  int? estimatedSecondsRemaining;

  /// Download speed (bytes per second)
  int? downloadSpeedBytesPerSecond;

  /// Downloaded bytes so far
  int downloadedBytes;

  /// Total bytes to download (if known)
  int? totalBytes;

  /// When download started
  @Property(type: PropertyType.date)
  DateTime? startedAt;

  /// When download completed/failed
  @Property(type: PropertyType.date)
  DateTime? finishedAt;

  /// UUID of resulting MediaItem (once complete)
  String? mediaItemId;

  /// Retry count
  int retryCount;

  /// Max retries allowed
  int maxRetries;

  // ============ Constructor ============

  Download({
    required this.youtubeUrl,
    required this.youtubeVideoId,
    required this.format,
    this.quality = '720p',
    this.status = 'queued',
    this.progressPercent = 0,
    this.errorMessage,
    this.estimatedSecondsRemaining,
    this.downloadSpeedBytesPerSecond,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.startedAt,
    this.finishedAt,
    this.mediaItemId,
    this.retryCount = 0,
    this.maxRetries = 3,
  });

  // ============ Computed properties ============

  /// Is download currently active?
  bool get isActive =>
      status == 'queued' || status == 'downloading' || status == 'processing';

  /// Is download complete?
  bool get isComplete => status == 'completed';

  /// Did download fail?
  bool get isFailed => status == 'failed';

  /// Can we retry this download?
  bool get canRetry => isFailed && retryCount < maxRetries;

  /// Human-readable status
  String get statusLabel {
    switch (status) {
      case 'queued':
        return 'Queued';
      case 'downloading':
        return 'Downloading ($progressPercent%)';
      case 'processing':
        return 'Processing...';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      default:
        return status;
    }
  }

  // ============ Actions ============

  /// Start downloading
  void start() {
    status = 'downloading';
    startedAt = DateTime.now();
    progressPercent = 0;
    errorMessage = null;
    touch();
  }

  /// Update download progress
  void updateProgress(
    int percent, {
    int? bytesDownloaded,
    int? totalSize,
    int? speedBytesPerSec,
    int? secondsRemaining,
  }) {
    progressPercent = percent.clamp(0, 100);
    if (bytesDownloaded != null) downloadedBytes = bytesDownloaded;
    if (totalSize != null) totalBytes = totalSize;
    if (speedBytesPerSec != null)
      downloadSpeedBytesPerSecond = speedBytesPerSec;
    if (secondsRemaining != null) estimatedSecondsRemaining = secondsRemaining;
    touch();
  }

  /// Mark as processing (converting, etc.)
  void markProcessing() {
    status = 'processing';
    touch();
  }

  /// Mark download complete
  void markComplete(String mediaItemId) {
    status = 'completed';
    finishedAt = DateTime.now();
    this.mediaItemId = mediaItemId;
    progressPercent = 100;
    errorMessage = null;
    touch();
  }

  /// Mark download failed
  void markFailed(String error) {
    status = 'failed';
    finishedAt = DateTime.now();
    errorMessage = error;
    touch();
  }

  /// Retry the download
  void retry() {
    if (canRetry) {
      retryCount++;
      status = 'queued';
      progressPercent = 0;
      downloadedBytes = 0;
      errorMessage = null;
      startedAt = null;
      finishedAt = null;
      touch();
    }
  }

  // ============ Serialization ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'youtubeUrl': youtubeUrl,
        'youtubeVideoId': youtubeVideoId,
        'format': format,
        'quality': quality,
        'status': status,
        'progressPercent': progressPercent,
        'errorMessage': errorMessage,
        'estimatedSecondsRemaining': estimatedSecondsRemaining,
        'downloadSpeedBytesPerSecond': downloadSpeedBytesPerSecond,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'mediaItemId': mediaItemId,
        'retryCount': retryCount,
        'maxRetries': maxRetries,
      };

  factory Download.fromJson(Map<String, dynamic> json) {
    final download = Download(
      youtubeUrl: json['youtubeUrl'] as String,
      youtubeVideoId: json['youtubeVideoId'] as String,
      format: json['format'] as String,
      quality: json['quality'] as String? ?? '720p',
      status: json['status'] as String? ?? 'queued',
      progressPercent: json['progressPercent'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
      estimatedSecondsRemaining: json['estimatedSecondsRemaining'] as int?,
      downloadSpeedBytesPerSecond: json['downloadSpeedBytesPerSecond'] as int?,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      totalBytes: json['totalBytes'] as int?,
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      finishedAt: json['finishedAt'] != null
          ? DateTime.parse(json['finishedAt'] as String)
          : null,
      mediaItemId: json['mediaItemId'] as String?,
      retryCount: json['retryCount'] as int? ?? 0,
      maxRetries: json['maxRetries'] as int? ?? 3,
    );
    download.id = json['id'] as int? ?? 0;
    download.uuid = json['uuid'] as String? ?? '';
    download.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    download.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    download.syncId = json['syncId'] as String?;
    return download;
  }
}
