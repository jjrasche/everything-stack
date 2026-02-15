import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/tools/regulation/entities/person.dart';

@Entity()
class PersonOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // ============ Person-specific fields ============

  String name;
  String? role;
  String? notes;

  // ============ Constructor ============

  PersonOB({
    required this.name,
    this.role,
    this.notes,
  });

  // ============ Conversion to/from domain entity ============

  /// Convert from domain entity to ObjectBox wrapper
  factory PersonOB.fromPerson(Person person) {
    return PersonOB(
      name: person.name,
      role: person.role,
      notes: person.notes,
    )
      ..id = person.id
      ..uuid = person.uuid
      ..createdAt = person.createdAt
      ..updatedAt = person.updatedAt
      ..syncId = person.syncId;
  }

  /// Convert from ObjectBox wrapper to domain entity
  Person toPerson() {
    final person = Person(
      name: name,
      role: role,
      notes: notes,
    );
    person.id = id;
    person.uuid = uuid;
    person.createdAt = createdAt;
    person.updatedAt = updatedAt;
    person.syncId = syncId;
    return person;
  }
}
