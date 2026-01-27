/// # Categorizer Service Type Definitions
///
/// Types for CategorizerService: adaptation data, invocation input/output.

import 'dart:convert';
import '../../core/adaptation_data.dart';

/// Learned categorization preferences (trainable parameters).
///
/// Adaptive tagging learns:
/// - Common entity categories for each entity type
/// - User-preferred tag taxonomy
/// - Confidence thresholds for auto-tagging
class CategorizerAdaptationData extends AdaptationData {
  /// Confidence threshold for auto-applying tags (default: 0.7)
  /// Tags below this confidence require manual confirmation
  final double autoTagThreshold;

  /// Maximum tags to apply per entity (default: 5)
  final int maxTagsPerEntity;

  /// Learned tag preferences by entity type
  /// Maps entityType → list of common tags
  /// Example: {'Invocation': ['llm', 'tool', 'semantic'], 'Note': ['personal', 'work']}
  final Map<String, List<String>> preferredTagsByEntityType;

  /// Custom user taxonomy
  /// Maps user-defined category → list of tags
  /// Example: {'work': ['meeting', 'project', 'deadline'], 'personal': ['health', 'family']}
  final Map<String, List<String>> customTaxonomy;

  CategorizerAdaptationData({
    required this.autoTagThreshold,
    required this.maxTagsPerEntity,
    required this.preferredTagsByEntityType,
    required this.customTaxonomy,
  });

  /// Default adaptation state (untrained).
  factory CategorizerAdaptationData.defaults() => CategorizerAdaptationData(
        autoTagThreshold: 0.7,
        maxTagsPerEntity: 5,
        preferredTagsByEntityType: {},
        customTaxonomy: {},
      );

  /// Deserialize from JSON.
  factory CategorizerAdaptationData.fromJson(Map<String, dynamic> json) =>
      CategorizerAdaptationData(
        autoTagThreshold: json['autoTagThreshold'] as double? ?? 0.7,
        maxTagsPerEntity: json['maxTagsPerEntity'] as int? ?? 5,
        preferredTagsByEntityType:
            (json['preferredTagsByEntityType'] as Map<String, dynamic>? ?? {})
                .map((k, v) => MapEntry(k, List<String>.from(v as List))),
        customTaxonomy: (json['customTaxonomy'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, List<String>.from(v as List))),
      );

  /// Serialize to JSON string.
  @override
  String toJson() => jsonEncode({
        'autoTagThreshold': autoTagThreshold,
        'maxTagsPerEntity': maxTagsPerEntity,
        'preferredTagsByEntityType': preferredTagsByEntityType,
        'customTaxonomy': customTaxonomy,
      });
}

/// Input to categorization operation (what entity was categorized).
class CategorizerInvocationInput {
  final String entityId;
  final String entityType;
  final String content;

  CategorizerInvocationInput({
    required this.entityId,
    required this.entityType,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        'entityId': entityId,
        'entityType': entityType,
        'content':
            content.substring(0, content.length > 200 ? 200 : content.length) +
                '...',
      };

  factory CategorizerInvocationInput.fromJson(Map<String, dynamic> json) =>
      CategorizerInvocationInput(
        entityId: json['entityId'] as String,
        entityType: json['entityType'] as String,
        content: json['content'] as String,
      );
}

/// Output from categorization operation (what tags were applied).
class CategorizerInvocationOutput {
  final List<String> tags;
  final Map<String, double> confidenceByTag;
  final bool autoApplied;

  CategorizerInvocationOutput({
    required this.tags,
    required this.confidenceByTag,
    required this.autoApplied,
  });

  Map<String, dynamic> toJson() => {
        'tags': tags,
        'confidenceByTag': confidenceByTag,
        'autoApplied': autoApplied,
      };

  factory CategorizerInvocationOutput.fromJson(Map<String, dynamic> json) =>
      CategorizerInvocationOutput(
        tags: List<String>.from(json['tags'] as List),
        confidenceByTag:
            Map<String, double>.from(json['confidenceByTag'] as Map),
        autoApplied: json['autoApplied'] as bool,
      );
}
