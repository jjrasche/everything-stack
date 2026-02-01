/// # Invocation
///
/// ## What it does
/// Generic record of a component's execution.
/// Used by all trainable components to log their inputs, outputs, and results.
///
/// ## Standardized Fields
/// Every invocation has these fields:
/// - eventId: Links to the triggering event
/// - componentType: Which component executed ('stt', 'llm', 'tts', 'context_selector', etc.)
/// - implementer: Which implementation executed this (e.g., 'groq', 'deepgram', 'flutter_tts'). Null for single-implementation components.
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
///   eventId: event.id,
///   componentType: 'stt',
///   implementer: 'deepgram',
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
import 'package:everything_stack_template/patterns/semantic_indexable.dart';
import 'package:everything_stack_template/patterns/ownable.dart';
import 'package:everything_stack_template/patterns/enrichable.dart';

import 'base_entity.dart';

class Invocation extends BaseEntity
    with Embeddable, SemanticIndexable, Ownable
    implements Enrichable {
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
  String eventId;

  /// Which component executed this invocation?
  /// Examples: 'stt', 'llm', 'tts', 'context_selector', 'tool_executor'
  String componentType;

  /// Which implementer executed this invocation?
  /// Examples: 'groq', 'claude', 'deepgram', 'flutter_tts'
  /// Null for single-implementation components (tool_selector, namespace_selector)
  String? implementer;

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
    required this.eventId,
    required this.componentType,
    required this.success,
    required this.confidence,
    this.implementer,
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
        'eventId': eventId,
        'componentType': componentType,
        'implementer': implementer,
        'success': success,
        'confidence': confidence,
        'input': input,
        'output': output,
        'metadata': metadata,
      };

  factory Invocation.fromJson(Map<String, dynamic> json) {
    final inv = Invocation(
      eventId: json['eventId'] as String,
      componentType: json['componentType'] as String,
      success: json['success'] as bool,
      confidence: (json['confidence'] as num).toDouble(),
      implementer: json['implementer'] as String?,
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

  // ============ SemanticIndexable Implementation ============

  /// Extract chunkable input for semantic chunking and indexing.
  /// Concatenates the conversational content for two-level chunking.
  @override
  String toChunkableInput() {
    if (output == null || output!.isEmpty) return '';

    // STT: User input
    if (componentType == 'stt') {
      final transcription = output!['transcription'] as String? ?? '';
      return 'User: $transcription';
    }

    // LLM: User prompt + Assistant response
    // This captures the full conversation turn for semantic search
    // (essential for imported conversations from ChatGPT, Claude.ai, etc.)
    if (componentType == 'llm') {
      final prompt = input?['prompt'] as String? ?? '';
      final response = output!['response'] as String? ?? '';
      if (prompt.isNotEmpty) {
        return 'User: $prompt\nAssistant: $response';
      }
      return 'Assistant: $response';
    }

    // Other components: no chunking
    return '';
  }

  /// Return chunking configuration level for this invocation.
  ///
  /// LLM invocations use 'invocation' config for whole-unit chunks.
  /// This enables VoiceTraits to retrieve complete conversation examples.
  /// Other invocation types use 'child' for fine-grained semantic units.
  @override
  String getChunkingConfig() {
    if (componentType == 'llm') {
      return 'invocation';
    }
    return 'child';
  }

  // ============ Enrichable Implementation ============

  /// Declare enrichment steps for async processing.
  /// Invocations need semantic enrichment (chunking + embedding + HNSW).
  @override
  List<String> get enrichmentSteps => ['semantic_enrichment'];
}
