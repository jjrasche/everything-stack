/// MCP tool within a namespace (e.g., "task.create").
///
/// Pure Dart domain entity -- ORM decorators belong on wrapper classes (ToolOB)
/// so the same entity compiles on native (ObjectBox) and web (IndexedDB).

import '../core/base_entity.dart';

class Tool extends BaseEntity {
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

  // ============ Tool fields ============

  /// Tool name within namespace: "create", "complete", "list"
  String name;

  /// Parent namespace ID: "task", "timer"
  String namespaceId;

  /// Computed full name: "task.create"
  String get fullName => '$namespaceId.$name';

  /// Human-readable description: "Create a new task"
  String description;

  /// Static keywords for initial matching
  List<String> keywords;

  /// JSON Schema for tool parameters
  /// Defines what inputs the tool accepts
  Map<String, dynamic> parameters;

  /// Semantic centroid computed from description
  /// Null until computed during registration
  List<double>? semanticCentroid;

  // ============ Constructor ============

  Tool({
    required this.name,
    required this.namespaceId,
    required this.description,
    this.keywords = const [],
    this.parameters = const {},
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
        'namespaceId': namespaceId,
        'description': description,
        'keywords': keywords,
        'parameters': parameters,
        'semanticCentroid': semanticCentroid,
      };

  factory Tool.fromJson(Map<String, dynamic> json) {
    final tool = Tool(
      name: json['name'] as String,
      namespaceId: json['namespaceId'] as String,
      description: json['description'] as String,
      keywords: List<String>.from(json['keywords'] as List? ?? []),
      parameters: Map<String, dynamic>.from(json['parameters'] as Map? ?? {}),
      semanticCentroid: json['semanticCentroid'] != null
          ? List<double>.from(json['semanticCentroid'] as List)
          : null,
    );
    tool.id = json['id'] as int? ?? 0;
    tool.uuid = json['uuid'] as String? ?? '';
    tool.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    tool.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    tool.syncId = json['syncId'] as String?;
    return tool;
  }
}
