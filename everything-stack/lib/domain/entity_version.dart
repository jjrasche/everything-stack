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
/// ## Schema
/// ```dart
/// @Collection()
/// class EntityVersion {
///   String uuid;                 // Unique version ID (for sync)
///   String entityType;           // 'Note', 'Tool', etc.
///   String entityUuid;           // Which entity this versions
///   DateTime timestamp;          // When change occurred
///   int versionNumber;           // Sequential per entity (1, 2, 3...)
///   String deltaJson;            // RFC 6902 patch operations
///   List<String> changedFields;  // ['title', 'body'] - queryable
///   bool isSnapshot;             // true for initial + periodic snapshots
///   String? snapshotJson;        // Full state when isSnapshot=true
///   String? userId;              // Who made the change
///   String? changeDescription;   // Optional description
///   SyncStatus syncStatus;       // For syncing versions
/// }
/// ```
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

import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import '../core/base_entity.dart';

part 'entity_version.g.dart';

/// UUID generator for version records
const _uuidGenerator = Uuid();

@Collection()
class EntityVersion {
  /// Isar auto-generated ID.
  /// INTERNAL USE ONLY - use uuid for external references.
  Id id = Isar.autoIncrement;

  /// Unique identifier for this version record (for sync correlation)
  @Index(unique: true)
  String uuid = _uuidGenerator.v4();

  /// Type of entity this versions ('Note', 'Tool', 'Contract', etc.)
  /// Composite index: query by type → entity → time
  @Index(composite: [CompositeIndex('entityUuid'), CompositeIndex('timestamp')])
  String entityType;

  /// UUID of the entity this version belongs to
  String entityUuid;

  /// When this change occurred
  DateTime timestamp;

  /// Sequential version number per entity (1, 2, 3...)
  /// Used for snapshot frequency logic
  int versionNumber;

  /// RFC 6902 JSON Patch operations as JSON string
  /// Transforms previous state → current state
  String deltaJson;

  /// Top-level fields that changed (for queryability without parsing delta)
  /// Example: ['title', 'body']
  List<String> changedFields = [];

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
  @Enumerated(EnumType.name)
  SyncStatus syncStatus = SyncStatus.local;

  /// Constructor
  EntityVersion({
    required this.entityType,
    required this.entityUuid,
    required this.timestamp,
    required this.versionNumber,
    required this.deltaJson,
    required this.changedFields,
    required this.isSnapshot,
    this.snapshotJson,
    this.userId,
    this.changeDescription,
  });

  /// Default constructor for Isar
  EntityVersion.empty()
      : entityType = '',
        entityUuid = '',
        timestamp = DateTime.now(),
        versionNumber = 1,
        deltaJson = '',
        isSnapshot = false;
}
