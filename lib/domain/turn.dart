/// # Turn
///
/// ## What it does
/// Represents a single user interaction turn (one speech → audio cycle).
/// Links together all the invocations from that turn:
/// - STTInvocation (speech → text)
/// - ContextManagerInvocation (text → namespace/tool selection)
/// - LLMInvocation (context → response + tool calls)
/// - TTSInvocation (response → audio)
///
/// ## Turn Lifecycle
/// 1. User speaks (correlationId generated)
/// 2. STT processes audio → STTInvocation created
/// 3. ContextManager processes utterance → ContextManagerInvocation created
/// 4. LLM generates response → LLMInvocation created
/// 5. TTS synthesizes audio → TTSInvocation created
/// 6. Turn created, linking all 4 invocations
/// 7. User provides feedback (Feedback entities created)
/// 8. trainFromFeedback() called on each component
///
/// ## Feedback Loop
/// All feedback for a Turn has turnId = this Turn's uuid.
/// trainFromFeedback(turnId) pulls feedback from FeedbackRepository.
/// Each service (STT, ContextManager, LLM, TTS) trains independently.
///
/// ## Usage
/// ```dart
/// final turn = Turn(
///   correlationId: event.correlationId,
///   sttInvocationId: sttInv.uuid,
///   contextManagerInvocationId: cmInv.uuid,
///   llmInvocationId: llmInv.uuid,
///   ttsInvocationId: ttsInv.uuid,
///   result: 'success',
/// );
/// await turnRepo.save(turn);
///
/// // Later, after user provides feedback:
/// await sttService.trainFromFeedback(turn.uuid);
/// await contextManager.trainFromFeedback(turn.uuid);
/// await llmService.trainFromFeedback(turn.uuid);
/// await ttsService.trainFromFeedback(turn.uuid);
/// ```

import '../core/base_entity.dart';

class Turn extends BaseEntity {
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

  // ============ Turn identity ============

  /// Ties together all invocations from this turn
  /// Same as the Event.correlationId that triggered the turn
  String correlationId;

  /// When this turn occurred
  DateTime timestamp = DateTime.now();

  // ============ Invocation references ============

  /// The STT invocation that transcribed the audio
  /// FK to STTInvocation.uuid
  String? sttInvocationId;

  /// The ContextManager invocation that selected namespace/tools
  /// FK to ContextManagerInvocation.uuid
  String? contextManagerInvocationId;

  /// The LLM invocation that generated response
  /// FK to LLMInvocation.uuid
  String? llmInvocationId;

  /// The TTS invocation that synthesized audio
  /// FK to TTSInvocation.uuid
  String? ttsInvocationId;

  // ============ Outcome ============

  /// Did the turn succeed? 'success', 'error', 'partial'
  String result = 'success';

  /// Why did it fail? (if result != 'success')
  String? errorMessage;

  /// Which component failed? 'stt', 'context_manager', 'llm', 'tts'
  String? failureComponent;

  /// How long did the entire turn take (ms)
  int latencyMs = 0;

  /// Whether this turn is marked for user feedback review
  bool markedForFeedback = false;

  /// When this turn was marked for feedback
  DateTime? markedAt;

  /// When feedback was trained on this turn
  DateTime? feedbackTrainedAt;

  // ============ Constructor ============

  Turn({
    required this.correlationId,
    this.sttInvocationId,
    this.contextManagerInvocationId,
    this.llmInvocationId,
    this.ttsInvocationId,
    this.result = 'success',
    this.errorMessage,
    this.failureComponent,
    this.markedForFeedback = false,
    this.markedAt,
    this.feedbackTrainedAt,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Helpers ============

  /// Did all components succeed?
  bool get isSuccessful => result == 'success';

  /// How many invocations are linked to this turn?
  int get invocationCount {
    int count = 0;
    if (sttInvocationId != null) count++;
    if (contextManagerInvocationId != null) count++;
    if (llmInvocationId != null) count++;
    if (ttsInvocationId != null) count++;
    return count;
  }

  /// Get all invocation IDs
  List<String> getInvocationIds() {
    return [
      if (sttInvocationId != null) sttInvocationId!,
      if (contextManagerInvocationId != null) contextManagerInvocationId!,
      if (llmInvocationId != null) llmInvocationId!,
      if (ttsInvocationId != null) ttsInvocationId!,
    ];
  }

  // ============ Serialization ============

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncId': syncId,
      'correlationId': correlationId,
      'timestamp': timestamp.toIso8601String(),
      'sttInvocationId': sttInvocationId,
      'contextManagerInvocationId': contextManagerInvocationId,
      'llmInvocationId': llmInvocationId,
      'ttsInvocationId': ttsInvocationId,
      'result': result,
      'errorMessage': errorMessage,
      'failureComponent': failureComponent,
      'latencyMs': latencyMs,
      'markedForFeedback': markedForFeedback,
      'markedAt': markedAt?.toIso8601String(),
      'feedbackTrainedAt': feedbackTrainedAt?.toIso8601String(),
    };
  }

  factory Turn.fromJson(Map<String, dynamic> json) {
    return Turn(
      correlationId: json['correlationId'] as String,
      sttInvocationId: json['sttInvocationId'] as String?,
      contextManagerInvocationId: json['contextManagerInvocationId'] as String?,
      llmInvocationId: json['llmInvocationId'] as String?,
      ttsInvocationId: json['ttsInvocationId'] as String?,
      result: json['result'] as String? ?? 'success',
      errorMessage: json['errorMessage'] as String?,
      failureComponent: json['failureComponent'] as String?,
      markedForFeedback: json['markedForFeedback'] as bool? ?? false,
      markedAt: json['markedAt'] != null
          ? DateTime.parse(json['markedAt'] as String)
          : null,
      feedbackTrainedAt: json['feedbackTrainedAt'] != null
          ? DateTime.parse(json['feedbackTrainedAt'] as String)
          : null,
    )
      ..id = json['id'] as int? ?? 0
      ..uuid = json['uuid'] as String? ?? ''
      ..createdAt = json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now()
      ..updatedAt = json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now()
      ..syncId = json['syncId'] as String?
      ..timestamp = json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now()
      ..latencyMs = json['latencyMs'] as int? ?? 0;
  }

  /// Create a copy of this Turn with optional field overrides
  Turn copyWith({
    String? correlationId,
    String? sttInvocationId,
    String? contextManagerInvocationId,
    String? llmInvocationId,
    String? ttsInvocationId,
    String? result,
    String? errorMessage,
    String? failureComponent,
    int? latencyMs,
    bool? markedForFeedback,
    DateTime? markedAt,
    DateTime? feedbackTrainedAt,
  }) {
    return Turn(
      correlationId: correlationId ?? this.correlationId,
      sttInvocationId: sttInvocationId ?? this.sttInvocationId,
      contextManagerInvocationId:
          contextManagerInvocationId ?? this.contextManagerInvocationId,
      llmInvocationId: llmInvocationId ?? this.llmInvocationId,
      ttsInvocationId: ttsInvocationId ?? this.ttsInvocationId,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      failureComponent: failureComponent ?? this.failureComponent,
      markedForFeedback: markedForFeedback ?? this.markedForFeedback,
      markedAt: markedAt ?? this.markedAt,
      feedbackTrainedAt: feedbackTrainedAt ?? this.feedbackTrainedAt,
    )
      ..id = id
      ..uuid = uuid
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncId = syncId
      ..timestamp = timestamp
      ..latencyMs = latencyMs ?? this.latencyMs;
  }
}
