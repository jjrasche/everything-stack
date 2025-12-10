/// # Edge Collection
///
/// ## What it does
/// Isar collection for storing entity-to-entity connections.
/// Implements the Edge entity from the Edgeable pattern with persistence.
///
/// ## Schema
/// - uuid: Unique ID for sync (inherited from BaseEntity)
/// - Composite key (domain): sourceUuid + targetUuid + edgeType
/// - Uniqueness enforced at repository level (Isar composite unique not supported)
/// - Indexed fields: uuid, sourceUuid, targetUuid, edgeType, syncStatus
/// - Metadata stored as JSON string
/// - Timestamps: createdAt, updatedAt (inherited from BaseEntity)
///
/// ## Known limitation
/// Isar 3.1.0 doesn't support composite unique constraints.
/// Repository checks for duplicates before insert. Low risk of race condition
/// in single-user offline-first app, but theoretically possible with concurrent writes.
///
/// ## Testing approach
/// Test through EdgeRepository. Verify CRUD operations,
/// unique constraint enforcement, indexed queries.

import 'package:isar/isar.dart';
import '../core/base_entity.dart';

part 'edge.g.dart';

@Collection()
class Edge extends BaseEntity {
  // ============ Isar field overrides ============
  // Override uuid with @Index for O(1) findByUuid() lookups
  // (Isar doesn't inherit indexed fields from base classes)
  @Index(unique: true)
  @override
  String uuid = '';

  // Override syncStatus with @enumerated annotation
  @override
  @enumerated
  SyncStatus syncStatus = SyncStatus.local;

  /// Source entity type name (e.g., 'Note', 'Project')
  String sourceType;

  /// Source entity UUID (indexed for fast lookup)
  @Index()
  String sourceUuid;

  /// Target entity type name (e.g., 'Project', 'Tag')
  String targetType;

  /// Target entity UUID (indexed for fast lookup)
  @Index()
  String targetUuid;

  /// Type of relationship (e.g., 'belongs_to', 'references', 'similar_to')
  /// Indexed to support filtering by edge type
  @Index()
  String edgeType;

  /// Optional metadata about the edge (stored as JSON string)
  String? metadata;

  /// Who created this edge (user ID or 'system' for AI-generated)
  String? createdBy;

  Edge({
    required this.sourceType,
    required this.sourceUuid,
    required this.targetType,
    required this.targetUuid,
    required this.edgeType,
    this.metadata,
    this.createdBy,
  }) {
    // Ensure uuid is generated if not set
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  /// Get composite key for uniqueness checking
  String get compositeKey => '$sourceUuid|$targetUuid|$edgeType';

  @override
  String toString() =>
      'Edge($sourceUuid -[$edgeType]-> $targetUuid, createdAt: $createdAt)';
}
