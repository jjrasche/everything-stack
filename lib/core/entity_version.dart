/// # EntityVersion
///
/// ## What it does
/// Stores historical changes for all entity types using Type 4 SCD with deltas.
/// Single collection for all versioned entities, enabling cross-entity audit queries.
///
/// ## What it enables
/// - Point-in-time reconstruction: "What was this Note on Dec 1?"
/// - Audit trail: "Who changed what and when?"
/// - Rollback: "Restore to version N"
/// - Collaboration: Field-level merge detection
/// - Sync efficiency: Transmit deltas, not full entities
/// - AI integration: Semantic understanding of change streams
///
/// ## Architecture
/// - Domain entities contain ONLY current state
/// - EntityVersion stores ALL historical changes for ALL entity types
/// - Changes stored as JSON Patch deltas (RFC 6902)
/// - Periodic snapshots for reconstruction efficiency (every N deltas)
///
/// ## Reconstruction
/// Forward-only: Find nearest snapshot before target → apply deltas forward → done
///
/// Example timeline:
/// ```
/// [S₀ v1]--d2--d3--d4--[S₁ v5]--d6--d7--CURRENT
///
/// To reconstruct at v6:
/// - Find snapshot S₁ (v5)
/// - Apply d6
/// - Return reconstructed state
/// ```
///
/// ## Testing approach
/// Integration tests:
/// - Create entity, record multiple changes
/// - Verify version numbers increment
/// - Verify deltas stored correctly
/// - Verify snapshots created at frequency intervals
/// - Test reconstruction at various points in time
/// - Test pruning old versions
///
/// ## Integrates with
/// - Versionable mixin: Entities opt-in to versioning
/// - VersionRepository: Manages version records
/// - EntityRepository: Calls recordChange() on save for Versionable entities
/// - Sync: Versions sync to remote database

import 'package:objectbox/objectbox.dart';
import 'package:json_annotation/json_annotation.dart';
import 'base_entity.dart';

// JSON serialization generated code
part 'entity_version.g.dart';

@Entity()
@JsonSerializable()
class EntityVersion extends BaseEntity {
  // ============ ObjectBox field overrides ============
  // Override id with @Id() for ObjectBox
  @override
  @Id()
  int id = 0;

  /// Unique identifier for this version record (for sync correlation)
  @Unique(onConflict: ConflictStrategy.replace)
  @override
  String uuid = '';

  // ============ BaseEntity field overrides ============
  /// When this version was created (versions are immutable)
  @Property(type: PropertyType.date)
  @override
  DateTime createdAt = DateTime.now();

  /// Same as createdAt for versions (immutable records)
  @Property(type: PropertyType.date)
  @override
  DateTime updatedAt = DateTime.now();

  /// For sync identification across devices
  @override
  String? syncId;

  /// Type of entity this versions ('Note', 'Tool', 'Contract', etc.)
  @Index()
  String entityType;

  /// UUID of the entity this version belongs to
  @Index()
  String entityUuid;

  /// Alias for createdAt - when this version was recorded.
  /// Version records are immutable, so timestamp == createdAt.
  DateTime get timestamp => createdAt;
  set timestamp(DateTime value) {
    createdAt = value;
    updatedAt = value; // Versions are immutable
  }

  /// Sequential version number per entity (1, 2, 3...)
  /// Used for snapshot frequency logic
  int versionNumber;

  /// RFC 6902 JSON Patch operations as JSON string
  /// Transforms previous state → current state
  String deltaJson;

  /// Top-level fields that changed (for queryability without parsing delta)
  /// Example: ['title', 'body']
  /// Stored as comma-separated string in ObjectBox
  @Transient()
  List<String> changedFields = [];

  @JsonKey(includeFromJson: false, includeToJson: false)
  String get dbChangedFields => changedFields.join(',');
  set dbChangedFields(String value) =>
      changedFields = value.isEmpty ? [] : value.split(',');

  /// True for initial creation + periodic snapshots (every N versions)
  bool isSnapshot;

  /// Full entity state as JSON string when isSnapshot=true
  /// Used as starting point for forward reconstruction
  String? snapshotJson;

  /// User ID of who made this change
  String? userId;

  /// Optional human-readable description of the change
  String? changeDescription;

  /// Sync status stored as int (enum index)
  @JsonKey(includeFromJson: false, includeToJson: false)
  int get dbSyncStatus => syncStatus.index;
  set dbSyncStatus(int value) => syncStatus = SyncStatus.values[value];

  /// Constructor
  EntityVersion({
    required this.entityType,
    required this.entityUuid,
    required DateTime timestamp,
    required this.versionNumber,
    required this.deltaJson,
    List<String>? changedFields,
    required this.isSnapshot,
    this.snapshotJson,
    this.userId,
    this.changeDescription,
  }) {
    // Set timestamps via the timestamp setter
    this.timestamp = timestamp;
    // Generate uuid if not set
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
    if (changedFields != null) {
      this.changedFields = changedFields;
    }
  }

  /// Default constructor for ObjectBox (no args needed)
  EntityVersion.empty()
      : entityType = '',
        entityUuid = '',
        versionNumber = 1,
        deltaJson = '',
        isSnapshot = false {
    // uuid generated by BaseEntity
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ JSON Serialization ============

  Map<String, dynamic> toJson() => _$EntityVersionToJson(this);
  factory EntityVersion.fromJson(Map<String, dynamic> json) =>
      _$EntityVersionFromJson(json);
}
