
import 'dart:indexed_db' as idb;
import '../../../persistence/indexeddb/base_indexeddb_adapter.dart';
import '../../../persistence/indexeddb/database_init.dart';
import '../../../persistence/indexeddb/idb_types.dart';
import '../entities/regulation_entry.dart';

class RegulationEntryIndexedDBAdapter
    extends BaseIndexedDBAdapter<RegulationEntry> {
  RegulationEntryIndexedDBAdapter(Database db) : super(db);

  /// Factory method for creating and initializing RegulationEntryIndexedDBAdapter
  static Future<RegulationEntryIndexedDBAdapter> create() async {
    final db = await openIndexedDatabase();
    return RegulationEntryIndexedDBAdapter(db);
  }

  @override
  String get objectStoreName => 'regulation_entries';

  @override
  RegulationEntry fromJson(Map<String, dynamic> json) =>
      RegulationEntry.fromJson(json);

  // ============ RegulationEntry-Specific Query Methods ============

  /// Find all entries for a specific person (by UUID in personIds list)
  Future<List<RegulationEntry>> findByPerson(String personId) async {
    final all = await findAll();
    return all.where((entry) => entry.personIds.contains(personId)).toList();
  }

  /// Find entries within a date range
  Future<List<RegulationEntry>> findByDateRange(
      DateTime start, DateTime end) async {
    final all = await findAll();
    return all.where((entry) {
      return entry.createdAt.isAfter(start) && entry.createdAt.isBefore(end);
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Find entries by entry type
  Future<List<RegulationEntry>> findByType(EntryType type) async {
    final all = await findAll();
    return all.where((entry) => entry.entryType == type).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Find entries by severity
  Future<List<RegulationEntry>> findBySeverity(Severity severity) async {
    final all = await findAll();
    return all.where((entry) => entry.severity == severity).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Get daily summary: count by entry type for a specific date
  Future<Map<EntryType, int>> getDailySummary(DateTime date) async {
    // Start of day
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final entries = await findByDateRange(start, end);

    // Count by entry type
    final summary = <EntryType, int>{};
    for (final entry in entries) {
      summary[entry.entryType] = (summary[entry.entryType] ?? 0) + 1;
    }

    return summary;
  }

  /// Get weekly ruptures: find all rupture entries for a week starting at weekStart
  Future<List<RegulationEntry>> getWeeklyRuptures(DateTime weekStart) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    final allEntries = await findByDateRange(weekStart, weekEnd);

    return allEntries
        .where((entry) => entry.entryType == EntryType.rupture)
        .toList();
  }
}
