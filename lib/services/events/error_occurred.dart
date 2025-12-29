/// # ErrorOccurred Event
///
/// Published when an error occurs during system operation.
/// Used for logging, monitoring, and debugging.
///
/// ## Sources
/// - Coordinator.orchestrate() on exception
/// - STTService.transcribe() on API failure
/// - Any service when an unexpected error occurs
///
/// ## Listening Consumers
/// - Error logger (persists error details)
/// - Monitoring service (alerts on critical errors)
/// - Test harness (validates error handling)
library;

import 'system_event.dart';

class ErrorOccurred extends SystemEvent {
  /// Component that encountered the error
  final String source;

  /// Human-readable error message
  final String message;

  /// Error type/class name (e.g., 'SocketException', 'TimeoutException')
  final String errorType;

  /// Stack trace if available
  final String? stackTrace;

  /// Severity: 'debug', 'info', 'warning', 'error', 'critical'
  final String severity;

  ErrorOccurred({
    required this.source,
    required this.message,
    required this.errorType,
    required String correlationId,
    this.stackTrace,
    this.severity = 'error',
    DateTime? createdAt,
  }) : super(correlationId: correlationId, createdAt: createdAt);

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'source': source,
    'message': message,
    'errorType': errorType,
    'stackTrace': stackTrace,
    'severity': severity,
  };

  factory ErrorOccurred.fromJson(Map<String, dynamic> json) {
    return ErrorOccurred(
      source: json['source'] as String? ?? '',
      message: json['message'] as String? ?? '',
      errorType: json['errorType'] as String? ?? 'UnknownError',
      correlationId: json['correlationId'] as String? ?? '',
      stackTrace: json['stackTrace'] as String?,
      severity: json['severity'] as String? ?? 'error',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  @override
  String toString() =>
      'ErrorOccurred(correlationId: $correlationId, source: "$source", message: "$message", severity: $severity)';
}
