/// Mock Trainer for testing Intent Engine learning loop
/// Captures failure signals, success signals, and null intents for analysis
/// Implements the abstract Trainer interface from ToolExecutor

import 'package:everything_stack_template/services/tool_executor/tool_executor.dart';

class MockTrainer implements Trainer {
  /// Last failure signal received
  Map<String, dynamic>? lastFailureSignal;

  /// Last success signal received
  Map<String, dynamic>? lastSuccess;

  /// Last null intent recorded
  Map<String, dynamic>? lastNullIntent;

  /// All failure signals received (for analysis)
  final List<Map<String, dynamic>> failureHistory = [];

  /// All success signals received (for analysis)
  final List<Map<String, dynamic>> successHistory = [];

  /// All null intents recorded (for analysis)
  final List<Map<String, dynamic>> nullIntentHistory = [];

  /// Record a tool execution failure for training
  /// Matches abstract Trainer interface from ToolExecutor
  @override
  void recordFailure({
    required String tool,
    required String failureType,
    required String message,
    String? slotAffected,
    double? slotConfidenceAtFailure,
  }) {
    lastFailureSignal = {
      'tool': tool,
      'failure_type': failureType,
      'message': message,
      'slot_affected': slotAffected,
      'slot_confidence_at_failure': slotConfidenceAtFailure,
      'timestamp': DateTime.now(),
    };

    failureHistory.add(lastFailureSignal!);
  }

  /// Record a successful tool execution for training
  /// Matches abstract Trainer interface from ToolExecutor
  @override
  void recordSuccess({
    required String tool,
    required Map<String, dynamic> slotsUsed,
    required String reasoning,
    Map<String, dynamic>? metadata,
  }) {
    lastSuccess = {
      'tool': tool,
      'slotsUsed': slotsUsed,
      'reasoning': reasoning,
      'metadata': metadata,
      'execution_status': 'success',
      'timestamp': DateTime.now(),
    };

    successHistory.add(lastSuccess!);
  }

  /// Record when intent classification returns null (conversational response only)
  void recordNullIntent({
    required String utterance,
    required String conversationalResponse,
  }) {
    lastNullIntent = {
      'utterance': utterance,
      'conversational_response': conversationalResponse,
      'timestamp': DateTime.now(),
    };

    nullIntentHistory.add(lastNullIntent!);
  }

  /// Get failure rate for a specific tool
  double getFailureRateForTool(String tool) {
    if (failureHistory.isEmpty && successHistory.isEmpty) {
      return 0.0;
    }

    final toolFailures = failureHistory.where((f) => f['tool'] == tool).length;
    final toolSuccesses = successHistory.where((s) => s['tool'] == tool).length;
    final totalToolExecutions = toolFailures + toolSuccesses;

    if (totalToolExecutions == 0) {
      return 0.0;
    }

    return toolFailures / totalToolExecutions;
  }

  /// Get most common failure type
  String? getMostCommonFailureType() {
    if (failureHistory.isEmpty) {
      return null;
    }

    final failureTypeCounts = <String, int>{};
    for (final failure in failureHistory) {
      final type = failure['failure_type'] as String;
      failureTypeCounts[type] = (failureTypeCounts[type] ?? 0) + 1;
    }

    return failureTypeCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Get slots that fail most frequently
  List<String> getMostFailedSlots() {
    final slotFailureCounts = <String, int>{};
    for (final failure in failureHistory) {
      final slot = failure['slot_affected'] as String?;
      if (slot != null) {
        slotFailureCounts[slot] = (slotFailureCounts[slot] ?? 0) + 1;
      }
    }

    final sorted = slotFailureCounts.entries.toList();
    sorted.sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  /// Reset trainer state
  void reset() {
    lastFailureSignal = null;
    lastSuccess = null;
    lastNullIntent = null;
    failureHistory.clear();
    successHistory.clear();
    nullIntentHistory.clear();
  }

  /// Get summary statistics
  Map<String, dynamic> getSummary() {
    return {
      'total_executions': failureHistory.length + successHistory.length,
      'total_failures': failureHistory.length,
      'total_successes': successHistory.length,
      'total_null_intents': nullIntentHistory.length,
      'failure_rate': failureHistory.length /
          (failureHistory.length + successHistory.length > 0
              ? failureHistory.length + successHistory.length
              : 1),
      'most_common_failure': getMostCommonFailureType(),
      'most_failed_slots': getMostFailedSlots(),
    };
  }
}
