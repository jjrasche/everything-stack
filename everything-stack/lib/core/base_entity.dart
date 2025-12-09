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
/// - `id`: Isar's internal auto-increment ID. NEVER use outside persistence layer.
/// - `uuid`: Universal identifier for the entity. Use for:
///   - HNSW index keys (O(1) semantic search)
///   - Edge connections (source/target UUIDs)
///   - Sync correlation (device-independent ID)
///   - Cross-type lookups
///   - API references
///
/// ## IMPORTANT: Override uuid with @Index in Concrete Classes
/// Each @Collection() class MUST override the uuid field with @Index annotation.
/// Isar doesn't inherit indexed fields from base classes, so explicit override
/// is required for O(1) findByUuid() lookups. This is the same pattern as
/// the @enumerated override on syncStatus.
///
/// Example:
/// ```dart
/// @Collection()
/// class Tool extends BaseEntity with Embeddable {
///   @Index(unique: true)
///   @override
///   late String uuid;
///
///   String name;
///   String description;
///
///   Tool() {
///     uuid = Uuid().v4();  // Override default if needed
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

import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

/// UUID generator instance
const _uuidGenerator = Uuid();

abstract class BaseEntity {
  /// Isar auto-generated ID.
  /// INTERNAL USE ONLY - never reference outside persistence layer.
  /// Use [uuid] for all external identification.
  Id id = Isar.autoIncrement;

  /// Universal unique identifier for this entity.
  /// Use for HNSW index, edges, sync, cross-type lookups, APIs.
  /// Auto-generated on entity creation.
  @Index(unique: true)
  String uuid = _uuidGenerator.v4();

  /// When entity was created
  DateTime createdAt = DateTime.now();

  /// When entity was last modified
  DateTime updatedAt = DateTime.now();

  /// Update timestamp before save
  void touch() {
    updatedAt = DateTime.now();
  }

  /// For sync identification across devices.
  /// Maps to remote database ID (e.g., Supabase row ID).
  String? syncId;

  /// Sync status: local, syncing, synced, conflict
  SyncStatus syncStatus = SyncStatus.local;
}

enum SyncStatus {
  local, // Only exists locally
  syncing, // Currently uploading
  synced, // Matches remote
  conflict, // Local and remote differ
}
