/// Records parameter-to-reward trials for Gaussian Process training.
/// Parameters are normalized to [0,1] for GP numerical stability.

import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';
import 'base_entity.dart';

part 'trial.g.dart';

@JsonSerializable()
class Trial extends BaseEntity {
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

  @override
  SyncStatus syncStatus = SyncStatus.local;

  // ============ Trial fields ============

  /// Which component is being optimized?
  /// Examples: 'context_selector', 'tool_selector', 'intent_recognizer'
  String componentType;

  /// User ID for multi-user isolation (null = global)
  String? userId;

  /// Normalized parameters as JSON: {"param1": 0.5, "param2": 0.8}
  /// All values in [0,1] range for GP numerical stability.
  String paramsJson;

  /// Reward signal from feedback
  /// - 1.0: Positive feedback (confirm, correct)
  /// - -1.0: Negative feedback (deny)
  /// - Intermediate values possible for partial credit
  double reward;

  /// Optional metadata about trial execution
  /// Can store: latency, confidence, error rates, etc.
  String? metadata;

  // ============ Constructor ============

  Trial({
    required this.componentType,
    required this.paramsJson,
    required this.reward,
    this.userId,
    this.metadata,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }

    // Validation
    if (componentType.isEmpty) {
      throw ArgumentError('componentType cannot be empty');
    }

    if (reward < -1.0 || reward > 1.0) {
      throw ArgumentError('reward must be in [-1.0, 1.0], got $reward');
    }

    try {
      jsonDecode(paramsJson);
    } catch (e) {
      throw ArgumentError('paramsJson must be valid JSON: $e');
    }
  }

  // ============ Helpers ============

  /// Get parameters as Map<String, double>
  Map<String, double> get params {
    final decoded = jsonDecode(paramsJson) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value as double));
  }

  /// Is this trial user-specific?
  bool get isUserSpecific => userId != null;

  /// Is this a positive trial? (reward > 0)
  bool get isPositive => reward > 0.0;

  /// Is this a negative trial? (reward < 0)
  bool get isNegative => reward < 0.0;

  // ============ JSON Serialization ============

  Map<String, dynamic> toJson() => _$TrialToJson(this);
  factory Trial.fromJson(Map<String, dynamic> json) => _$TrialFromJson(json);
}
