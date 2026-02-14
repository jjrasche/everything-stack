import 'package:json_annotation/json_annotation.dart';
import '../core/base_entity.dart';

part 'prompt_version.g.dart';

/// Versioned prompt for any component that uses LLM prompts.
///
/// Scoped by componentType (e.g., 'extraction', 'evaluation').
/// Only one version is active per componentType at a time.
@JsonSerializable()
class PromptVersion extends BaseEntity {
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

  String componentType;
  int version;
  String promptText;
  String reason;
  bool isActive;

  /// Performance metrics from evaluation (e.g., fInsight, coverage, focus).
  Map<String, dynamic> metrics;

  @JsonKey(includeFromJson: false, includeToJson: false)
  int get dbSyncStatus => syncStatus.index;
  set dbSyncStatus(int value) => syncStatus = SyncStatus.values[value];

  PromptVersion({
    required this.componentType,
    required this.version,
    required this.promptText,
    this.reason = '',
    this.isActive = false,
    Map<String, dynamic>? metrics,
  }) : metrics = metrics ?? {} {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  Map<String, dynamic> toJson() => _$PromptVersionToJson(this);
  factory PromptVersion.fromJson(Map<String, dynamic> json) =>
      _$PromptVersionFromJson(json);
}
