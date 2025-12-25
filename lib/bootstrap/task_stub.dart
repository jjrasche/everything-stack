/// # Task Stub (Web)
///
/// Stub implementation of Task for web platform.
/// On web, Tasks are only used through the repository.

class Task {
  final String title;
  final String priority;
  final DateTime? dueDate;
  final String? description;

  int id = 0;
  String uuid = '';
  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();
  String? syncId;
  bool completed = false;
  DateTime? completedAt;
  String? ownerId;
  List<String> sharedWith = [];

  Task({
    required this.title,
    this.priority = 'medium',
    this.dueDate,
    this.description,
  });

  void complete() {
    completed = true;
    completedAt = DateTime.now();
  }

  void touch() {
    updatedAt = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'uuid': uuid,
    'title': title,
    'priority': priority,
    'dueDate': dueDate?.toIso8601String(),
    'description': description,
    'completed': completed,
  };

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      title: json['title'] as String,
      priority: json['priority'] as String? ?? 'medium',
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
      description: json['description'] as String?,
    );
  }
}
