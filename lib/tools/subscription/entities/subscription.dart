/// # Subscription
///
/// ## What it does
/// Represents a subscription to a media source (YouTube channel, RSS feed, etc).
/// Tracks subscription metadata and polling state.
///
/// ## Fields
/// - sourceUrl: URL of the media source to subscribe to
/// - sourceType: Type of source (youtube_channel, youtube_playlist, rss_feed)
/// - name: Display name for the subscription
/// - isActive: Whether this subscription is currently active/polling
/// - lastCheckedAt: When we last polled this source for new media
///
/// ## Usage
/// ```dart
/// final subscription = Subscription(
///   sourceUrl: 'https://youtube.com/@crashcourse',
///   sourceType: 'youtube_channel',
///   name: 'Crash Course',
/// );
/// ```

import 'package:objectbox/objectbox.dart';

import '../../../core/base_entity.dart';

@Entity()
class Subscription extends BaseEntity {
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
  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  @override
  String? syncId;

  // ============ Subscription fields ============

  /// URL of the media source
  /// e.g., "https://youtube.com/@crashcourse", "https://example.com/rss.xml"
  String sourceUrl;

  /// Type of media source
  /// Options: "youtube_channel", "youtube_playlist", "rss_feed"
  String sourceType;

  /// Display name for this subscription
  /// e.g., "Crash Course", "Daily News"
  String name;

  /// Is this subscription currently active (polling enabled)?
  bool isActive;

  /// When was this subscription last checked for new media?
  @Property(type: PropertyType.date)
  DateTime? lastCheckedAt;

  /// How many items have been downloaded from this subscription?
  int totalItemsDownloaded;

  // ============ Constructor ============

  Subscription({
    required this.sourceUrl,
    required this.sourceType,
    required this.name,
    this.isActive = true,
    this.lastCheckedAt,
    this.totalItemsDownloaded = 0,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Computed properties ============

  /// Has this subscription been polled yet?
  bool get hasBeenPolled => lastCheckedAt != null;

  /// How long ago was this subscription last checked?
  Duration? get timeSinceLastCheck =>
      lastCheckedAt != null
          ? DateTime.now().difference(lastCheckedAt!)
          : null;

  // ============ Actions ============

  /// Record that we polled this subscription
  void recordPolling() {
    lastCheckedAt = DateTime.now();
    touch();
  }

  /// Increment downloaded items counter
  void addDownloadedItems(int count) {
    totalItemsDownloaded += count;
    touch();
  }

  /// Deactivate this subscription
  void deactivate() {
    isActive = false;
    touch();
  }

  /// Reactivate this subscription
  void activate() {
    isActive = true;
    touch();
  }

  // ============ Serialization ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'sourceUrl': sourceUrl,
        'sourceType': sourceType,
        'name': name,
        'isActive': isActive,
        'lastCheckedAt': lastCheckedAt?.toIso8601String(),
        'totalItemsDownloaded': totalItemsDownloaded,
      };

  factory Subscription.fromJson(Map<String, dynamic> json) {
    final sub = Subscription(
      sourceUrl: json['sourceUrl'] as String,
      sourceType: json['sourceType'] as String,
      name: json['name'] as String,
      isActive: json['isActive'] as bool? ?? true,
      lastCheckedAt: json['lastCheckedAt'] != null
          ? DateTime.parse(json['lastCheckedAt'] as String)
          : null,
      totalItemsDownloaded: json['totalItemsDownloaded'] as int? ?? 0,
    );
    sub.id = json['id'] as int? ?? 0;
    sub.uuid = json['uuid'] as String? ?? '';
    sub.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    sub.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    sub.syncId = json['syncId'] as String?;
    return sub;
  }
}
