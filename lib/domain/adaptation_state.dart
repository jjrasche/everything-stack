/// # Adaptation State
///
/// ## What it does
/// Stores tunable parameters for each component.
/// Learned from user feedback during training phases.
/// Supports multi-scope learning: global baseline → user-specific personalization
///
/// ## Scope
/// - 'global': Shared baseline for all users
/// - 'user': Personalized state for specific user
/// - 'device': (Future) Per-device personalization
///
/// ## Query precedence
/// When getting current state for a user:
/// 1. Check user-scoped state
/// 2. Fall back to global state
/// 3. Create default if neither exists
///
/// ## Version tracking
/// - version: Incremented on each update (optimistic locking)
/// - lastUpdatedAt: When state was last modified
/// - lastUpdateReason: Why it was updated (for audit trail)
///
/// ## Usage
/// ```dart
/// // Global baseline
/// final global = await stateRepo.getCurrent();
///
/// // User-specific
/// final user = await stateRepo.getCurrent(userId: 'user_123');
/// ```

import '../core/base_entity.dart';

// ============ STT Adaptation State ============

class STTAdaptationState extends BaseEntity {
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

  // ============ Scope fields ============

  /// Whose state is this? 'global', 'user', 'device'
  String scope;

  /// User ID (null if global scope)
  String? userId;

  /// Device ID (null if not device-scoped)
  String? deviceId;

  // ============ STT tunable parameters ============

  /// Minimum confidence to accept transcription (0.0-1.0)
  /// Learned from: feedback on low-confidence transcriptions
  double confidenceThreshold = 0.65;

  /// Minimum feedback count before updating state
  /// Prevents overtraining on small sample
  int minFeedbackCount = 10;

  // ============ Version & audit trail ============

  /// Version for optimistic locking
  /// Increment on each update to prevent race conditions
  int version = 0;

  /// When this state was last updated
  DateTime lastUpdatedAt = DateTime.now();

  /// Why was it updated? ('trainFromFeedback', 'manual', etc.)
  String lastUpdateReason = '';

  /// How many feedback records were used to compute this state?
  int feedbackCountApplied = 0;

  // ============ Constructor ============

  STTAdaptationState({
    required this.scope,
    this.userId,
    this.deviceId,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'uuid': uuid,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'syncId': syncId,
    'scope': scope,
    'userId': userId,
    'deviceId': deviceId,
    'confidenceThreshold': confidenceThreshold,
    'minFeedbackCount': minFeedbackCount,
    'version': version,
    'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
    'lastUpdateReason': lastUpdateReason,
    'feedbackCountApplied': feedbackCountApplied,
  };

  factory STTAdaptationState.fromJson(Map<String, dynamic> json) {
    final state = STTAdaptationState(
      scope: json['scope'] as String,
      userId: json['userId'] as String?,
      deviceId: json['deviceId'] as String?,
    );
    state.id = json['id'] as int? ?? 0;
    state.uuid = json['uuid'] as String? ?? '';
    state.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    state.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    state.syncId = json['syncId'] as String?;
    state.confidenceThreshold = json['confidenceThreshold'] as double? ?? 0.65;
    state.minFeedbackCount = json['minFeedbackCount'] as int? ?? 10;
    state.version = json['version'] as int? ?? 0;
    state.lastUpdatedAt = json['lastUpdatedAt'] != null
        ? DateTime.parse(json['lastUpdatedAt'] as String)
        : DateTime.now();
    state.lastUpdateReason = json['lastUpdateReason'] as String? ?? '';
    state.feedbackCountApplied = json['feedbackCountApplied'] as int? ?? 0;
    return state;
  }
}

// ============ LLM Adaptation State ============

class LLMAdaptationState extends BaseEntity {
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

  String scope;
  String? userId;
  String? deviceId;

  // ============ LLM tunable parameters ============

  /// Which system prompt variant to use
  /// Allows A/B testing different prompt strategies
  String systemPromptVariant = 'default';

  /// LLM temperature (0.0-1.0)
  /// Lower = deterministic, Higher = creative
  /// Learned from: user corrections to responses
  double temperature = 0.7;

  /// Maximum tokens per response
  /// Learned from: feedback on truncated responses
  int maxTokens = 2048;

  // ============ Version & audit trail ============

  int version = 0;
  DateTime lastUpdatedAt = DateTime.now();
  String lastUpdateReason = '';
  int feedbackCountApplied = 0;

  LLMAdaptationState({
    required this.scope,
    this.userId,
    this.deviceId,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'uuid': uuid,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'syncId': syncId,
    'scope': scope,
    'userId': userId,
    'deviceId': deviceId,
    'systemPromptVariant': systemPromptVariant,
    'temperature': temperature,
    'maxTokens': maxTokens,
    'version': version,
    'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
    'lastUpdateReason': lastUpdateReason,
    'feedbackCountApplied': feedbackCountApplied,
  };

  factory LLMAdaptationState.fromJson(Map<String, dynamic> json) {
    final state = LLMAdaptationState(
      scope: json['scope'] as String,
      userId: json['userId'] as String?,
      deviceId: json['deviceId'] as String?,
    );
    state.id = json['id'] as int? ?? 0;
    state.uuid = json['uuid'] as String? ?? '';
    state.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    state.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    state.syncId = json['syncId'] as String?;
    state.systemPromptVariant =
        json['systemPromptVariant'] as String? ?? 'default';
    state.temperature = json['temperature'] as double? ?? 0.7;
    state.maxTokens = json['maxTokens'] as int? ?? 2048;
    state.version = json['version'] as int? ?? 0;
    state.lastUpdatedAt = json['lastUpdatedAt'] != null
        ? DateTime.parse(json['lastUpdatedAt'] as String)
        : DateTime.now();
    state.lastUpdateReason = json['lastUpdateReason'] as String? ?? '';
    state.feedbackCountApplied = json['feedbackCountApplied'] as int? ?? 0;
    return state;
  }
}

// ============ TTS Adaptation State ============

class TTSAdaptationState extends BaseEntity {
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

  String scope;
  String? userId;
  String? deviceId;

  // ============ TTS tunable parameters ============

  /// Voice to use
  /// Learned from: user preferences in feedback
  String voiceId = 'default';

  /// Speech rate (0.5 - 2.0, where 1.0 is normal)
  /// Learned from: feedback on speech clarity
  double speechRate = 1.0;

  // ============ Version & audit trail ============

  int version = 0;
  DateTime lastUpdatedAt = DateTime.now();
  String lastUpdateReason = '';
  int feedbackCountApplied = 0;

  TTSAdaptationState({
    required this.scope,
    this.userId,
    this.deviceId,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'uuid': uuid,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'syncId': syncId,
    'scope': scope,
    'userId': userId,
    'deviceId': deviceId,
    'voiceId': voiceId,
    'speechRate': speechRate,
    'version': version,
    'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
    'lastUpdateReason': lastUpdateReason,
    'feedbackCountApplied': feedbackCountApplied,
  };

  factory TTSAdaptationState.fromJson(Map<String, dynamic> json) {
    final state = TTSAdaptationState(
      scope: json['scope'] as String,
      userId: json['userId'] as String?,
      deviceId: json['deviceId'] as String?,
    );
    state.id = json['id'] as int? ?? 0;
    state.uuid = json['uuid'] as String? ?? '';
    state.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    state.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    state.syncId = json['syncId'] as String?;
    state.voiceId = json['voiceId'] as String? ?? 'default';
    state.speechRate = json['speechRate'] as double? ?? 1.0;
    state.version = json['version'] as int? ?? 0;
    state.lastUpdatedAt = json['lastUpdatedAt'] != null
        ? DateTime.parse(json['lastUpdatedAt'] as String)
        : DateTime.now();
    state.lastUpdateReason = json['lastUpdateReason'] as String? ?? '';
    state.feedbackCountApplied = json['feedbackCountApplied'] as int? ?? 0;
    return state;
  }
}
