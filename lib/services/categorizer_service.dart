import 'package:flutter/material.dart';
import 'dart:convert';
import '../core/base_entity.dart';
import '../core/trainable.dart';
import '../core/invocation.dart';
import '../core/feedback.dart' as core_feedback;
import './types/categorizer_types.dart';

class CategorizerService with Trainable<CategorizerAdaptationData> {
  CategorizerService();

  /// Categorize an entity by analyzing its content.
  ///
  /// Flow:
  /// 1. Load adaptation state (learned tag preferences)
  /// 2. Extract content from entity
  /// 3. Apply rule-based categorization (keyword matching, pattern detection)
  /// 4. Filter by confidence threshold
  /// 5. Limit to maxTagsPerEntity
  /// 6. Record invocation for training feedback
  ///
  /// Returns: List of tags with confidences
  Future<List<String>> categorizeEntity(
    BaseEntity entity, {
    String? userId,
  }) async {
    // 1. Load adaptation state
    final adaptationState = await getAdaptationState(userId: userId);
    final adaptationData =
        adaptationState.dataJson.isNotEmpty && adaptationState.dataJson != '{}'
            ? deserializeData(adaptationState.dataJson)
            : createDefaultData();

    // 2. Extract content from entity
    final content = _extractContent(entity);
    if (content.isEmpty) {
      return [];
    }

    // 3. Apply rule-based categorization
    final entityType = entity.runtimeType.toString();
    final tagConfidences = _analyzeContent(
      content: content,
      entityType: entityType,
      adaptationData: adaptationData,
    );

    // 4. Filter by confidence threshold
    final autoTagThreshold = adaptationData.autoTagThreshold;
    final confidenceByTag = <String, double>{};
    final autoAppliedTags = <String>[];

    for (final entry in tagConfidences.entries) {
      if (entry.value >= autoTagThreshold) {
        autoAppliedTags.add(entry.key);
        confidenceByTag[entry.key] = entry.value;
      }
    }

    // 5. Limit to maxTagsPerEntity
    final maxTags = adaptationData.maxTagsPerEntity;
    final sortedTags = autoAppliedTags.toList()
      ..sort((a, b) => confidenceByTag[b]!.compareTo(confidenceByTag[a]!));
    final finalTags = sortedTags.take(maxTags).toList();

    // 6. Record invocation for training feedback
    await recordInvocation(
      entity.uuid,
      Invocation(
        eventId: entity.uuid,
        componentType: componentType,
        implementer: null,
        success: true,
        confidence: finalTags.isNotEmpty
            ? confidenceByTag.values.reduce((a, b) => a + b) /
                confidenceByTag.length
            : 0.0,
        input: CategorizerInvocationInput(
          entityId: entity.uuid,
          entityType: entityType,
          content: content,
        ).toJson(),
        output: CategorizerInvocationOutput(
          tags: finalTags,
          confidenceByTag: Map.from(confidenceByTag)
            ..removeWhere((k, v) => !finalTags.contains(k)),
          autoApplied: finalTags.isNotEmpty,
        ).toJson(),
      ),
    );

    return finalTags;
  }

  /// Extract content from entity for categorization.
  /// Entities can implement a toCategorizableContent() method,
  /// or we fall back to toString().
  String _extractContent(BaseEntity entity) {
    // Try to call toCategorizableContent() if entity supports it
    try {
      final dynamic dynamicEntity = entity;
      if (dynamicEntity is dynamic &&
          dynamicEntity.toCategorizableContent != null) {
        return (dynamicEntity as dynamic).toCategorizableContent() as String;
      }
    } catch (e) {
      // Entity doesn't support toCategorizableContent, fall back
    }

    // Fall back to toString()
    return entity.toString();
  }

  /// Analyze content to extract tags with confidence scores.
  ///
  /// Current implementation: Simple keyword matching.
  /// Future: Use LLM for semantic categorization.
  Map<String, double> _analyzeContent({
    required String content,
    required String entityType,
    required CategorizerAdaptationData adaptationData,
  }) {
    final tagConfidences = <String, double>{};
    final contentLower = content.toLowerCase();

    // 1. Check preferred tags for this entity type
    final preferredTags =
        adaptationData.preferredTagsByEntityType[entityType] ?? [];
    for (final tag in preferredTags) {
      if (contentLower.contains(tag.toLowerCase())) {
        tagConfidences[tag] = 0.9; // High confidence for learned preferences
      }
    }

    // 2. Check custom taxonomy
    for (final entry in adaptationData.customTaxonomy.entries) {
      final category = entry.key;
      final tags = entry.value;
      for (final tag in tags) {
        if (contentLower.contains(tag.toLowerCase())) {
          tagConfidences[tag] = 0.8; // Medium-high confidence for user taxonomy
        }
      }
    }

    // 3. Default rule-based keywords
    final defaultKeywords = {
      'meeting': 0.7,
      'task': 0.7,
      'note': 0.7,
      'project': 0.7,
      'urgent': 0.8,
      'important': 0.8,
    };

    for (final entry in defaultKeywords.entries) {
      final keyword = entry.key;
      final confidence = entry.value;
      if (contentLower.contains(keyword) &&
          !tagConfidences.containsKey(keyword)) {
        tagConfidences[keyword] = confidence;
      }
    }

    return tagConfidences;
  }

  // ============ Trainable Implementation ============

  @override
  String get componentType => 'categorizer';

  @override
  CategorizerAdaptationData createDefaultData() =>
      CategorizerAdaptationData.defaults();

  @override
  CategorizerAdaptationData deserializeData(String json) =>
      CategorizerAdaptationData.fromJson(
          jsonDecode(json) as Map<String, dynamic>);

  @override
  Widget buildFeedbackUI(BuildContext context, Invocation invocation) {
    // Parse typed input/output from invocation
    final input = CategorizerInvocationInput.fromJson(invocation.input!);
    final output = CategorizerInvocationOutput.fromJson(invocation.output!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Categorized Entity:',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Type: ${input.entityType}'),
              Text('Tags: ${output.tags.join(", ")}'),
              const SizedBox(height: 8),
              ...output.tags.map((tag) => Text(
                    '$tag: ${(output.confidenceByTag[tag]! * 100).toStringAsFixed(0)}% confidence',
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Were tags appropriate?',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(
              onPressed: () {
                // TODO: Record feedback (tags were good)
              },
              child: const Text('Good'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                // TODO: Show tag adjustment UI
              },
              child: const Text('Adjust Tags'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> trainFromFeedback(
      Invocation invocation, core_feedback.Feedback feedback) async {
    // TODO: Implement training algorithm
    // 1. Parse typed feedback: user corrections to tags
    // 2. Get current AdaptationState for categorizer
    // 3. Update preferredTagsByEntityType based on feedback patterns
    // 4. Adjust autoTagThreshold if user frequently rejects tags
    // 5. Save updated AdaptationState
  }
}
