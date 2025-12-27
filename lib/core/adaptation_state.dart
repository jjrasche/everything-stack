/// # Adaptation State (Generic)
///
/// ## What it does
/// Stores learned parameters for any trainable component.
/// A single entity replaces component-specific adaptation states.
///
/// ## Scope
/// Currently single-user (no user scoping yet).
/// Will add userId via mixin later if needed.
///
/// ## Generic Data Storage
/// - data: Component-specific parameters as JSON
///   - For STT: { confidenceThreshold: 0.65, minFeedbackCount: 10 }
///   - For LLM: { temperature: 0.7, maxTokens: 2048, systemPromptVariant: 'default' }
///   - For TTS: { voiceId: 'default', speechRate: 1.0 }
///   - For ContextManager: { namespaceAttention: {...}, toolAttention: {...} }
///
/// ## Version Tracking
/// - version: Incremented on each update (optimistic locking)
/// - lastUpdatedAt: When state was last modified
/// - lastUpdateReason: Why it was updated (for audit trail)
/// - feedbackCountApplied: How many feedback records went into this state?
///
/// ## Usage
/// ```dart
/// // Get or create STT adaptation state
/// final state = await stateRepo.findByComponentType('stt') ??
///   AdaptationState(componentType: 'stt', data: {
///     'confidenceThreshold': 0.65,
///     'minFeedbackCount': 10,
///   });
///
/// // Train it
/// state.data['confidenceThreshold'] = 0.72;
/// state.version++;
/// state.lastUpdatedAt = DateTime.now();
/// state.lastUpdateReason = 'trainFromFeedback';
/// await stateRepo.save(state);
/// ```

import 'dart:convert';
import 'base_entity.dart';

class AdaptationState extends BaseEntity {
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

  // ============ Identity & Scoping ============

  /// Which component does this state belong to?
  /// Examples: 'stt', 'llm', 'tts', 'namespace_selector', 'tool_selector'
  String componentType;

  /// Scope of the adaptation state: 'global' or 'user'
  /// 'global': Applies to all users
  /// 'user': Personalized to a specific user (see userId)
  String scope = 'global';

  /// If scope='user', this is the user ID for personalized adaptation
  /// If scope='global', this is null
  String? userId;

  // ============ Learned Parameters (Generic JSON) ============

  /// Component-specific learned parameters
  Map<String, dynamic> data = {};

  /// JSON string storage for data
  String dataJson = '{}';

  // ============ Version & Audit Trail ============

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

  AdaptationState({
    required this.componentType,
    this.scope = 'global',
    this.userId,
    Map<String, dynamic>? data,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
    if (data != null) {
      this.data = data;
      _saveData();
    }
  }

  // ============ Lifecycle Helpers ============

  /// Load data from JSON before use
  void loadData() {
    if (dataJson.isNotEmpty && dataJson != '{}') {
      try {
        data = jsonDecode(dataJson) as Map<String, dynamic>? ?? {};
      } catch (e) {
        // If JSON parse fails, keep current data
      }
    }
  }

  /// Save data to JSON before persisting
  void saveData() {
    _saveData();
  }

  void _saveData() {
    dataJson = jsonEncode(data);
    touch();
  }

  // ============ Serialization ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'componentType': componentType,
        'scope': scope,
        'userId': userId,
        'data': data,
        'version': version,
        'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
        'lastUpdateReason': lastUpdateReason,
        'feedbackCountApplied': feedbackCountApplied,
      };

  factory AdaptationState.fromJson(Map<String, dynamic> json) {
    final state = AdaptationState(
      componentType: json['componentType'] as String,
      scope: json['scope'] as String? ?? 'global',
      userId: json['userId'] as String?,
      data: json['data'] != null
          ? Map<String, dynamic>.from(json['data'] as Map)
          : null,
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
    state.version = json['version'] as int? ?? 0;
    state.lastUpdatedAt = json['lastUpdatedAt'] != null
        ? DateTime.parse(json['lastUpdatedAt'] as String)
        : DateTime.now();
    state.lastUpdateReason = json['lastUpdateReason'] as String? ?? '';
    state.feedbackCountApplied = json['feedbackCountApplied'] as int? ?? 0;
    return state;
  }
}
