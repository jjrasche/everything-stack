/// # CommitmentIndexedDBAdapter
///
/// ## What it does
/// IndexedDB implementation of PersistenceAdapter for Commitment entities.
/// Handles CRUD operations for web platform.
///
/// ## Usage
/// ```dart
/// final db = await openIndexedDatabase();
/// final adapter = CommitmentIndexedDBAdapter(db);
/// final repo = CommitmentRepository(adapter: adapter);
/// ```

import 'dart:indexed_db' as idb;
import '../../../persistence/indexeddb/base_indexeddb_adapter.dart';
import '../../../persistence/indexeddb/database_init.dart';
import '../../../persistence/indexeddb/idb_types.dart';
import '../entities/commitment_stub.dart'
    if (dart.library.io) '../entities/commitment.dart';

class CommitmentIndexedDBAdapter extends BaseIndexedDBAdapter<Commitment> {
  CommitmentIndexedDBAdapter(Database db) : super(db);

  /// Factory method for creating and initializing CommitmentIndexedDBAdapter
  static Future<CommitmentIndexedDBAdapter> create() async {
    final db = await openIndexedDatabase();
    return CommitmentIndexedDBAdapter(db);
  }

  @override
  String get objectStoreName => 'commitments';

  @override
  Commitment fromJson(Map<String, dynamic> json) =>
      Commitment.fromJson(json);

  // ============ Commitment-Specific Query Methods ============

  /// Find all active commitments
  Future<List<Commitment>> findActive() async {
    final all = await findAll();
    return all.where((commitment) => commitment.active).toList();
  }

  /// Find all commitments for a specific person (by UUID in personIds list)
  Future<List<Commitment>> findByPerson(String personId) async {
    final all = await findAll();
    return all
        .where((commitment) => commitment.personIds.contains(personId))
        .toList();
  }

  /// Find commitments by interval
  Future<List<Commitment>> findByInterval(String interval) async {
    final all = await findAll();
    return all
        .where((commitment) => commitment.interval == interval)
        .toList();
  }
}
