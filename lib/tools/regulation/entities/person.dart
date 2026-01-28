/// # Person
///
/// ## What it does
/// Represents a person involved in regulation tracking events and commitments.
/// Used to track family members, household participants, or other relevant individuals.
///
/// ## Domain Entity Pattern
/// This is a pure Dart domain entity with NO ObjectBox decorators.
/// ObjectBox decorators belong on the wrapper class (PersonOB) in the adapters directory.
/// This allows the same entity to work on native (ObjectBox) and web (IndexedDB) platforms.
///
/// ## Usage
/// ```dart
/// final person = Person(
///   name: 'Alice',
///   role: 'child',
///   notes: 'Age 8, responds well to deep breathing techniques',
/// );
/// ```

import '../../../core/base_entity.dart';

class Person extends BaseEntity {
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

  // ============ Person fields ============

  /// Person's name
  String name;

  /// Optional role (e.g., "parent", "child", "partner", "therapist")
  String? role;

  /// Optional notes about this person
  String? notes;

  // ============ Constructor ============

  Person({
    required this.name,
    this.role,
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
        'name': name,
        'role': role,
        'notes': notes,
      };

  factory Person.fromJson(Map<String, dynamic> json) {
    final person = Person(
      name: json['name'] as String,
      role: json['role'] as String?,
      notes: json['notes'] as String?,
    );
    person.id = json['id'] as int? ?? 0;
    person.uuid = json['uuid'] as String? ?? '';
    person.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    person.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    person.syncId = json['syncId'] as String?;
    return person;
  }
}
