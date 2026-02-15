import 'dart:convert';
import '../../core/adaptation_data.dart';

/// Learned chunking preferences (trainable parameters).
///
/// Adaptive chunk sizes can be tuned based on:
/// - Entity type (Invocation vs Note vs Task)
/// - Content category (code vs prose vs conversation)
/// - User feedback on semantic search quality
class ChunkingAdaptationData extends AdaptationData {
  /// Target tokens for parent chunks (default: 200)
  /// Parent chunks provide high-level semantic context
  final int parentTargetTokens;

  /// Target tokens for child chunks (default: 25)
  /// Child chunks provide fine-grained semantic matches
  final int childTargetTokens;

  /// Category-specific chunk sizes
  /// Maps entity type → custom parent token count
  /// Example: {'Invocation': 150, 'Note': 250}
  final Map<String, int> categorySpecificSizes;

  ChunkingAdaptationData({
    required this.parentTargetTokens,
    required this.childTargetTokens,
    required this.categorySpecificSizes,
  });

  /// Default adaptation state (untrained).
  factory ChunkingAdaptationData.defaults() => ChunkingAdaptationData(
        parentTargetTokens: 200,
        childTargetTokens: 25,
        categorySpecificSizes: {},
      );

  /// Deserialize from JSON.
  factory ChunkingAdaptationData.fromJson(Map<String, dynamic> json) =>
      ChunkingAdaptationData(
        parentTargetTokens: json['parentTargetTokens'] as int? ?? 200,
        childTargetTokens: json['childTargetTokens'] as int? ?? 25,
        categorySpecificSizes: Map<String, int>.from(
          json['categorySpecificSizes'] as Map<String, dynamic>? ?? {},
        ),
      );

  /// Serialize to JSON string.
  @override
  String toJson() => jsonEncode({
        'parentTargetTokens': parentTargetTokens,
        'childTargetTokens': childTargetTokens,
        'categorySpecificSizes': categorySpecificSizes,
      });

  /// Get parent chunk size for a specific entity type.
  /// Falls back to default if no category-specific size exists.
  int getParentSizeForCategory(String entityType) {
    return categorySpecificSizes[entityType] ?? parentTargetTokens;
  }
}

/// Input to chunking operation (what entity was chunked).
class ChunkingInvocationInput {
  final String entityId;
  final String entityType;
  final String chunkableInput;
  final int inputTokenCount;

  ChunkingInvocationInput({
    required this.entityId,
    required this.entityType,
    required this.chunkableInput,
    required this.inputTokenCount,
  });

  Map<String, dynamic> toJson() => {
        'entityId': entityId,
        'entityType': entityType,
        'chunkableInput': chunkableInput,
        'inputTokenCount': inputTokenCount,
      };

  factory ChunkingInvocationInput.fromJson(Map<String, dynamic> json) =>
      ChunkingInvocationInput(
        entityId: json['entityId'] as String,
        entityType: json['entityType'] as String,
        chunkableInput: json['chunkableInput'] as String,
        inputTokenCount: json['inputTokenCount'] as int,
      );
}

/// Output from chunking operation (how many chunks created).
class ChunkingInvocationOutput {
  final int parentChunkCount;
  final int childChunkCount;
  final int totalChunks;
  final List<int> chunkSizesTokens;

  ChunkingInvocationOutput({
    required this.parentChunkCount,
    required this.childChunkCount,
    required this.totalChunks,
    required this.chunkSizesTokens,
  });

  Map<String, dynamic> toJson() => {
        'parentChunkCount': parentChunkCount,
        'childChunkCount': childChunkCount,
        'totalChunks': totalChunks,
        'chunkSizesTokens': chunkSizesTokens,
      };

  factory ChunkingInvocationOutput.fromJson(Map<String, dynamic> json) =>
      ChunkingInvocationOutput(
        parentChunkCount: json['parentChunkCount'] as int,
        childChunkCount: json['childChunkCount'] as int,
        totalChunks: json['totalChunks'] as int,
        chunkSizesTokens: List<int>.from(json['chunkSizesTokens'] as List),
      );
}
