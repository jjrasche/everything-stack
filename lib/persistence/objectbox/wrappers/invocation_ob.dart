/// # InvocationOB - ObjectBox Wrapper
///
/// ObjectBox-decorated version of Invocation domain entity.
/// Contains all ObjectBox decorators (@Entity, @Id, @Property, etc.)

import 'dart:convert';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/core/invocation.dart';

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

  String eventId;
  String componentType;
  String? turnId;
  bool success;
  double confidence;

  // JSON storage for dynamic fields
  String? inputJson;
  String? outputJson;
  String? metadataJson;

  // ============ Constructor ============

  InvocationOB({
    required this.eventId,
    required this.componentType,
    required this.success,
    required this.confidence,
    this.turnId,
    this.inputJson,
    this.outputJson,
    this.metadataJson,
  });

  // ============ Conversion Methods ============

  /// Convert from domain Invocation to ObjectBox wrapper
  factory InvocationOB.fromInvocation(Invocation invocation) {
    return InvocationOB(
      eventId: invocation.eventId,
      componentType: invocation.componentType,
      success: invocation.success,
      confidence: invocation.confidence,
      turnId: invocation.turnId,
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
    // Deserialize JSON strings back to Maps
    Map<String, dynamic>? inputMap;
    if (inputJson != null && inputJson!.isNotEmpty) {
      try {
        inputMap = jsonDecode(inputJson!) as Map<String, dynamic>;
      } catch (_) {
        inputMap = null;
      }
    }

    Map<String, dynamic>? outputMap;
    if (outputJson != null && outputJson!.isNotEmpty) {
      try {
        outputMap = jsonDecode(outputJson!) as Map<String, dynamic>;
      } catch (_) {
        outputMap = null;
      }
    }

    Map<String, dynamic>? metadataMap;
    if (metadataJson != null && metadataJson!.isNotEmpty) {
      try {
        metadataMap = jsonDecode(metadataJson!) as Map<String, dynamic>;
      } catch (_) {
        metadataMap = null;
      }
    }

    return Invocation(
      eventId: eventId,
      componentType: componentType,
      success: success,
      confidence: confidence,
      turnId: turnId,
      input: inputMap,
      output: outputMap,
      metadata: metadataMap,
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
