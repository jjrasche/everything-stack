import 'dart:convert';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/domain/namespace.dart';

@Entity()
class NamespaceOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // ============ Namespace-specific fields ============

  String name;
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

  NamespaceOB({
    required this.name,
    required this.description,
  });

  // ============ Conversion to/from domain entity ============

  /// Convert from domain entity to ObjectBox wrapper
  factory NamespaceOB.fromNamespace(Namespace namespace) {
    return NamespaceOB(
      name: namespace.name,
      description: namespace.description,
    )
      ..id = namespace.id
      ..uuid = namespace.uuid
      ..createdAt = namespace.createdAt
      ..updatedAt = namespace.updatedAt
      ..syncId = namespace.syncId
      ..keywords = namespace.keywords
      ..semanticCentroid = namespace.semanticCentroid;
  }

  /// Convert from ObjectBox wrapper to domain entity
  Namespace toNamespace() {
    final namespace = Namespace(
      name: name,
      description: description,
      keywords: keywords,
      semanticCentroid: semanticCentroid,
    );
    namespace.id = id;
    namespace.uuid = uuid;
    namespace.createdAt = createdAt;
    namespace.updatedAt = updatedAt;
    namespace.syncId = syncId;
    return namespace;
  }
}
