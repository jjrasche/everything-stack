/// # RegulationEntryObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for RegulationEntry entities.
/// Supports queries by person, date range, entry type, and severity.
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = RegulationEntryObjectBoxAdapter(store);
/// final repo = RegulationEntryRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../../../core/persistence/objectbox_tx_context.dart';
import '../entities/regulation_entry.dart';
import '../../../objectbox.g.dart';

class RegulationEntryObjectBoxAdapter
    implements PersistenceAdapter<RegulationEntry> {
  final Store _store;
  late final Box<RegulationEntry> _box;

  RegulationEntryObjectBoxAdapter(this._store) {
    _box = _store.box<RegulationEntry>();
  }

  Box<RegulationEntry> get box => _box;

  // ============ CRUD ============

  @override
  Future<RegulationEntry?> findById(String uuid) async {
    final query = _box.query(RegulationEntry_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  Future<RegulationEntry> getById(String uuid) async {
    final entity = await findById(uuid);
    if (entity == null) {
      throw Exception('RegulationEntry not found with uuid: $uuid');
    }
    return entity;
  }

  @override
  @deprecated
  Future<RegulationEntry?> findByIntId(int id) async {
    return _box.get(id);
  }

  @override
  @deprecated
  Future<RegulationEntry> getByIntId(int id) async {
    final entity = await findByIntId(id);
    if (entity == null) {
      throw Exception('RegulationEntry not found with id: $id');
    }
    return entity;
  }

  @override
  Future<List<RegulationEntry>> findAll() async {
    return _box.getAll();
  }

  @override
  Future<RegulationEntry> save(RegulationEntry entity,
      {bool touch = true}) async {
    if (touch) {
      entity.touch();
    }
    _box.put(entity);
    return entity;
  }

  @override
  Future<List<RegulationEntry>> saveAll(List<RegulationEntry> entities) async {
    for (final entity in entities) {
      entity.touch();
    }
    _box.putMany(entities);
    return entities;
  }

  @override
  Future<bool> delete(String uuid) async {
    final entity = await findById(uuid);
    if (entity != null) {
      return _box.remove(entity.id);
    }
    return false;
  }

  @override
  @deprecated
  Future<bool> deleteByIntId(int id) async {
    return _box.remove(id);
  }

  @override
  Future<void> deleteAll(List<String> uuids) async {
    for (final uuid in uuids) {
      final entity = await findById(uuid);
      if (entity != null) {
        _box.remove(entity.id);
      }
    }
  }

  @override
  Future<int> count() async {
    return _box.count();
  }

  @override
  Future<List<RegulationEntry>> findUnsynced() async {
    final query = _box.query(RegulationEntry_.syncId.isNull()).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  // ============ Transaction Operations ============

  @override
  RegulationEntry? findByIdInTx(TransactionContext ctx, String uuid) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<RegulationEntry>();
    final query = box.query(RegulationEntry_.uuid.equals(uuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  @override
  @deprecated
  RegulationEntry? findByIntIdInTx(TransactionContext ctx, int id) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<RegulationEntry>();
    return box.get(id);
  }

  @override
  List<RegulationEntry> findAllInTx(TransactionContext ctx) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<RegulationEntry>();
    return box.getAll();
  }

  @override
  RegulationEntry saveInTx(TransactionContext ctx, RegulationEntry entity,
      {bool touch = true}) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<RegulationEntry>();
    if (touch) {
      entity.touch();
    }
    box.put(entity);
    return entity;
  }

  @override
  List<RegulationEntry> saveAllInTx(
      TransactionContext ctx, List<RegulationEntry> entities) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<RegulationEntry>();
    for (final entity in entities) {
      entity.touch();
    }
    box.putMany(entities);
    return entities;
  }

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) {
    final entity = findByIdInTx(ctx, uuid);
    if (entity != null) {
      final obCtx = ctx as ObjectBoxTxContext;
      final box = obCtx.store.box<RegulationEntry>();
      return box.remove(entity.id);
    }
    return false;
  }

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) {
    final obCtx = ctx as ObjectBoxTxContext;
    final box = obCtx.store.box<RegulationEntry>();
    return box.remove(id);
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) {
    for (final uuid in uuids) {
      final entity = findByIdInTx(ctx, uuid);
      if (entity != null) {
        final obCtx = ctx as ObjectBoxTxContext;
        final box = obCtx.store.box<RegulationEntry>();
        box.remove(entity.id);
      }
    }
  }

  // ============ Semantic Search (Not Implemented) ============

  @override
  Future<List<RegulationEntry>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    throw UnimplementedError(
        'RegulationEntry does not support semantic search');
  }

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(RegulationEntry entity) generateEmbedding,
  ) async {
    // RegulationEntry doesn't have semantic search, no-op
  }

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
    final query = _box
        .query(RegulationEntry_.createdAt.betweenDate(start, end))
        .order(RegulationEntry_.createdAt)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find entries by entry type
  Future<List<RegulationEntry>> findByType(EntryType type) async {
    final query = _box
        .query(RegulationEntry_.dbEntryType.equals(type.index))
        .order(RegulationEntry_.createdAt, flags: Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  /// Find entries by severity
  Future<List<RegulationEntry>> findBySeverity(Severity severity) async {
    final query = _box
        .query(RegulationEntry_.dbSeverity.equals(severity.index))
        .order(RegulationEntry_.createdAt, flags: Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
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

  // ============ Lifecycle ============

  @override
  Future<void> close() async {
    // Store lifecycle managed externally
  }
}
