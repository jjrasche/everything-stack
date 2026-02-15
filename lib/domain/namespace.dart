/// Tool category for two-hop selection (LLM picks namespace, classifier picks tool).
///
/// Pure Dart domain entity -- ORM decorators belong on wrapper classes (NamespaceOB)
/// so the same entity compiles on native (ObjectBox) and web (IndexedDB).

import '../core/base_entity.dart';

class Namespace extends BaseEntity {
  // ============ BaseEntity field overrides ============
  @override
  int id = 0;

  @override
  String uuid = '';

  @override
  DateTime createdAt = DateTime.now();

  @override
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
  List<double>? semanticCentroid;

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
