/// # CommitmentLog
///
/// ## What it does
/// Records daily tracking of commitment completion.
/// Tracks who completed it and when.
///
/// ## Domain Entity Pattern
/// This is a pure Dart domain entity with NO ObjectBox decorators.
/// ObjectBox decorators belong on the wrapper class (CommitmentLogOB) in the adapters directory.
/// This allows the same entity to work on native (ObjectBox) and web (IndexedDB) platforms.
///
/// ## Usage
/// ```dart
/// final log = CommitmentLog(
///   commitmentId: 'commitment-uuid',
///   date: DateTime.now(),
///   completed: true,
///   personId: 'person-uuid',
///   notes: 'Completed morning meditation for 15 minutes',
/// );
/// ```

import '../../../core/base_entity.dart';

class CommitmentLog extends BaseEntity {
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

  // ============ CommitmentLog fields ============

  /// UUID of the commitment being logged
  String commitmentId;

  /// Date this log entry is for
  DateTime date;

  /// Was the commitment completed?
  bool completed;

  /// Who completed it (UUID of Person)
  String? personId;

  /// Optional notes about completion
  String? notes;

  // ============ Constructor ============

  CommitmentLog({
    required this.commitmentId,
    required this.date,
    required this.completed,
    this.personId,
    this.notes,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ JSON serialization ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'commitmentId': commitmentId,
        'date': date.toIso8601String(),
        'completed': completed,
        'personId': personId,
        'notes': notes,
      };

  factory CommitmentLog.fromJson(Map<String, dynamic> json) {
    final log = CommitmentLog(
      commitmentId: json['commitmentId'] as String,
      date: DateTime.parse(json['date'] as String),
      completed: json['completed'] as bool,
      personId: json['personId'] as String?,
      notes: json['notes'] as String?,
    );
    log.id = json['id'] as int? ?? 0;
    log.uuid = json['uuid'] as String? ?? '';
    log.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    log.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    log.syncId = json['syncId'] as String?;
    return log;
  }
}
