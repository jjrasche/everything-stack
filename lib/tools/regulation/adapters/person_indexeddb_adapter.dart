/// # PersonIndexedDBAdapter
///
/// ## What it does
/// IndexedDB implementation of PersistenceAdapter for Person entities.
/// Handles CRUD operations for web platform.
///
/// ## Usage
/// ```dart
/// final db = await openIndexedDatabase();
/// final adapter = PersonIndexedDBAdapter(db);
/// final repo = PersonRepository(adapter: adapter);
/// ```

import 'dart:indexed_db' as idb;
import '../../../persistence/indexeddb/base_indexeddb_adapter.dart';
import '../../../persistence/indexeddb/database_init.dart';
import '../../../persistence/indexeddb/idb_types.dart';
import '../entities/person_stub.dart'
    if (dart.library.io) '../entities/person.dart';

class PersonIndexedDBAdapter extends BaseIndexedDBAdapter<Person> {
  PersonIndexedDBAdapter(Database db) : super(db);

  /// Factory method for creating and initializing PersonIndexedDBAdapter
  static Future<PersonIndexedDBAdapter> create() async {
    final db = await openIndexedDatabase();
    return PersonIndexedDBAdapter(db);
  }

  @override
  String get objectStoreName => 'persons';

  @override
  Person fromJson(Map<String, dynamic> json) => Person.fromJson(json);

  // ============ Person-Specific Query Methods ============

  /// Find person by name (case-insensitive)
  Future<Person?> findByName(String name) async {
    final all = await findAll();
    try {
      return all.firstWhere(
        (person) => person.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Find all people with a specific role
  Future<List<Person>> findByRole(String role) async {
    final all = await findAll();
    return all.where((person) => person.role == role).toList();
  }
}
