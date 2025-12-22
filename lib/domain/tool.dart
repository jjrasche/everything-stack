/// # Tool
///
/// ## What it does
/// Represents an MCP tool within a namespace.
/// Tools are the actual functions that can be invoked (e.g., "task.create").
///
/// ## Key Design
/// - namespaceId: Links to parent Namespace
/// - fullName: Computed as "namespaceId.name" (e.g., "task.create")
/// - parameters: JSON Schema defining tool parameters
/// - semanticCentroid: Computed from description for semantic matching
///
/// ## Two-Hop Selection
/// 1. LLM picks namespace (semantic match)
/// 2. Statistical classifier picks tool within namespace
/// 3. Tool's parameters guide slot filling
///
/// ## Usage
/// ```dart
/// final createTool = Tool(
///   name: 'create',
///   namespaceId: 'task',
///   description: 'Create a new task',
///   keywords: ['add', 'new', 'make'],
///   parameters: {
///     'type': 'object',
///     'properties': {
///       'title': {'type': 'string'},
///       'dueDate': {'type': 'string', 'format': 'date-time'},
///     },
///     'required': ['title'],
///   },
/// );
/// print(createTool.fullName); // "task.create"
/// ```

import 'package:objectbox/objectbox.dart';

import '../core/base_entity.dart';

@Entity()
class Tool extends BaseEntity {
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
  @Transient()
  Map<String, dynamic> parameters;

  /// JSON storage for parameters
  String parametersJson = '{}';

  /// Semantic centroid computed from description
  /// Null until computed during registration
  @Transient()
  List<double>? semanticCentroid;

  /// JSON storage for semanticCentroid
  String? semanticCentroidJson;

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
