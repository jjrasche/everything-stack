/// # RegulationEntryRepository
///
/// ## What it does
/// Repository for RegulationEntry entities. Manages regulation event logging.
/// Uses platform-specific adapters - ObjectBox on native, IndexedDB on web.
///
/// ## Usage
/// ```dart
/// final repo = RegulationEntryRepository();
///
/// // Find entries by person
/// final entries = await repo.findByPerson(personUuid);
///
/// // Get daily summary
/// final summary = await repo.getDailySummary(DateTime.now());
/// ```

import '../../../core/entity_repository.dart';
import '../../../services/embedding_service.dart';
import '../entities/regulation_entry_stub.dart'
    if (dart.library.io) '../entities/regulation_entry.dart';

// Platform-specific adapter factory
import 'regulation_entry_adapter_web.dart'
    if (dart.library.io) 'regulation_entry_adapter_native.dart';

class RegulationEntryRepository extends EntityRepository<RegulationEntry> {
  RegulationEntryRepository({EmbeddingService? embeddingService})
      : super(
          adapter: createRegulationEntryAdapter(),
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  // ============ RegulationEntry-specific queries ============

  /// Find all entries for a specific person (by UUID in personIds list)
  Future<List<RegulationEntry>> findByPerson(String personId) async {
    final all = await findAll();
    return all.where((entry) => entry.personIds.contains(personId)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
