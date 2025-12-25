/// # InvocationOB - ObjectBox Wrapper
///
/// ObjectBox-decorated version of Invocation domain entity.
/// Contains all ObjectBox decorators (@Entity, @Id, @Property, etc.)

import 'package:objectbox/objectbox.dart';
import '../../domain/invocation.dart';

@Entity()
class InvocationOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // ============ Invocation-specific fields ============

  String correlationId;
  String componentType;
  bool success;
  double confidence;

  // JSON storage for dynamic fields
  String? inputJson;
  String? outputJson;
  String? metadataJson;

  // ============ Constructor ============

  InvocationOB({
    required this.correlationId,
    required this.componentType,
    required this.success,
    required this.confidence,
    this.inputJson,
    this.outputJson,
    this.metadataJson,
  });

  // ============ Conversion Methods ============

  /// Convert from domain Invocation to ObjectBox wrapper
  factory InvocationOB.fromInvocation(Invocation invocation) {
    return InvocationOB(
      correlationId: invocation.correlationId,
      componentType: invocation.componentType,
      success: invocation.success,
      confidence: invocation.confidence,
      inputJson: invocation.inputJson,
      outputJson: invocation.outputJson,
      metadataJson: invocation.metadataJson,
    )
      ..id = invocation.id
      ..uuid = invocation.uuid
      ..createdAt = invocation.createdAt
      ..updatedAt = invocation.updatedAt
      ..syncId = invocation.syncId;
  }

  /// Convert from ObjectBox wrapper back to domain Invocation
  Invocation toInvocation() {
    return Invocation(
      correlationId: correlationId,
      componentType: componentType,
      success: success,
      confidence: confidence,
    )
      ..id = id
      ..uuid = uuid
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncId = syncId
      ..inputJson = inputJson
      ..outputJson = outputJson
      ..metadataJson = metadataJson;
  }
}
