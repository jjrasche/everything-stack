import 'package:objectbox/objectbox.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../tools/regulation/entities/regulation_entry.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/regulation_entry_ob.dart';

class RegulationEntryObjectBoxAdapter
    extends BaseObjectBoxAdapter<RegulationEntry, RegulationEntryOB>
    implements PersistenceAdapter<RegulationEntry> {
  RegulationEntryObjectBoxAdapter(Store store) : super(store);

  @override
  RegulationEntryOB toOB(RegulationEntry entity) =>
      RegulationEntryOB.fromRegulationEntry(entity);

  @override
  RegulationEntry fromOB(RegulationEntryOB ob) => ob.toRegulationEntry();

  @override
  Condition<RegulationEntryOB> uuidEqualsCondition(String uuid) =>
      RegulationEntryOB_.uuid.equals(uuid);

  @override
  Condition<RegulationEntryOB> syncStatusLocalCondition() =>
      RegulationEntryOB_.syncId.isNull();

  // ============ RegulationEntry-Specific Query Methods ============

  /// Find all entries for a specific person (by UUID in personIds list)
  Future<List<RegulationEntry>> findByPerson(String personId) async {
    // Query: dbPersonIds contains personId
    // Note: Contains query on comma-separated string
    final allEntries = await findAll();
    return allEntries
        .where((entry) => entry.personIds.contains(personId))
        .toList();
  }

  /// Find entries within a date range
  Future<List<RegulationEntry>> findByDateRange(
      DateTime start, DateTime end) async {
    final query = box
        .query(RegulationEntryOB_.createdAt.betweenDate(start, end))
        .order(RegulationEntryOB_.createdAt)
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  /// Find entries by entry type
  Future<List<RegulationEntry>> findByType(EntryType type) async {
    final query = box
        .query(RegulationEntryOB_.dbEntryType.equals(type.index))
        .order(RegulationEntryOB_.createdAt, flags: Order.descending)
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  /// Find entries by severity
  Future<List<RegulationEntry>> findBySeverity(Severity severity) async {
    final query = box
        .query(RegulationEntryOB_.dbSeverity.equals(severity.index))
        .order(RegulationEntryOB_.createdAt, flags: Order.descending)
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  /// Get daily summary: count by entry type for a specific date
  Future<Map<EntryType, int>> getDailySummary(DateTime date) async {
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
