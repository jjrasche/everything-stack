import 'dart:convert';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/domain/tool.dart';

@Entity()
class ToolOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // ============ Tool-specific fields ============

  String name;
  String namespaceId;
  String description;

  /// JSON storage for keywords
  String keywordsJson = '[]';

  /// Keywords getter/setter
  @Transient()
  List<String> get keywords {
    if (keywordsJson.isEmpty || keywordsJson == '[]') return [];
    return List<String>.from(json.decode(keywordsJson) as List);
  }

  set keywords(List<String> value) {
    keywordsJson = json.encode(value);
  }

  /// JSON storage for parameters
  String parametersJson = '{}';

  /// Parameters getter/setter
  @Transient()
  Map<String, dynamic> get parameters {
    if (parametersJson.isEmpty || parametersJson == '{}') return {};
    return Map<String, dynamic>.from(json.decode(parametersJson) as Map);
  }

  set parameters(Map<String, dynamic> value) {
    parametersJson = json.encode(value);
  }

  /// JSON storage for semanticCentroid
  String? semanticCentroidJson;

  /// Semantic centroid getter/setter
  @Transient()
  List<double>? get semanticCentroid {
    if (semanticCentroidJson == null || semanticCentroidJson!.isEmpty) {
      return null;
    }
    return List<double>.from(json.decode(semanticCentroidJson!) as List);
  }

  set semanticCentroid(List<double>? value) {
    semanticCentroidJson = value != null ? json.encode(value) : null;
  }

  // ============ Constructor ============

  ToolOB({
    required this.name,
    required this.namespaceId,
    required this.description,
  });

  // ============ Conversion to/from domain entity ============

  /// Convert from domain entity to ObjectBox wrapper
  factory ToolOB.fromTool(Tool tool) {
    return ToolOB(
      name: tool.name,
      namespaceId: tool.namespaceId,
      description: tool.description,
    )
      ..id = tool.id
      ..uuid = tool.uuid
      ..createdAt = tool.createdAt
      ..updatedAt = tool.updatedAt
      ..syncId = tool.syncId
      ..keywords = tool.keywords
      ..parameters = tool.parameters
      ..semanticCentroid = tool.semanticCentroid;
  }

  /// Convert from ObjectBox wrapper to domain entity
  Tool toTool() {
    final tool = Tool(
      name: name,
      namespaceId: namespaceId,
      description: description,
      keywords: keywords,
      parameters: parameters,
      semanticCentroid: semanticCentroid,
    );
    tool.id = id;
    tool.uuid = uuid;
    tool.createdAt = createdAt;
    tool.updatedAt = updatedAt;
    tool.syncId = syncId;
    return tool;
  }
}
