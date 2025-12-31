/// # Invocation
///
/// ## What it does
/// Generic record of a component's execution.
/// Used by all trainable components to log their inputs, outputs, and results.
///
/// ## Standardized Fields
/// Every invocation has these fields:
/// - correlationId: Links to the triggering event/turn
/// - componentType: Which component executed ('stt', 'llm', 'tts', 'context_manager', 'namespace_selector', etc.)
/// - success: Did the component succeed?
/// - confidence: How confident was the component (0.0-1.0)?
/// - createdAt: When did this happen?
///
/// ## Generic Data Fields
/// - input: Component-specific input as JSON
/// - output: Component-specific output as JSON
/// - metadata: Optional additional data
///
/// ## Usage
/// ```dart
/// final invocation = Invocation(
///   correlationId: event.correlationId,
///   componentType: 'stt',
///   success: true,
///   confidence: 0.95,
///   input: {'audioId': 'audio_123'},
///   output: {'transcription': 'hello world'},
/// );
/// await invocationRepo.save(invocation);
/// ```
///
/// ## Training Flow
/// 1. Component executes, creates Invocation with input/output
/// 2. User provides Feedback on the Invocation
/// 3. Trainer uses Invocation + Feedback to update AdaptationState

import 'dart:convert';
import 'package:everything_stack_template/patterns/embeddable.dart';

import '../core/base_entity.dart';

class Invocation extends BaseEntity with Embeddable {
  // ============ BaseEntity field overrides ============
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

  // ============ Standardized Invocation Fields ============

  /// Links to the triggering event or turn (for conversation context)
  String correlationId;

  /// Which component executed this invocation?
  /// Examples: 'stt', 'llm', 'tts', 'context_manager', 'namespace_selector', 'tool_selector'
  String componentType;

  /// FK to Turn - links invocation to conversation turn (null for background/test invocations)
  String? turnId;

  /// Did the component succeed?
  bool success;

  /// How confident was the component? (0.0-1.0)
  /// For components without confidence, use 1.0 if success=true, 0.0 if success=false
  double confidence;

  // ============ Generic Data Fields (JSON storage) ============

  /// Component-specific input data (stored as JSON)

  Map<String, dynamic>? input;

  /// JSON string storage for input
  String? inputJson;

  /// Component-specific output data (stored as JSON)

  Map<String, dynamic>? output;

  /// JSON string storage for output
  String? outputJson;

  /// Optional additional metadata (stored as JSON)

  Map<String, dynamic>? metadata;

  /// JSON string storage for metadata
  String? metadataJson;

  // ============ Constructor ============

  Invocation({
    required this.correlationId,
    required this.componentType,
    required this.success,
    required this.confidence,
    this.turnId,
    this.input,
    this.output,
    this.metadata,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
    // Serialize input/output maps to JSON strings for ObjectBox storage
    if (input != null && inputJson == null) {
      inputJson = jsonEncode(input);
    }
    if (output != null && outputJson == null) {
      outputJson = jsonEncode(output);
    }
    if (metadata != null && metadataJson == null) {
      metadataJson = jsonEncode(metadata);
    }
  }

  /// Ensure JSON fields are populated from Map fields before saving
  void ensureSerialized() {
    if (input != null && inputJson == null) {
      inputJson = jsonEncode(input);
    }
    if (output != null && outputJson == null) {
      outputJson = jsonEncode(output);
    }
    if (metadata != null && metadataJson == null) {
      metadataJson = jsonEncode(metadata);
    }
  }

  // ============ Serialization Helpers ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'correlationId': correlationId,
        'componentType': componentType,
        'turnId': turnId,
        'success': success,
        'confidence': confidence,
        'input': input,
        'output': output,
        'metadata': metadata,
      };

  factory Invocation.fromJson(Map<String, dynamic> json) {
    final inv = Invocation(
      correlationId: json['correlationId'] as String,
      componentType: json['componentType'] as String,
      success: json['success'] as bool,
      confidence: (json['confidence'] as num).toDouble(),
      turnId: json['turnId'] as String?,
      input: json['input'] != null
          ? Map<String, dynamic>.from(json['input'] as Map)
          : null,
      output: json['output'] != null
          ? Map<String, dynamic>.from(json['output'] as Map)
          : null,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
    );
    inv.id = json['id'] as int? ?? 0;
    inv.uuid = json['uuid'] as String? ?? '';
    inv.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    inv.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    inv.syncId = json['syncId'] as String?;
    return inv;
  }

  // ============ Embeddable Implementation ============

  /// Extract embeddable text for semantic search.
  /// Returns component output text for STT/LLM, empty for others.
  @override
  String toEmbeddingInput() {
    if (output == null || output!.isEmpty) return '';

    // STT: return transcription
    if (componentType == 'stt') {
      return output!['transcription'] as String? ?? '';
    }

    // LLM: return response text
    if (componentType == 'llm') {
      return output!['response'] as String? ?? '';
    }

    // Other components: no embedding
    return '';
  }
}
