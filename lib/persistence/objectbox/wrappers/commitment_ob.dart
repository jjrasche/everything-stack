import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/tools/regulation/entities/commitment.dart';

@Entity()
class CommitmentOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // ============ Commitment-specific fields ============

  String name;
  String? rationale;
  String interval;

  @Property(type: PropertyType.date)
  DateTime? timeOfDay;

  /// Conditions to verify completion (stored as comma-separated string)
  String dbVerificationConditions = '';

  /// Verification conditions getter/setter
  @Transient()
  List<String> get verificationConditions {
    if (dbVerificationConditions.isEmpty) return [];
    return dbVerificationConditions.split(',');
  }

  set verificationConditions(List<String> value) {
    dbVerificationConditions = value.join(',');
  }

  /// Person UUIDs (many-to-many, stored as comma-separated string)
  String dbPersonIds = '';

  /// Person IDs getter/setter
  @Transient()
  List<String> get personIds {
    if (dbPersonIds.isEmpty) return [];
    return dbPersonIds.split(',');
  }

  set personIds(List<String> value) {
    dbPersonIds = value.join(',');
  }

  bool active;

  // ============ Constructor ============

  CommitmentOB({
    required this.name,
    this.rationale,
    required this.interval,
    this.timeOfDay,
    this.active = true,
  });

  // ============ Conversion to/from domain entity ============

  /// Convert from domain entity to ObjectBox wrapper
  factory CommitmentOB.fromCommitment(Commitment commitment) {
    return CommitmentOB(
      name: commitment.name,
      rationale: commitment.rationale,
      interval: commitment.interval,
      timeOfDay: commitment.timeOfDay,
      active: commitment.active,
    )
      ..id = commitment.id
      ..uuid = commitment.uuid
      ..createdAt = commitment.createdAt
      ..updatedAt = commitment.updatedAt
      ..syncId = commitment.syncId
      ..verificationConditions = commitment.verificationConditions
      ..personIds = commitment.personIds;
  }

  /// Convert from ObjectBox wrapper to domain entity
  Commitment toCommitment() {
    final commitment = Commitment(
      name: name,
      rationale: rationale,
      interval: interval,
      timeOfDay: timeOfDay,
      verificationConditions: verificationConditions,
      personIds: personIds,
      active: active,
    );
    commitment.id = id;
    commitment.uuid = uuid;
    commitment.createdAt = createdAt;
    commitment.updatedAt = updatedAt;
    commitment.syncId = syncId;
    return commitment;
  }
}
