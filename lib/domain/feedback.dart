/// # Feedback
///
/// ## What it does
/// Records user feedback on component invocations.
/// Links invocations to user corrections/confirmations.
/// Used for training components to improve.
///
/// ## Actions
/// - confirm: User says output was correct
/// - deny: User says output was wrong (but didn't provide correction)
/// - correct: User corrected the output (correctedData contains correction)
/// - ignore: Don't learn from this invocation (test, sensitive, etc.)
///
/// ## Turn Context
/// - turnId: Optional. If set, feedback is part of conversational context.
///           If null, feedback is for background/retry/test invocations.
/// - Component learns only from conversational feedback (turnId != null)
/// - Background feedback can be learned separately if desired
///
/// ## Usage
/// ```dart
/// // User corrects STT transcription
/// final feedback = Feedback(
///   invocationId: 'stt_inv_001',
///   turnId: 'turn_5',
///   componentType: 'stt',
///   action: FeedbackAction.correct,
///   correctedData: 'corrected text',
/// );
/// await feedbackRepo.save(feedback);
/// ```

import 'package:json_annotation/json_annotation.dart';
import '../core/base_entity.dart';

part 'feedback.g.dart';

/// Actions user can take on an invocation
enum FeedbackAction {
  /// User confirms the invocation was correct
  confirm,

  /// User says it was wrong but didn't provide correction
  deny,

  /// User corrected the invocation (correctedData contains the correction)
  correct,

  /// Don't learn from this invocation (test case, sensitive data, etc.)
  ignore,
}

@JsonSerializable()
class Feedback extends BaseEntity {
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

  // ============ Feedback fields ============

  /// Which invocation does this feedback apply to?
  /// FK to (sttInvocation.id, intentInvocation.id, etc.)
  String invocationId;

  /// Which component? ('stt', 'intent', 'llm', 'tts')
  String componentType;

  /// Which turn is this feedback for? (null if background/retry/test)
  /// If set, feedback applies to conversational context
  /// If null, feedback is for background/retry/test invocations
  String? turnId;

  /// What action did user take?
  @JsonKey(unknownEnumValue: FeedbackAction.ignore)
  FeedbackAction action;

  /// Component-specific correction (only populated if action == 'correct')
  /// STT: corrected transcription (string)
  /// Intent: corrected slots as JSON
  /// LLM: corrected response (string)
  /// TTS: null (can't realistically correct audio)
  String? correctedData;

  /// Why did user provide this feedback?
  /// Optional. Helps with debugging and learning.
  String? reason;

  /// When user provided this feedback
  DateTime timestamp = DateTime.now();

  // ============ Constructor ============

  Feedback({
    required this.invocationId,
    required this.componentType,
    required this.action,
    this.turnId,
    this.correctedData,
    this.reason,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Helpers ============

  /// Is this feedback part of a conversation turn?
  bool get isConversational => turnId != null;

  /// Is this feedback for a background/retry/test invocation?
  bool get isBackground => turnId == null;

  /// Did user provide a correction?
  bool get hasCorrection =>
      action == FeedbackAction.correct && correctedData != null;

  // ============ JSON Serialization ============

  Map<String, dynamic> toJson() => _$FeedbackToJson(this);
  factory Feedback.fromJson(Map<String, dynamic> json) =>
      _$FeedbackFromJson(json);
}
