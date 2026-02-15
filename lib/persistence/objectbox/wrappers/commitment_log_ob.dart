import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/tools/regulation/entities/commitment_log.dart';

@Entity()
class CommitmentLogOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // ============ CommitmentLog-specific fields ============

  String commitmentId;

  @Property(type: PropertyType.date)
  DateTime date;

  bool completed;
  String? personId;
  String? notes;

  // ============ Constructor ============

  CommitmentLogOB({
    required this.commitmentId,
    required this.date,
    required this.completed,
    this.personId,
    this.notes,
  });

  // ============ Conversion to/from domain entity ============

  /// Convert from domain entity to ObjectBox wrapper
  factory CommitmentLogOB.fromCommitmentLog(CommitmentLog log) {
    return CommitmentLogOB(
      commitmentId: log.commitmentId,
      date: log.date,
      completed: log.completed,
      personId: log.personId,
      notes: log.notes,
    )
      ..id = log.id
      ..uuid = log.uuid
      ..createdAt = log.createdAt
      ..updatedAt = log.updatedAt
      ..syncId = log.syncId;
  }

  /// Convert from ObjectBox wrapper to domain entity
  CommitmentLog toCommitmentLog() {
    final log = CommitmentLog(
      commitmentId: commitmentId,
      date: date,
      completed: completed,
      personId: personId,
      notes: notes,
    );
    log.id = id;
    log.uuid = uuid;
    log.createdAt = createdAt;
    log.updatedAt = updatedAt;
    log.syncId = syncId;
    return log;
  }
}
