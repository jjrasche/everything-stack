/// # TimerOB - ObjectBox Wrapper
///
/// ObjectBox-decorated version of Timer domain entity.
/// Contains all ObjectBox decorators (@Entity, @Id, @Property, etc.)
///
/// This wrapper allows Timer domain entities to remain pure Dart,
/// while providing ObjectBox persistence for native platforms.

import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/tools/timer/entities/timer.dart';

@Entity()
class TimerOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // ============ Timer-specific fields ============

  String label;
  int durationSeconds;

  @Property(type: PropertyType.date)
  DateTime setAt;

  @Property(type: PropertyType.date)
  DateTime endsAt;

  bool fired;

  @Property(type: PropertyType.date)
  DateTime? firedAt;

  // ============ Constructor ============

  TimerOB({
    required this.label,
    required this.durationSeconds,
    required this.setAt,
    required this.endsAt,
    this.fired = false,
    this.firedAt,
  });

  // ============ Conversion to/from domain entity ============

  /// Convert from domain entity to ObjectBox wrapper
  factory TimerOB.fromTimer(Timer timer) {
    return TimerOB(
      label: timer.label,
      durationSeconds: timer.durationSeconds,
      setAt: timer.setAt,
      endsAt: timer.endsAt,
      fired: timer.fired,
      firedAt: timer.firedAt,
    )
      ..id = timer.id
      ..uuid = timer.uuid
      ..createdAt = timer.createdAt
      ..updatedAt = timer.updatedAt
      ..syncId = timer.syncId;
  }

  /// Convert from ObjectBox wrapper to domain entity
  Timer toTimer() {
    final timer = Timer(
      label: label,
      durationSeconds: durationSeconds,
      setAt: setAt,
      endsAt: endsAt,
      fired: fired,
      firedAt: firedAt,
    );
    timer.id = id;
    timer.uuid = uuid;
    timer.createdAt = createdAt;
    timer.updatedAt = updatedAt;
    timer.syncId = syncId;
    return timer;
  }
}
