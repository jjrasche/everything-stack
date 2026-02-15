/// ## Schema addition
/// ```dart
/// String? invocationCorrelationId;  // Links to Event chain
/// DateTime? invokedAt;               // When tool was called
/// String? invokedByTool;             // "task.create"
/// Map<String, dynamic>? invocationParams;  // Parameters used
/// double? invocationConfidence;      // How confident was tool selection
/// String? invocationStatus;          // 'success', 'tool_error', 'execution_error'
/// ```
///
/// ## Usage
/// ```dart
/// class Task extends BaseEntity with Invocable, Ownable {
///   String title;
///   DateTime? dueDate;
/// }
///
/// // When tool creates a task
/// final task = Task(title: 'Buy groceries');
/// task.invocationCorrelationId = event.correlationId;
/// task.invokedAt = DateTime.now();
/// task.invokedByTool = 'task.create';
/// task.invocationParams = {'title': 'Buy groceries'};
/// task.invocationConfidence = 0.92;
/// task.invocationStatus = 'success';
/// ```
///
/// ## Key Insight
/// No separate invocation table needed for result entities.
/// The entity IS the result - it carries its own birth certificate.
/// ContextManagerInvocation tracks the decision process;
/// Invocable tracks the outcome.
///
/// ## Integrates with
/// - Event: correlationId links to triggering event
/// - ContextManagerInvocation: Records why this tool was chosen
/// - Ownable: Who owns the created entity

mixin Invocable {
  /// Links to the Event chain that triggered this invocation
  String? invocationCorrelationId;

  /// When the tool was invoked
  DateTime? invokedAt;

  /// Which tool created this entity: "task.create", "timer.set"
  String? invokedByTool;

  /// Parameters passed to the tool
  Map<String, dynamic>? invocationParams;

  /// How confident was the tool selection (0.0-1.0)
  double? invocationConfidence;

  /// Result status of the invocation
  /// - 'success': Tool executed successfully
  /// - 'tool_error': Tool returned an error
  /// - 'execution_error': Exception during execution
  String? invocationStatus;

  /// Was this entity created by a tool invocation?
  bool get wasInvoked => invokedByTool != null;

  /// Did the invocation succeed?
  bool get invocationSucceeded => invocationStatus == 'success';

  /// Record invocation details
  void recordInvocation({
    required String correlationId,
    required String toolName,
    Map<String, dynamic>? params,
    double? confidence,
    String status = 'success',
  }) {
    invocationCorrelationId = correlationId;
    invokedAt = DateTime.now();
    invokedByTool = toolName;
    invocationParams = params;
    invocationConfidence = confidence;
    invocationStatus = status;
  }

  /// Mark invocation as failed
  void markInvocationFailed(String errorType) {
    invocationStatus = errorType;
  }

  /// Invocation fields as JSON (for serialization)
  Map<String, dynamic> invocableToJson() => {
        'invocationCorrelationId': invocationCorrelationId,
        'invokedAt': invokedAt?.toIso8601String(),
        'invokedByTool': invokedByTool,
        'invocationParams': invocationParams,
        'invocationConfidence': invocationConfidence,
        'invocationStatus': invocationStatus,
      };

  /// Populate invocation fields from JSON
  void invocableFromJson(Map<String, dynamic> json) {
    invocationCorrelationId = json['invocationCorrelationId'] as String?;
    invokedAt = json['invokedAt'] != null
        ? DateTime.parse(json['invokedAt'] as String)
        : null;
    invokedByTool = json['invokedByTool'] as String?;
    invocationParams = json['invocationParams'] != null
        ? Map<String, dynamic>.from(json['invocationParams'] as Map)
        : null;
    invocationConfidence = json['invocationConfidence'] as double?;
    invocationStatus = json['invocationStatus'] as String?;
  }
}
