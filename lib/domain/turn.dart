/// # Turn
///
/// ## What it does
/// Represents one user utterance cycle in a conversation.
/// Groups the invocations that occurred as part of this turn:
/// STT (user input) → Intent (classification) → LLM (response) → TTS (audio)
///
/// ## Key Design
/// - Each component has a single invocationId (the final/successful attempt)
/// - Retries are separate records with contextType='retry'
/// - Turn doesn't store turnId—it IS identified by conversationId + turnIndex
/// - markedForFeedback allows users to flag turns for review
///
/// ## Usage
/// ```dart
/// final turn = Turn(
///   conversationId: 'conv_123',
///   turnIndex: 5,
/// );
///
/// turn.sttInvocationId = 'stt_inv_001';
/// turn.intentInvocationId = 'intent_inv_001';
/// await turnRepo.save(turn);
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

  // ============ Turn fields ============

  /// Which conversation does this turn belong to?
  String conversationId;

  /// Sequential index within the conversation (0-indexed)
  /// Allows reconstruction of conversation flow
  int turnIndex;

  /// When this turn occurred
  DateTime timestamp = DateTime.now();

  /// User marked this turn for feedback/review
  bool markedForFeedback = false;

  /// When user marked it (null if not marked)
  DateTime? markedAt;

  /// When this turn was last trained on feedback (null if never trained)
  DateTime? feedbackTrainedAt;

  // ============ Component Invocation Mapping ============
  /// RULE: Each field stores the FINAL invocation ID for that component
  /// Final = successful attempt, or last attempt before giving up
  /// Retries are separate records with contextType='retry'

  /// STT invocation (speech → transcription)
  String? sttInvocationId;

  /// Intent invocation (transcription → tool classification)
  String? intentInvocationId;

  /// LLM invocation (context + history → response)
  String? llmInvocationId;

  /// TTS invocation (response → audio)
  String? ttsInvocationId;

  // ============ Constructor ============

  Turn({
    required this.conversationId,
    required this.turnIndex,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Helpers ============

  /// Get all invocation IDs that exist for this turn
  /// Used for querying all invocations at once
  List<String> getExistingInvocationIds() => [
        sttInvocationId,
        intentInvocationId,
        llmInvocationId,
        ttsInvocationId,
      ].whereType<String>().toList();

  /// Check if all components ran successfully
  bool get isComplete =>
      sttInvocationId != null &&
      intentInvocationId != null &&
      llmInvocationId != null &&
      ttsInvocationId != null;

  /// Check if turn has any invocations yet
  bool get hasInvocations => getExistingInvocationIds().isNotEmpty;

  // ============ Copy Constructor ============

  /// Create a copy of this turn with selected fields replaced
  Turn copyWith({
    String? conversationId,
    int? turnIndex,
    DateTime? timestamp,
    bool? markedForFeedback,
    DateTime? markedAt,
    DateTime? feedbackTrainedAt,
    String? sttInvocationId,
    String? intentInvocationId,
    String? llmInvocationId,
    String? ttsInvocationId,
  }) {
    final copy = Turn(
      conversationId: conversationId ?? this.conversationId,
      turnIndex: turnIndex ?? this.turnIndex,
    );
    copy.id = id;
    copy.uuid = uuid;
    copy.createdAt = createdAt;
    copy.updatedAt = DateTime.now();
    copy.syncId = syncId;
    copy.timestamp = timestamp ?? this.timestamp;
    copy.markedForFeedback = markedForFeedback ?? this.markedForFeedback;
    copy.markedAt = markedAt ?? this.markedAt;
    copy.feedbackTrainedAt = feedbackTrainedAt ?? this.feedbackTrainedAt;
    copy.sttInvocationId = sttInvocationId ?? this.sttInvocationId;
    copy.intentInvocationId = intentInvocationId ?? this.intentInvocationId;
    copy.llmInvocationId = llmInvocationId ?? this.llmInvocationId;
    copy.ttsInvocationId = ttsInvocationId ?? this.ttsInvocationId;
    return copy;
  }

  // ============ JSON Serialization ============

  Map<String, dynamic> toJson() => {
    'id': id,
    'uuid': uuid,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'syncId': syncId,
    'conversationId': conversationId,
    'turnIndex': turnIndex,
    'timestamp': timestamp.toIso8601String(),
    'markedForFeedback': markedForFeedback,
    'markedAt': markedAt?.toIso8601String(),
    'feedbackTrainedAt': feedbackTrainedAt?.toIso8601String(),
    'sttInvocationId': sttInvocationId,
    'intentInvocationId': intentInvocationId,
    'llmInvocationId': llmInvocationId,
    'ttsInvocationId': ttsInvocationId,
  };

  factory Turn.fromJson(Map<String, dynamic> json) {
    final turn = Turn(
      conversationId: json['conversationId'] as String,
      turnIndex: json['turnIndex'] as int,
    );
    turn.id = json['id'] as int? ?? 0;
    turn.uuid = json['uuid'] as String? ?? '';
    turn.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    turn.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    turn.syncId = json['syncId'] as String?;
    turn.timestamp = json['timestamp'] != null
        ? DateTime.parse(json['timestamp'] as String)
        : DateTime.now();
    turn.markedForFeedback = json['markedForFeedback'] as bool? ?? false;
    turn.markedAt = json['markedAt'] != null
        ? DateTime.parse(json['markedAt'] as String)
        : null;
    turn.feedbackTrainedAt = json['feedbackTrainedAt'] != null
        ? DateTime.parse(json['feedbackTrainedAt'] as String)
        : null;
    turn.sttInvocationId = json['sttInvocationId'] as String?;
    turn.intentInvocationId = json['intentInvocationId'] as String?;
    turn.llmInvocationId = json['llmInvocationId'] as String?;
    turn.ttsInvocationId = json['ttsInvocationId'] as String?;
    return turn;
  }
}
