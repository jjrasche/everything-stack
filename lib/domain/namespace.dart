/// # Namespace
///
/// ## What it does
/// Represents a category of tools (e.g., "task", "timer", "health").
/// Namespaces organize tools and enable two-hop tool selection:
/// 1. LLM picks namespace based on semantic match
/// 2. Statistical classifier picks tool within namespace
///
/// ## Key Design
/// - keywords: Static registration keywords for initial matching
/// - semanticCentroid: Computed from all tool descriptions at registration
/// - Thresholds are stored in NamespaceAdaptationState (owned by Personality)
///
/// ## Usage
/// ```dart
/// final taskNamespace = Namespace(
///   name: 'task',
///   description: 'Manage tasks and reminders',
///   keywords: ['todo', 'reminder', 'schedule', 'task'],
/// );
/// ```

import 'package:objectbox/objectbox.dart';

import '../core/base_entity.dart';

@Entity()
class Namespace extends BaseEntity {
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

  // ============ Namespace fields ============

  /// Unique namespace identifier: "task", "timer", "health"
  String name;

  /// Human-readable description: "Manage tasks and reminders"
  String description;

  /// Static keywords for initial matching
  /// Used at registration before semantic centroids are computed
  List<String> keywords;

  /// Semantic centroid computed from all tool descriptions
  /// Null until computed during registration
  @Transient()
  List<double>? semanticCentroid;

  /// JSON storage for semanticCentroid
  String? semanticCentroidJson;

  // ============ Constructor ============

  Namespace({
    required this.name,
    required this.description,
    this.keywords = const [],
    this.semanticCentroid,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
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
        'description': description,
        'keywords': keywords,
        'semanticCentroid': semanticCentroid,
      };

  factory Namespace.fromJson(Map<String, dynamic> json) {
    final ns = Namespace(
      name: json['name'] as String,
      description: json['description'] as String,
      keywords: List<String>.from(json['keywords'] as List? ?? []),
      semanticCentroid: json['semanticCentroid'] != null
          ? List<double>.from(json['semanticCentroid'] as List)
          : null,
    );
    ns.id = json['id'] as int? ?? 0;
    ns.uuid = json['uuid'] as String? ?? '';
    ns.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    ns.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    ns.syncId = json['syncId'] as String?;
    return ns;
  }
}
