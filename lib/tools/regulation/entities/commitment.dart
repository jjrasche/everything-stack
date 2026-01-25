/// # Commitment
///
/// ## What it does
/// Represents a commitment that people make (daily meditation, kitchen clean, etc.).
/// Tracks who is responsible and how to verify completion.
///
/// ## Usage
/// ```dart
/// final commitment = Commitment(
///   name: 'Morning meditation',
///   rationale: 'Helps start the day calm and focused',
///   interval: 'daily',
///   timeOfDay: DateTime(2024, 1, 1, 7, 0), // 7 AM
///   verificationConditions: ['meditation app shows completion', 'sits for 10 minutes'],
///   personIds: ['person-uuid-1'],
///   active: true,
/// );
/// ```

import 'package:objectbox/objectbox.dart';

import '../../../core/base_entity.dart';

@Entity()
class Commitment extends BaseEntity {
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

  // ============ Commitment fields ============

  /// Name of the commitment
  String name;

  /// Why this commitment matters
  String? rationale;

  /// How often to check this commitment ("daily", "weekly", "monthly")
  String interval;

  /// Optional scheduled time of day
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

  /// Is this commitment active?
  bool active;

  // ============ Constructor ============

  Commitment({
    required this.name,
    this.rationale,
    required this.interval,
    this.timeOfDay,
    List<String>? verificationConditions,
    List<String>? personIds,
    this.active = true,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
    this.verificationConditions = verificationConditions ?? []; // Use setter
    this.personIds = personIds ?? []; // Use setter
  }

  // ============ JSON serialization ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'name': name,
        'rationale': rationale,
        'interval': interval,
        'timeOfDay': timeOfDay?.toIso8601String(),
        'verificationConditions': verificationConditions,
        'personIds': personIds,
        'active': active,
      };

  factory Commitment.fromJson(Map<String, dynamic> json) {
    final commitment = Commitment(
      name: json['name'] as String,
      rationale: json['rationale'] as String?,
      interval: json['interval'] as String,
      timeOfDay: json['timeOfDay'] != null
          ? DateTime.parse(json['timeOfDay'] as String)
          : null,
      verificationConditions:
          (json['verificationConditions'] as List).map((e) => e as String).toList(),
      personIds: (json['personIds'] as List).map((e) => e as String).toList(),
      active: json['active'] as bool? ?? true,
    );
    commitment.id = json['id'] as int? ?? 0;
    commitment.uuid = json['uuid'] as String? ?? '';
    commitment.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    commitment.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    commitment.syncId = json['syncId'] as String?;
    return commitment;
  }
}
