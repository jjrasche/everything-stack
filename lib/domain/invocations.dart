/// # Invocations
///
/// ## What they do
/// Each invocation represents a component's execution:
/// - STTInvocation: speech → transcription
/// - IntentInvocation: transcription → structured intent
/// - LLMInvocation: context + intent → response
/// - TTSInvocation: response → audio
///
/// ## Key Design
/// - Invocations are independent. Optionally tied to Turn via Turn.invocationIds
/// - contextType determines context: 'conversation' (part of turn), 'retry', 'background', 'test'
/// - retryCount tracks how many times component retried (0 = first try)
/// - Invocations can exist outside Turn (background tasks, testing)
///
/// ## Turn Mapping
/// Turn.sttInvocationId = the final STT invocation (successful or last attempt)
/// Turn.intentInvocationId = the final Intent invocation
/// ... etc
///
/// Retries are stored separately with contextType='retry'

import '../core/base_entity.dart';

// ============ Base Invocation ============
// Not a separate entity, but abstract contract for all invocations

abstract class BaseInvocation extends BaseEntity {
  /// Which component created this? 'stt', 'intent', 'llm', 'tts'
  String componentType;

  /// Execution context: 'conversation' (part of turn), 'retry', 'background', 'test'
  String contextType = 'conversation';

  /// How many retries did this component make? (0 = first try, 1 = second try, etc.)
  int retryCount = 0;

  /// Why did it retry (if retryCount > 0)?
  String? lastError;

  /// When this invocation occurred
  DateTime timestamp = DateTime.now();

  BaseInvocation({required this.componentType});
}

// ============ STT Invocation ============

class STTInvocation extends BaseEntity {
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

  // ============ Invocation fields ============

  /// Identifies this as STT component
  final String componentType = 'stt';

  /// Execution context: 'conversation', 'retry', 'background', 'test'
  String contextType = 'conversation';

  /// Which audio was transcribed
  String audioId;

  /// Transcribed text output
  String output;

  /// How confident is STT in this transcription (0.0-1.0)
  double confidence;

  /// How many times did STT retry? (0 = first try)
  int retryCount = 0;

  /// Why did it retry?
  String? lastError;

  /// When this invocation occurred
  DateTime timestamp = DateTime.now();

  STTInvocation({
    required this.audioId,
    required this.output,
    required this.confidence,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  Map<String, dynamic> toJson() => {
        'componentType': componentType,
        'contextType': contextType,
        'audioId': audioId,
        'output': output,
        'confidence': confidence,
        'retryCount': retryCount,
        'lastError': lastError,
        'timestamp': timestamp.toIso8601String(),
      };

  factory STTInvocation.fromJson(Map<String, dynamic> json) => STTInvocation(
        audioId: json['audioId'] as String,
        output: json['output'] as String,
        confidence: json['confidence'] as double,
      )
        ..contextType = json['contextType'] as String? ?? 'conversation'
        ..retryCount = json['retryCount'] as int? ?? 0
        ..lastError = json['lastError'] as String?
        ..timestamp = json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now();
}

// ============ Intent Invocation ============

class IntentInvocation extends BaseEntity {
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

  // ============ Invocation fields ============

  final String componentType = 'intent';

  String contextType = 'conversation';

  /// Which transcription was classified
  String transcription;

  /// Which tool was selected (empty = conversational, no tool)
  String toolName;

  /// Filled slots as JSON string
  /// {"slotName": value, ...}
  String slotsJson;

  /// How confident is Intent in this classification (0.0-1.0)
  double confidence;

  /// How many times did Intent retry?
  int retryCount = 0;

  String? lastError;

  DateTime timestamp = DateTime.now();

  IntentInvocation({
    required this.transcription,
    required this.toolName,
    required this.slotsJson,
    required this.confidence,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  Map<String, dynamic> toJson() => {
        'componentType': componentType,
        'contextType': contextType,
        'transcription': transcription,
        'toolName': toolName,
        'slotsJson': slotsJson,
        'confidence': confidence,
        'retryCount': retryCount,
        'lastError': lastError,
        'timestamp': timestamp.toIso8601String(),
      };

  factory IntentInvocation.fromJson(Map<String, dynamic> json) =>
      IntentInvocation(
        transcription: json['transcription'] as String,
        toolName: json['toolName'] as String,
        slotsJson: json['slotsJson'] as String,
        confidence: json['confidence'] as double,
      )
        ..contextType = json['contextType'] as String? ?? 'conversation'
        ..retryCount = json['retryCount'] as int? ?? 0
        ..lastError = json['lastError'] as String?
        ..timestamp = json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now();
}

// ============ LLM Invocation ============

class LLMInvocation extends BaseEntity {
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

  // ============ Invocation fields ============

  final String componentType = 'llm';

  String contextType = 'conversation';

  /// Which prompt template was used (e.g., 'v1.2.3')
  /// Allows re-creating the exact prompt structure later
  String systemPromptVersion;

  /// How many previous turns were included in this prompt
  /// Used to reconstruct conversation history
  int conversationHistoryLength;

  /// The LLM response
  String response;

  /// How many tokens were used (input + output)
  int tokenCount;

  /// Why did LLM stop? ('stop', 'max_tokens', 'length', etc.)
  String stopReason = '';

  /// How many times did LLM retry?
  int retryCount = 0;

  String? lastError;

  DateTime timestamp = DateTime.now();

  LLMInvocation({
    required this.systemPromptVersion,
    required this.conversationHistoryLength,
    required this.response,
    required this.tokenCount,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  Map<String, dynamic> toJson() => {
        'componentType': componentType,
        'contextType': contextType,
        'systemPromptVersion': systemPromptVersion,
        'conversationHistoryLength': conversationHistoryLength,
        'response': response,
        'tokenCount': tokenCount,
        'stopReason': stopReason,
        'retryCount': retryCount,
        'lastError': lastError,
        'timestamp': timestamp.toIso8601String(),
      };

  factory LLMInvocation.fromJson(Map<String, dynamic> json) => LLMInvocation(
        systemPromptVersion: json['systemPromptVersion'] as String,
        conversationHistoryLength: json['conversationHistoryLength'] as int,
        response: json['response'] as String,
        tokenCount: json['tokenCount'] as int,
      )
        ..contextType = json['contextType'] as String? ?? 'conversation'
        ..stopReason = json['stopReason'] as String? ?? ''
        ..retryCount = json['retryCount'] as int? ?? 0
        ..lastError = json['lastError'] as String?
        ..timestamp = json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now();
}

// ============ TTS Invocation ============

class TTSInvocation extends BaseEntity {
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

  // ============ Invocation fields ============

  final String componentType = 'tts';

  String contextType = 'conversation';

  /// Text that was synthesized
  String text;

  /// Resulting audio ID (reference to BlobStore)
  String audioId;

  /// How many times did TTS retry?
  int retryCount = 0;

  String? lastError;

  DateTime timestamp = DateTime.now();

  TTSInvocation({
    required this.text,
    required this.audioId,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  Map<String, dynamic> toJson() => {
        'componentType': componentType,
        'contextType': contextType,
        'text': text,
        'audioId': audioId,
        'retryCount': retryCount,
        'lastError': lastError,
        'timestamp': timestamp.toIso8601String(),
      };

  factory TTSInvocation.fromJson(Map<String, dynamic> json) => TTSInvocation(
        text: json['text'] as String,
        audioId: json['audioId'] as String,
      )
        ..contextType = json['contextType'] as String? ?? 'conversation'
        ..retryCount = json['retryCount'] as int? ?? 0
        ..lastError = json['lastError'] as String?
        ..timestamp = json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now();
}
