
import '../../../core/base_entity.dart';

class Commitment extends BaseEntity {
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

  // ============ Commitment fields ============

  /// Name of the commitment
  String name;

  /// Why this commitment matters
  String? rationale;

  /// How often to check this commitment ("daily", "weekly", "monthly")
  String interval;

  /// Optional scheduled time of day
  DateTime? timeOfDay;

  /// Verification conditions as list
  List<String> verificationConditions;

  /// Person UUIDs
  List<String> personIds;

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
  })  : verificationConditions = verificationConditions ?? [],
        personIds = personIds ?? [] {
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
      verificationConditions: (json['verificationConditions'] as List)
          .map((e) => e as String)
          .toList(),
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
