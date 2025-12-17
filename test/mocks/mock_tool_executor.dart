/// Mock ToolExecutor for testing Intent Engine integration with execution
/// Allows tests to simulate execution failures and successes

enum ExecutionFailureType {
  entityNotFound,
  ambiguousEntity,
  requiredSlotMissing,
  slotValidationError,
  toolNotFound,
  unknown,
}

enum ExecutionStatus {
  success,
  failed,
  skipped,
}

class ExecutionFailure {
  final ExecutionFailureType type;
  final String message;
  final String? originalUtterance;
  final Map<String, dynamic>? attemptedSlots;
  final String? slotName;
  final double? slotConfidence;

  ExecutionFailure({
    required this.type,
    required this.message,
    this.originalUtterance,
    this.attemptedSlots,
    this.slotName,
    this.slotConfidence,
  });
}

class ExecutionSuccess {
  final String tool;
  final Map<String, dynamic> slotsUsed;

  ExecutionSuccess({
    required this.tool,
    this.slotsUsed = const {},
  });
}

class ExecutionResult {
  final ExecutionStatus status;
  final String? message;
  final ExecutionFailure? failure;
  final ExecutionSuccess? success;

  ExecutionResult({
    required this.status,
    this.message,
    this.failure,
    this.success,
  });
}

class MockToolExecutor {
  /// Pre-configured failure for next execution
  late ExecutionFailure? _failureToReturn;

  /// Pre-configured success for next execution
  late ExecutionSuccess? _successToReturn;

  /// Track all executions
  final List<Map<String, dynamic>> executionHistory = [];

  /// Number of execute() calls
  int callCount = 0;

  MockToolExecutor() {
    _failureToReturn = null;
    _successToReturn = null;
  }

  /// Set up next execution to fail
  void setFailure(String tool, ExecutionFailure failure) {
    _failureToReturn = failure;
    _successToReturn = null;
  }

  /// Set up next execution to succeed
  void setSuccess(ExecutionSuccess success) {
    _successToReturn = success;
    _failureToReturn = null;
  }

  /// Execute intents (returns configured failure or success)
  Future<ExecutionResult> execute(List<Map<String, dynamic>> intents) async {
    callCount++;

    if (intents.isEmpty) {
      return ExecutionResult(
        status: ExecutionStatus.skipped,
        message: 'No intents to execute',
      );
    }

    // Record execution
    executionHistory.add({
      'intent_count': intents.length,
      'intents': intents,
      'timestamp': DateTime.now(),
    });

    // Return configured result
    if (_failureToReturn != null) {
      return ExecutionResult(
        status: ExecutionStatus.failed,
        message: _failureToReturn!.message,
        failure: _failureToReturn,
      );
    }

    if (_successToReturn != null) {
      return ExecutionResult(
        status: ExecutionStatus.success,
        message: 'Execution successful',
        success: _successToReturn,
      );
    }

    // Default to success if nothing configured
    return ExecutionResult(
      status: ExecutionStatus.success,
      message: 'Execution successful',
    );
  }

  /// Reset mock state
  void reset() {
    callCount = 0;
    executionHistory.clear();
    _failureToReturn = null;
    _successToReturn = null;
  }
}
