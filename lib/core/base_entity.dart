/// # BaseEntity
///
/// ## What it does
/// Foundation for all domain entities. Provides common fields and lifecycle.
///
/// ## What it enables
/// - Consistent entity structure across domain
/// - Common fields (uuid, timestamps) handled once
/// - Pattern mixins compose cleanly
/// - Repository operations work generically
/// - Cross-type identification via uuid
///
/// ## Identifiers
/// - `id`: Database auto-increment ID. NEVER use outside persistence layer.
/// - `uuid`: Universal identifier for the entity. Use for:
///   - HNSW index keys (O(1) semantic search)
///   - Edge connections (source/target UUIDs)
///   - Sync correlation (device-independent ID)
///   - Cross-type lookups
///   - API references
///
/// ## ObjectBox Annotations
/// Concrete entity classes must add ObjectBox annotations:
/// - `@Entity()` on the class
/// - `@Unique(onConflict: ConflictStrategy.replace)` on uuid override
///
/// Example:
/// ```dart
/// @Entity()
/// class Tool extends BaseEntity with Embeddable {
///   @Unique(onConflict: ConflictStrategy.replace)
///   @override
///   String uuid = '';
///
///   String name;
///   String description;
///
///   Tool({required this.name, required this.description}) {
///     if (uuid.isEmpty) uuid = super.uuid;
///   }
///
///   @override
///   String toEmbeddingInput() => '$name $description';
/// }
/// ```
///
/// ## Testing approach
/// BaseEntity itself needs no testing. Test domain entities that extend it.
/// Verify timestamps update correctly, uuids generate uniquely.

import 'package:objectbox/objectbox.dart';
import 'package:uuid/uuid.dart';
import '../services/sync_service.dart' show SyncStatus;

// Re-export SyncStatus for convenience
export '../services/sync_service.dart' show SyncStatus;

/// UUID generator instance
const _uuidGenerator = Uuid();

abstract class BaseEntity {
  /// Database auto-generated ID.
  /// INTERNAL USE ONLY - never reference outside persistence layer.
  /// Use [uuid] for all external identification.
  ///
  /// ObjectBox assigns this automatically when id = 0.
  @Id()
  int id = 0;

  /// Universal unique identifier for this entity.
  /// Use for HNSW index, edges, sync, cross-type lookups, APIs.
  /// Auto-generated on entity creation.
  ///
  /// Concrete classes should override with @Unique annotation.
  String uuid = _uuidGenerator.v4();

  /// When entity was created
  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  /// When entity was last modified
  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  /// Update timestamp before save
  void touch() {
    updatedAt = DateTime.now();
  }

  /// For sync identification across devices.
  /// Maps to remote database ID (e.g., Supabase row ID).
  String? syncId;

  /// Sync status: local, syncing, synced, conflict
  /// Stored as int (enum index) in ObjectBox.
  SyncStatus syncStatus = SyncStatus.local;
}
