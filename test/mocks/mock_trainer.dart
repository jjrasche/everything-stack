/// Mock Trainer for testing Intent Engine learning loop
/// Captures failure signals, success signals, and null intents for analysis

class MockTrainer {
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
  void recordFailure({
    required String tool,
    required String failureType,
    required String message,
    String? slotAffected,
    String? originalUtterance,
    Map<String, dynamic>? attemptedSlots,
    List<String>? ambiguousValues,
    double? slotConfidenceAtFailure,
  }) {
    lastFailureSignal = {
      'tool': tool,
      'failure_type': failureType,
      'message': message,
      'slot_affected': slotAffected,
      'original_utterance': originalUtterance,
      'attempted_slots': attemptedSlots,
      'ambiguous_values': ambiguousValues,
      'slot_confidence_at_failure': slotConfidenceAtFailure,
      'timestamp': DateTime.now(),
    };

    failureHistory.add(lastFailureSignal!);
  }

  /// Record a successful tool execution for training
  void recordSuccess({
    required String utterance,
    required Map<String, dynamic> intent,
    required dynamic executionResult,
    Map<String, dynamic>? slotsUsed,
    Map<String, num>? slotConfidenceAtExecution,
  }) {
    lastSuccess = {
      'utterance': utterance,
      'tool': intent['tool'],
      'slotsUsed': slotsUsed ?? intent['slots'],
      'slot_confidence_at_execution': slotConfidenceAtExecution ?? intent['slot_confidence'],
      'reasoning': intent['reasoning'],
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

    return slotFailureCounts.entries
        .sorted((a, b) => b.value.compareTo(a.value))
        .map((e) => e.key)
        .toList();
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

extension on List<MapEntry<String, int>> {
  List<MapEntry<String, int>> sorted(
      int Function(MapEntry<String, int>, MapEntry<String, int>) compare) {
    final copy = [...this];
    copy.sort(compare);
    return copy;
  }
}
