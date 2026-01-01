/// # System Event Base Class
///
/// Base class for system-level events (STT transcription, errors, etc.)
/// Different from domain/event.dart which is a persisted entity model.
///
/// System events are:
/// - Immutable once published
/// - Typed (subclasses define event kind)
/// - Timestamped with correlationId for turn tracing
/// - Used by EventBus for pub/sub coordination
library;

abstract class SystemEvent {
  /// Unique ID tying events in a "turn" together
  /// (user interaction → STT → Coordinator orchestration → training)
  final String correlationId;

  /// When this event was created (UTC)
  final DateTime createdAt;

  SystemEvent({
    required this.correlationId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  /// Event type name for debugging
  String get eventType => runtimeType.toString();

  /// Convert to JSON for persistence
  Map<String, dynamic> toJson() => {
        'correlationId': correlationId,
        'createdAt': createdAt.toIso8601String(),
        'eventType': eventType,
      };

  @override
  String toString() =>
      '$eventType(correlationId: $correlationId, createdAt: $createdAt)';
}
