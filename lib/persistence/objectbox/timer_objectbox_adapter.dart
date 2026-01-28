/// # TimerObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for Timer entities.
/// Uses wrapper pattern (TimerOB) to keep domain entity clean.
///
/// ## Pattern
/// - Domain entity (Timer) has NO ObjectBox decorators
/// - Wrapper class (TimerOB) has ALL decorators
/// - Adapter converts between Timer <-> TimerOB
///
/// ## Usage
/// ```dart
/// final store = await openStore();
/// final adapter = TimerObjectBoxAdapter(store);
/// final repo = TimerRepository(adapter: adapter);
/// ```

import 'package:objectbox/objectbox.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../tools/timer/entities/timer.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/timer_ob.dart';

class TimerObjectBoxAdapter extends BaseObjectBoxAdapter<Timer, TimerOB>
    implements PersistenceAdapter<Timer> {
  TimerObjectBoxAdapter(Store store) : super(store);

  @override
  TimerOB toOB(Timer entity) => TimerOB.fromTimer(entity);

  @override
  Timer fromOB(TimerOB ob) => ob.toTimer();

  @override
  Condition<TimerOB> uuidEqualsCondition(String uuid) =>
      TimerOB_.uuid.equals(uuid);

  @override
  Condition<TimerOB> syncStatusLocalCondition() => TimerOB_.syncId.isNull();

  // ============ Timer-Specific Query Methods ============

  /// Find active timers (not fired, still running)
  Future<List<Timer>> findActive() async {
    final now = DateTime.now();
    final query = box
        .query(
          TimerOB_.fired.equals(false) &
              TimerOB_.endsAt.greaterThan(now.millisecondsSinceEpoch),
        )
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  /// Find expired timers (past endsAt but not marked as fired)
  Future<List<Timer>> findExpired() async {
    final now = DateTime.now();
    final query = box
        .query(
          TimerOB_.fired.equals(false) &
              TimerOB_.endsAt.lessOrEqual(now.millisecondsSinceEpoch),
        )
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  /// Find fired timers
  Future<List<Timer>> findFired() async {
    final query = box.query(TimerOB_.fired.equals(true)).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  /// Find timer by label
  Future<Timer?> findByLabel(String label) async {
    final query = box
        .query(
          TimerOB_.label.equals(label) & TimerOB_.fired.equals(false),
        )
        .build();
    try {
      final ob = query.findFirst();
      return ob != null ? fromOB(ob) : null;
    } finally {
      query.close();
    }
  }
}
