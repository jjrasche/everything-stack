/// # CommitmentLog
///
/// ## What it does
/// Records daily tracking of commitment completion.
/// Tracks who completed it and when.
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

import 'package:objectbox/objectbox.dart';

import '../../../core/base_entity.dart';

@Entity()
class CommitmentLog extends BaseEntity {
  // ============ BaseEntity field overrides ============
  @override
  @Id()
  int id = 0;

  @override
  @Unique()
  String uuid = '';

  @override
  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @override
  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  @override
  String? syncId;

  // ============ CommitmentLog fields ============

  /// UUID of the commitment being logged
  String commitmentId;

  /// Date this log entry is for
  @Property(type: PropertyType.date)
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
