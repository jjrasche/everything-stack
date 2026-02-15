/// ## Schema addition
/// ```dart
/// DateTime? dueAt;
/// DateTime? scheduledAt;
/// DateTime? completedAt;
/// String? recurrenceRule; // iCal RRULE format
/// ```
///
/// ## Usage
/// ```dart
/// class Task extends BaseEntity with Temporal {
///   String title;
/// }
///
/// // Set due date
/// task.dueAt = DateTime.now().add(Duration(days: 7));
///
/// // Query by time range
/// final dueThisWeek = await taskRepo.findDueBetween(
///   DateTime.now(),
///   DateTime.now().add(Duration(days: 7)),
/// );
///
/// // Recurring task
/// task.recurrenceRule = 'FREQ=WEEKLY;BYDAY=MO,WE,FR';
/// ```
///
/// ## Integrates with
/// - Ownable: "My tasks due this week"
/// - Embeddable: "Find tasks similar to X due soon"

mixin Temporal {
  /// When this item is due (deadline)
  DateTime? dueAt;

  /// When this item is scheduled to occur
  DateTime? scheduledAt;

  /// When this item was completed
  DateTime? completedAt;

  /// iCal RRULE for recurring items
  /// Examples:
  /// - Daily: 'FREQ=DAILY'
  /// - Weekly on Mon/Wed/Fri: 'FREQ=WEEKLY;BYDAY=MO,WE,FR'
  /// - Monthly on 1st: 'FREQ=MONTHLY;BYMONTHDAY=1'
  String? recurrenceRule;

  /// Is this item overdue?
  bool get isOverdue {
    if (dueAt == null || completedAt != null) return false;
    return DateTime.now().isAfter(dueAt!);
  }

  /// Is this item due within the given duration?
  bool isDueSoon(Duration window) {
    if (dueAt == null || completedAt != null) return false;
    return dueAt!.isBefore(DateTime.now().add(window));
  }

  /// Mark as completed now
  void complete() {
    completedAt = DateTime.now();
  }

  /// Is this a recurring item?
  bool get isRecurring => recurrenceRule != null && recurrenceRule!.isNotEmpty;

  /// Get next occurrence for recurring item.
  /// Returns null if not recurring or no more occurrences.
  DateTime? getNextOccurrence() {
    if (!isRecurring) return null;
    // TODO: Implement RRULE parsing
    // Consider using a library like rrule
    throw UnimplementedError('RRULE parsing not yet implemented');
  }
}
