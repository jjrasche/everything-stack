/// Native (mobile/desktop) BaseEntity with ObjectBox annotations
library;

import 'package:objectbox/objectbox.dart';
import 'package:uuid/uuid.dart';
import '../../services/sync_service.dart' show SyncStatus;

export '../../services/sync_service.dart' show SyncStatus;

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
