/// Represents an entity queued for async enrichment processing.
/// Tracks which enrichment steps are pending, completed, or in-progress.

import 'base_entity.dart';

class EnrichmentQueueItem extends BaseEntity {
  // ============ BaseEntity field overrides ============
  @override
  int id = 0;

  @override
  String uuid = '';

  @override
  DateTime createdAt = DateTime.now();

  @override
  DateTime updatedAt = DateTime.now();

  @override
  String? syncId;

  // ============ EnrichmentQueueItem Fields ============

  /// UUID of the entity being enriched
  final String entityUuid;

  /// Type name of the entity (e.g., 'Invocation', 'Task')
  final String entityType;

  /// Steps still to execute
  List<String> pendingSteps;

  /// Steps already completed
  List<String> completedSteps;

  /// Step currently being processed (null if idle)
  /// Non-null indicates this item is locked for processing
  String? currentStep;

  /// Number of retry attempts
  int retries;

  /// Last error message (if any)
  String? lastError;

  /// When this item was added to queue
  DateTime enqueuedAt;

  // ============ String Storage for Querying ============

  /// Comma-separated pendingSteps for ObjectBox/IndexedDB queries
  String get pendingStepsStr => pendingSteps.join(',');
  set pendingStepsStr(String value) {
    pendingSteps = value.isEmpty ? [] : value.split(',');
  }

  /// Comma-separated completedSteps for ObjectBox/IndexedDB queries
  String get completedStepsStr => completedSteps.join(',');
  set completedStepsStr(String value) {
    completedSteps = value.isEmpty ? [] : value.split(',');
  }

  // ============ Computed Properties ============

  /// True when all steps are done (nothing pending, nothing in progress)
  bool get isComplete => pendingSteps.isEmpty && currentStep == null;

  /// Check if a step can run (all its dependencies completed)
  bool canRunStep(String stepType, List<String> requiredSteps) {
    // Step must be pending
    if (!pendingSteps.contains(stepType)) return false;
    // Must not be currently processing another step
    if (currentStep != null) return false;
    // All required steps must be completed
    return requiredSteps.every((step) => completedSteps.contains(step));
  }

  // ============ Constructor ============

  EnrichmentQueueItem({
    required this.entityUuid,
    required this.entityType,
    required this.pendingSteps,
    required this.completedSteps,
    this.currentStep,
    this.retries = 0,
    this.lastError,
    DateTime? enqueuedAt,
  }) : enqueuedAt = enqueuedAt ?? DateTime.now() {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Serialization ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'entityUuid': entityUuid,
        'entityType': entityType,
        'pendingSteps': pendingSteps,
        'completedSteps': completedSteps,
        'currentStep': currentStep,
        'retries': retries,
        'lastError': lastError,
        'enqueuedAt': enqueuedAt.toIso8601String(),
      };

  factory EnrichmentQueueItem.fromJson(Map<String, dynamic> json) {
    final item = EnrichmentQueueItem(
      entityUuid: json['entityUuid'] as String,
      entityType: json['entityType'] as String,
      pendingSteps: (json['pendingSteps'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      completedSteps: (json['completedSteps'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      currentStep: json['currentStep'] as String?,
      retries: json['retries'] as int? ?? 0,
      lastError: json['lastError'] as String?,
      enqueuedAt: json['enqueuedAt'] != null
          ? DateTime.parse(json['enqueuedAt'] as String)
          : null,
    );
    item.id = json['id'] as int? ?? 0;
    item.uuid = json['uuid'] as String? ?? '';
    item.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    item.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    item.syncId = json['syncId'] as String?;
    return item;
  }

  @override
  String toString() =>
      'EnrichmentQueueItem(uuid: $uuid, entityUuid: $entityUuid, '
      'entityType: $entityType, pending: $pendingSteps, '
      'completed: $completedSteps, current: $currentStep)';
}
