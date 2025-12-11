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
import 'package:uuid/uuid.dart';
import '../core/base_entity.dart';

/// UUID generator for version records
const _uuidGenerator = Uuid();

@Entity()
class EntityVersion {
  /// Database auto-generated ID.
  /// INTERNAL USE ONLY - use uuid for external references.
  @Id()
  int id = 0;

  /// Unique identifier for this version record (for sync correlation)
  @Unique(onConflict: ConflictStrategy.replace)
  String uuid = _uuidGenerator.v4();

  /// Type of entity this versions ('Note', 'Tool', 'Contract', etc.)
  @Index()
  String entityType;

  /// UUID of the entity this version belongs to
  @Index()
  String entityUuid;

  /// When this change occurred
  @Property(type: PropertyType.date)
  DateTime timestamp;

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

  /// Sync status for this version record
  /// Marked @Transient - use dbSyncStatus for storage
  @Transient()
  SyncStatus syncStatus = SyncStatus.local;

  /// Sync status stored as int (enum index)
  int get dbSyncStatus => syncStatus.index;
  set dbSyncStatus(int value) => syncStatus = SyncStatus.values[value];

  /// Constructor
  EntityVersion({
    required this.entityType,
    required this.entityUuid,
    required this.timestamp,
    required this.versionNumber,
    required this.deltaJson,
    List<String>? changedFields,
    required this.isSnapshot,
    this.snapshotJson,
    this.userId,
    this.changeDescription,
  }) {
    if (changedFields != null) {
      this.changedFields = changedFields;
    }
  }

  /// Default constructor for ObjectBox (no args needed)
  EntityVersion.empty()
      : entityType = '',
        entityUuid = '',
        timestamp = DateTime.now(),
        versionNumber = 1,
        deltaJson = '',
        isSnapshot = false;
}
