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

import 'package:json_annotation/json_annotation.dart';
import 'base_entity.dart';

// JSON serialization generated code
part 'edge.g.dart';

@JsonSerializable()
class Edge extends BaseEntity {
  // ============ BaseEntity field overrides ============
  /// Database auto-generated ID (inherited from BaseEntity)
  @override
  int id = 0;

  /// Universal unique identifier (inherited from BaseEntity)
  @override
  String uuid = '';

  /// When entity was created (inherited from BaseEntity)
  @override
  DateTime createdAt = DateTime.now();

  /// When entity was last modified (inherited from BaseEntity)
  @override
  DateTime updatedAt = DateTime.now();

  /// For sync identification across devices (inherited from BaseEntity)
  @override
  String? syncId;

  /// Source entity type name (e.g., 'Note', 'Project')
  String sourceType;

  /// Source entity UUID (indexed in adapters for fast lookup)
  String sourceUuid;

  /// Target entity type name (e.g., 'Project', 'Tag')
  String targetType;

  /// Target entity UUID (indexed in adapters for fast lookup)
  String targetUuid;

  /// Type of relationship (e.g., 'belongs_to', 'references', 'similar_to')
  /// Indexed in adapters to support filtering by edge type
  String edgeType;

  /// Optional metadata about the edge (stored as JSON string)
  String? metadata;

  /// Who created this edge (user ID or 'system' for AI-generated)
  String? createdBy;

  /// Sync status stored as int (enum index)
  @JsonKey(includeFromJson: false, includeToJson: false)
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

  // ============ JSON Serialization ============

  Map<String, dynamic> toJson() => _$EdgeToJson(this);
  factory Edge.fromJson(Map<String, dynamic> json) => _$EdgeFromJson(json);

  @override
  String toString() =>
      'Edge($sourceUuid -[$edgeType]-> $targetUuid, createdAt: $createdAt)';
}
