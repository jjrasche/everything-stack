/// # Trainer Service Types
///
/// Shared types for parameter optimization and training infrastructure.

/// Parameter bounds definition: (min, max)
typedef ParamBounds = Map<String, (double, double)>;

/// Trial outcome from optimizer's perspective
class TrialOutcome {
  final Map<String, dynamic> params;
  final double reward;
  final DateTime timestamp;
  final String? metadata;

  TrialOutcome({
    required this.params,
    required this.reward,
    required this.timestamp,
    this.metadata,
  });
}

/// Exception thrown when optimizer fails
class OptimizerException implements Exception {
  final String message;
  final dynamic cause;

  OptimizerException(this.message, {this.cause});

  @override
  String toString() => 'OptimizerException: $message${cause != null ? ' (caused by: $cause)' : ''}';
}
