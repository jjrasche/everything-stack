import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/core/enrichment_queue_item.dart';

@Entity()
class EnrichmentQueueItemOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  /// UUID of the entity being enriched
  @Index()
  String entityUuid;

  /// Type name of the entity (e.g., 'Invocation', 'Task')
  String entityType;

  /// Comma-separated pending steps for queries
  /// e.g., "semantic_enrichment,categorization"
  String pendingStepsStr;

  /// Comma-separated completed steps for queries
  String completedStepsStr;

  /// Step currently being processed (null if idle)
  /// Non-null = this item is locked for processing
  @Index()
  String? currentStep;

  /// Number of retry attempts
  int retries;

  /// Last error message (if any)
  String? lastError;

  /// When this item was added to queue
  @Property(type: PropertyType.date)
  DateTime enqueuedAt;

  EnrichmentQueueItemOB({
    required this.entityUuid,
    required this.entityType,
    required this.pendingStepsStr,
    required this.completedStepsStr,
    this.currentStep,
    this.retries = 0,
    this.lastError,
    DateTime? enqueuedAt,
  }) : enqueuedAt = enqueuedAt ?? DateTime.now();

  factory EnrichmentQueueItemOB.fromItem(EnrichmentQueueItem item) {
    return EnrichmentQueueItemOB(
      entityUuid: item.entityUuid,
      entityType: item.entityType,
      pendingStepsStr: item.pendingStepsStr,
      completedStepsStr: item.completedStepsStr,
      currentStep: item.currentStep,
      retries: item.retries,
      lastError: item.lastError,
      enqueuedAt: item.enqueuedAt,
    )
      ..id = item.id
      ..uuid = item.uuid
      ..createdAt = item.createdAt
      ..updatedAt = item.updatedAt
      ..syncId = item.syncId;
  }

  EnrichmentQueueItem toItem() {
    final item = EnrichmentQueueItem(
      entityUuid: entityUuid,
      entityType: entityType,
      pendingSteps: pendingStepsStr.isEmpty ? [] : pendingStepsStr.split(','),
      completedSteps:
          completedStepsStr.isEmpty ? [] : completedStepsStr.split(','),
      currentStep: currentStep,
      retries: retries,
      lastError: lastError,
      enqueuedAt: enqueuedAt,
    )
      ..id = id
      ..uuid = uuid
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncId = syncId;
    return item;
  }
}
