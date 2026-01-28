/// # PersonObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for Person entities.
/// Uses wrapper pattern (PersonOB) to keep domain entity clean.
///
/// ## Pattern
/// - Domain entity (Person) has NO ObjectBox decorators
/// - Wrapper class (PersonOB) has ALL decorators
/// - Adapter converts between Person <-> PersonOB
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = PersonObjectBoxAdapter(store);
/// final repo = PersonRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../tools/regulation/entities/person.dart';
import '../../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/person_ob.dart';

class PersonObjectBoxAdapter extends BaseObjectBoxAdapter<Person, PersonOB>
    implements PersistenceAdapter<Person> {
  PersonObjectBoxAdapter(Store store) : super(store);

  @override
  PersonOB toOB(Person entity) => PersonOB.fromPerson(entity);

  @override
  Person fromOB(PersonOB ob) => ob.toPerson();

  @override
  Condition<PersonOB> uuidEqualsCondition(String uuid) =>
      PersonOB_.uuid.equals(uuid);

  @override
  Condition<PersonOB> syncStatusLocalCondition() => PersonOB_.syncId.isNull();

  // ============ Person-Specific Query Methods ============

  /// Find person by name (case-insensitive)
  Future<Person?> findByName(String name) async {
    final query =
        box.query(PersonOB_.name.equals(name, caseSensitive: false)).build();
    try {
      final ob = query.findFirst();
      return ob != null ? fromOB(ob) : null;
    } finally {
      query.close();
    }
  }

  /// Find all people with a specific role
  Future<List<Person>> findByRole(String role) async {
    final query = box.query(PersonOB_.role.equals(role)).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }
}
