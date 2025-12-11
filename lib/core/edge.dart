/// # Edge Entity
///
/// ## What it does
/// Entity for storing entity-to-entity connections.
/// Implements the Edge entity from the Edgeable pattern with persistence.
///
/// ## Schema
/// - uuid: Unique ID for sync (inherited from BaseEntity)
/// - Composite key (domain): sourceUuid + targetUuid + edgeType
/// - Uniqueness enforced at repository level
/// - Indexed fields: uuid, sourceUuid, targetUuid, edgeType
/// - Metadata stored as JSON string
/// - Timestamps: createdAt, updatedAt (inherited from BaseEntity)
///
/// ## Testing approach
/// Test through EdgeRepository. Verify CRUD operations,
/// unique constraint enforcement, indexed queries.

import 'package:objectbox/objectbox.dart';
import 'base_entity.dart';

@Entity()
class Edge extends BaseEntity {
  // ============ ObjectBox field overrides ============
  // Override id with @Id() for ObjectBox
  @override
  @Id()
  int id = 0;

  @Unique(onConflict: ConflictStrategy.replace)
  @override
  String uuid = '';

  // ============ BaseEntity field overrides ============
  /// When entity was created
  @Property(type: PropertyType.date)
  @override
  DateTime createdAt = DateTime.now();

  /// When entity was last modified
  @Property(type: PropertyType.date)
  @override
  DateTime updatedAt = DateTime.now();

  /// For sync identification across devices
  @override
  String? syncId;

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

  /// Sync status stored as int (enum index)
  int get dbSyncStatus => syncStatus.index;
  set dbSyncStatus(int value) => syncStatus = SyncStatus.values[value];

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
