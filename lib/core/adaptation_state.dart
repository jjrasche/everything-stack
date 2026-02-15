/// Stores learned parameters for any trainable component per implementer.
/// Adaptation state is per-user (individual preference tuning).

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

  /// Which implementer does this state apply to?
  /// Examples: 'groq', 'claude', 'deepgram', 'flutter_tts'
  /// Null for single-implementation components (tool_selector, namespace_selector)
  String? implementer;

  /// User ID for this adaptation state (personalized to a specific user)
  /// Null means default/global initialization values, but all states are per-user
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
    this.implementer,
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
        'implementer': implementer,
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
      implementer: json['implementer'] as String?,
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
