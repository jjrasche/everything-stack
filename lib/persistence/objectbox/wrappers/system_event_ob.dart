/// # SystemEventOB (ObjectBox Wrapper)
///
/// ObjectBox model for SystemEvent storage.
/// Maps SystemEvent to ObjectBox for native platform persistence.
library;

import 'package:objectbox/objectbox.dart';

@Entity()
class SystemEventOB {
  @Id()
  int id = 0;

  /// Event type name (TranscriptionComplete, ErrorOccurred, etc.)
  late String eventType;

  /// Correlation ID for turn tracing
  late String correlationId;

  /// When event was created
  late DateTime createdAt;

  /// Full event data as JSON
  late String jsonData;

  SystemEventOB({
    required this.eventType,
    required this.correlationId,
    required this.createdAt,
    required this.jsonData,
  });

  /// Serialize to JSON for storage
  Map<String, dynamic> toJson() => {
    'eventType': eventType,
    'correlationId': correlationId,
    'createdAt': createdAt.toIso8601String(),
    'jsonData': jsonData,
  };

  /// Deserialize from JSON
  factory SystemEventOB.fromJson(Map<String, dynamic> json) {
    return SystemEventOB(
      eventType: json['eventType'] as String? ?? '',
      correlationId: json['correlationId'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      jsonData: json['jsonData'] as String? ?? '{}',
    );
  }
}
