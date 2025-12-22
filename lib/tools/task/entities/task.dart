/// # Task
///
/// ## What it does
/// Represents a user task/todo with due date and priority.
/// Can be owned by a user and shared with others (Ownable).
/// Tracks how it was created by tools (Invocable).
///
/// ## Key features
/// - Priority levels: high, medium, low
/// - Optional due date
/// - Completion tracking
/// - Multi-user ownership via Ownable
/// - Tool invocation tracking via Invocable
///
/// ## Usage
/// ```dart
/// final task = Task(
///   title: 'Buy groceries',
///   priority: 'medium',
///   dueDate: DateTime.now().add(Duration(days: 1)),
/// );
///
/// // Set ownership
/// task.ownerId = currentUser.id;
///
/// // Mark creation by tool
/// task.recordInvocation(
///   correlationId: event.correlationId,
///   toolName: 'task.create',
///   params: {'title': 'Buy groceries', 'priority': 'medium'},
///   confidence: 0.92,
/// );
///
/// // Complete the task
/// task.complete();
/// ```

import 'package:objectbox/objectbox.dart';

import '../../../core/base_entity.dart';
import '../../../patterns/invocable.dart';
import '../../../patterns/ownable.dart';

@Entity()
class Task extends BaseEntity with Invocable, Ownable {
  // ============ BaseEntity field overrides ============
  @override
  @Id()
  int id = 0;

  @override
  @Unique()
  String uuid = '';

  @override
  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @override
  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  @override
  String? syncId;

  // ============ Task fields ============

  /// Task title/description
  String title;

  /// Optional due date
  @Property(type: PropertyType.date)
  DateTime? dueDate;

  /// Priority: 'high', 'medium', 'low'
  String priority;

  /// Optional longer description
  String? description;

  /// Is this task completed?
  bool completed;

  /// When was it completed?
  @Property(type: PropertyType.date)
  DateTime? completedAt;

  // ============ Ownable mixin fields (stored) ============

  @override
  String? ownerId;

  @override
  List<String> sharedWith = [];

  @override
  @Transient()
  Visibility visibility = Visibility.private;

  /// Store visibility as int for ObjectBox
  int get visibilityIndex => visibility.index;
  set visibilityIndex(int value) => visibility = Visibility.values[value];

  // ============ Invocable mixin fields (stored) ============

  @override
  String? invocationCorrelationId;

  @override
  @Property(type: PropertyType.date)
  DateTime? invokedAt;

  @override
  String? invokedByTool;

  @override
  @Transient()
  Map<String, dynamic>? invocationParams;

  /// JSON string storage for invocationParams
  String? invocationParamsJson;

  @override
  double? invocationConfidence;

  @override
  String? invocationStatus;

  // ============ Constructor ============

  Task({
    required this.title,
    this.priority = 'medium',
    this.dueDate,
    this.description,
    this.completed = false,
    this.completedAt,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Computed properties ============

  /// Is this task incomplete?
  bool get isIncomplete => !completed;

  /// Is this task overdue?
  bool get isOverdue {
    if (completed || dueDate == null) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  /// Is this task due today?
  bool get isDueToday {
    if (dueDate == null) return false;
    final now = DateTime.now();
    return dueDate!.year == now.year &&
        dueDate!.month == now.month &&
        dueDate!.day == now.day;
  }

  /// Is this task due soon (within 24 hours)?
  bool get isDueSoon {
    if (dueDate == null || completed) return false;
    final now = DateTime.now();
    final diff = dueDate!.difference(now);
    return diff.inHours >= 0 && diff.inHours <= 24;
  }

  /// Is this high priority?
  bool get isHighPriority => priority == 'high';

  // ============ Actions ============

  /// Mark task as completed
  void complete() {
    if (!completed) {
      completed = true;
      completedAt = DateTime.now();
      touch();
    }
  }

  /// Mark task as incomplete (reopen)
  void reopen() {
    if (completed) {
      completed = false;
      completedAt = null;
      touch();
    }
  }

  /// Update priority
  void setPriority(String newPriority) {
    if (['high', 'medium', 'low'].contains(newPriority)) {
      priority = newPriority;
      touch();
    }
  }

  // ============ Serialization ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'title': title,
        'dueDate': dueDate?.toIso8601String(),
        'priority': priority,
        'description': description,
        'completed': completed,
        'completedAt': completedAt?.toIso8601String(),
        'ownerId': ownerId,
        'sharedWith': sharedWith,
        'visibility': visibility.name,
        ...invocableToJson(),
      };

  factory Task.fromJson(Map<String, dynamic> json) {
    final task = Task(
      title: json['title'] as String,
      priority: json['priority'] as String? ?? 'medium',
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
      description: json['description'] as String?,
      completed: json['completed'] as bool? ?? false,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
    );
    task.id = json['id'] as int? ?? 0;
    task.uuid = json['uuid'] as String? ?? '';
    task.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    task.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    task.syncId = json['syncId'] as String?;
    task.ownerId = json['ownerId'] as String?;
    task.sharedWith = (json['sharedWith'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [];
    task.visibility = Visibility.values.firstWhere(
      (v) => v.name == json['visibility'],
      orElse: () => Visibility.private,
    );
    task.invocableFromJson(json);
    return task;
  }
}
