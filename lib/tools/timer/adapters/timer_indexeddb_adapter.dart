/// # TimerIndexedDBAdapter
///
/// ## What it does
/// IndexedDB implementation of PersistenceAdapter for Timer entities.
/// Handles CRUD operations for web platform.
///
/// ## Usage
/// ```dart
/// final db = await idbFactory.open('my_database');
/// final adapter = TimerIndexedDBAdapter(db);
/// final repo = TimerRepository(adapter: adapter);
/// ```

import 'package:idb_shim/idb.dart';
import '../../../persistence/indexeddb/base_indexeddb_adapter.dart';
import '../entities/timer.dart';

class TimerIndexedDBAdapter extends BaseIndexedDBAdapter<Timer> {
  TimerIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => 'timers';

  @override
  Timer fromJson(Map<String, dynamic> json) => Timer.fromJson(json);

  // ============ Timer-Specific Query Methods ============

  /// Find active timers (not fired, still running)
  Future<List<Timer>> findActive() async {
    final all = await findAll();
    final now = DateTime.now();
    return all.where((timer) {
      return !timer.fired && timer.endsAt.isAfter(now);
    }).toList();
  }

  /// Find expired timers (past endsAt but not marked as fired)
  Future<List<Timer>> findExpired() async {
    final all = await findAll();
    final now = DateTime.now();
    return all.where((timer) {
      return !timer.fired && timer.endsAt.isBefore(now);
    }).toList();
  }

  /// Find fired timers
  Future<List<Timer>> findFired() async {
    final all = await findAll();
    return all.where((timer) => timer.fired).toList();
  }

  /// Find timer by label
  Future<Timer?> findByLabel(String label) async {
    final all = await findAll();
    try {
      return all.firstWhere(
        (timer) => timer.label == label && !timer.fired,
      );
    } catch (e) {
      return null;
    }
  }
}
