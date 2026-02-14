import 'dart:convert';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/domain/prompt_version.dart';
import 'package:everything_stack_template/core/base_entity.dart';

@Entity()
class PromptVersionOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  @Index()
  late String componentType;

  int version = 1;

  late String promptText;

  String reason = '';

  bool isActive = false;

  String? metricsJson;

  int syncStatus = 0;

  PromptVersionOB();

  factory PromptVersionOB.fromPromptVersion(PromptVersion pv) {
    return PromptVersionOB()
      ..id = pv.id
      ..uuid = pv.uuid
      ..createdAt = pv.createdAt
      ..updatedAt = pv.updatedAt
      ..syncId = pv.syncId
      ..componentType = pv.componentType
      ..version = pv.version
      ..promptText = pv.promptText
      ..reason = pv.reason
      ..isActive = pv.isActive
      ..metricsJson = pv.metrics.isNotEmpty ? jsonEncode(pv.metrics) : null
      ..syncStatus = pv.syncStatus.index;
  }

  PromptVersion toPromptVersion() {
    final pv = PromptVersion(
      componentType: componentType,
      version: version,
      promptText: promptText,
      reason: reason,
      isActive: isActive,
      metrics: metricsJson != null
          ? Map<String, dynamic>.from(jsonDecode(metricsJson!) as Map)
          : null,
    )
      ..id = id
      ..uuid = uuid
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncId = syncId
      ..syncStatus = SyncStatus.values[syncStatus];

    return pv;
  }

  void validate() {
    if (uuid.isEmpty) throw ArgumentError('uuid cannot be empty');
    if (componentType.isEmpty) {
      throw ArgumentError('componentType cannot be empty');
    }
    if (promptText.isEmpty) throw ArgumentError('promptText cannot be empty');
    if (version < 1) throw ArgumentError('version must be >= 1');
  }

  @override
  String toString() =>
      'PromptVersionOB($uuid, $componentType v$version, active: $isActive)';
}
