/// # CommitmentLogIndexedDBAdapter
///
/// ## What it does
/// IndexedDB implementation of PersistenceAdapter for CommitmentLog entities.
/// Handles CRUD operations and queries for web platform.
///
/// ## Usage
/// ```dart
/// final db = await openIndexedDatabase();
/// final adapter = CommitmentLogIndexedDBAdapter(db);
/// final repo = CommitmentLogRepository(adapter: adapter);
/// ```

import 'dart:indexed_db' as idb;
import '../../../persistence/indexeddb/base_indexeddb_adapter.dart';
import '../../../persistence/indexeddb/database_init.dart';
import '../../../persistence/indexeddb/idb_types.dart';
import '../entities/commitment_log_stub.dart'
    if (dart.library.io) '../entities/commitment_log.dart';

class CommitmentLogIndexedDBAdapter
    extends BaseIndexedDBAdapter<CommitmentLog> {
  CommitmentLogIndexedDBAdapter(Database db) : super(db);

  /// Factory method for creating and initializing CommitmentLogIndexedDBAdapter
  static Future<CommitmentLogIndexedDBAdapter> create() async {
    final db = await openIndexedDatabase();
    return CommitmentLogIndexedDBAdapter(db);
  }

  @override
  String get objectStoreName => 'commitment_logs';

  @override
  CommitmentLog fromJson(Map<String, dynamic> json) =>
      CommitmentLog.fromJson(json);

  // ============ CommitmentLog-Specific Query Methods ============

  /// Find all logs for a specific commitment
  Future<List<CommitmentLog>> findByCommitment(String commitmentId) async {
    final all = await findAll();
    return all.where((log) => log.commitmentId == commitmentId).toList();
  }

  /// Find log for a commitment on a specific date
  Future<CommitmentLog?> findByCommitmentAndDate(
      String commitmentId, DateTime date) async {
    // Start of day
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final all = await findAll();
    try {
      return all.firstWhere(
        (log) =>
            log.commitmentId == commitmentId &&
            log.date.isAfter(start) &&
            log.date.isBefore(end),
      );
    } catch (e) {
      return null;
    }
  }

  /// Find logs within a date range
  Future<List<CommitmentLog>> findByDateRange(
      DateTime start, DateTime end) async {
    final all = await findAll();
    return all.where((log) {
      return log.date.isAfter(start) && log.date.isBefore(end);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Get completion rate for a commitment (percentage of completed logs)
  Future<double> getCompletionRate(String commitmentId) async {
    final logs = await findByCommitment(commitmentId);
    if (logs.isEmpty) {
      return 0.0;
    }

    final completedCount = logs.where((log) => log.completed).length;
    return (completedCount / logs.length) * 100;
  }
}
