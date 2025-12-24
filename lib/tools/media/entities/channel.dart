/// # Channel
///
/// ## What it does
/// Represents a YouTube channel that the user is interested in.
/// Tracks channel metadata and subscription status.
///
/// ## Key features
/// - YouTube channel ID and URL
/// - Tracks subscription status
/// - Last checked for new content
/// - Channel statistics (cached)
///
/// ## Usage
/// ```dart
/// final channel = Channel(
///   name: 'Semantic Search Tutorials',
///   youtubeChannelId: 'UCxyz...',
///   youtubeUrl: 'https://youtube.com/@...',
/// );
///
/// await channelRepo.save(channel);
/// ```

import 'package:objectbox/objectbox.dart';

import '../../../core/base_entity.dart';

@Entity()
class Channel extends BaseEntity {
  // ============ BaseEntity field overrides ============
  @override
  @Id()
  int id = 0;

  @override
  @Unique()
  String uuid = '';

  @override
  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @override
  DateTime updatedAt = DateTime.now();

  @override
  String? syncId;

  // ============ Channel fields ============

  /// Channel name
  String name;

  /// YouTube channel ID
  String youtubeChannelId;

  /// YouTube channel URL
  String youtubeUrl;

  /// Is user subscribed to this channel?
  bool isSubscribed;

  /// Last time we checked for new videos
  @Property(type: PropertyType.date)
  DateTime? lastCheckedAt;

  /// Optional channel description from YouTube
  String? description;

  /// Channel subscriber count (cached)
  int? subscriberCount;

  /// Total video count (cached)
  int? videoCount;

  /// Channel avatar URL
  String? avatarUrl;

  /// When subscription was added
  @Property(type: PropertyType.date)
  DateTime? subscribedAt;

  // ============ Constructor ============

  Channel({
    required this.name,
    required this.youtubeChannelId,
    required this.youtubeUrl,
    this.isSubscribed = true,
    this.lastCheckedAt,
    this.description,
    this.subscriberCount,
    this.videoCount,
    this.avatarUrl,
    this.subscribedAt,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Computed properties ============

  /// Should we check for new videos?
  bool get shouldCheckForNew {
    if (!isSubscribed) return false;
    if (lastCheckedAt == null) return true;
    // Check if more than 1 hour has passed
    return DateTime.now().difference(lastCheckedAt!).inHours >= 1;
  }

  // ============ Actions ============

  /// Mark that we just checked for new videos
  void markChecked() {
    lastCheckedAt = DateTime.now();
    touch();
  }

  /// Subscribe to this channel
  void subscribe() {
    if (!isSubscribed) {
      isSubscribed = true;
      subscribedAt = DateTime.now();
      touch();
    }
  }

  /// Unsubscribe from this channel
  void unsubscribe() {
    if (isSubscribed) {
      isSubscribed = false;
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
        'name': name,
        'youtubeChannelId': youtubeChannelId,
        'youtubeUrl': youtubeUrl,
        'isSubscribed': isSubscribed,
        'lastCheckedAt': lastCheckedAt?.toIso8601String(),
        'description': description,
        'subscriberCount': subscriberCount,
        'videoCount': videoCount,
        'avatarUrl': avatarUrl,
        'subscribedAt': subscribedAt?.toIso8601String(),
      };

  factory Channel.fromJson(Map<String, dynamic> json) {
    final channel = Channel(
      name: json['name'] as String,
      youtubeChannelId: json['youtubeChannelId'] as String,
      youtubeUrl: json['youtubeUrl'] as String,
      isSubscribed: json['isSubscribed'] as bool? ?? true,
      lastCheckedAt: json['lastCheckedAt'] != null
          ? DateTime.parse(json['lastCheckedAt'] as String)
          : null,
      description: json['description'] as String?,
      subscriberCount: json['subscriberCount'] as int?,
      videoCount: json['videoCount'] as int?,
      avatarUrl: json['avatarUrl'] as String?,
      subscribedAt: json['subscribedAt'] != null
          ? DateTime.parse(json['subscribedAt'] as String)
          : null,
    );
    channel.id = json['id'] as int? ?? 0;
    channel.uuid = json['uuid'] as String? ?? '';
    channel.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    channel.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    channel.syncId = json['syncId'] as String?;
    return channel;
  }
}
