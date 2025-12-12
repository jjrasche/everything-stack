/// Web BaseEntity without ObjectBox annotations (plain Dart)
library;

import 'package:uuid/uuid.dart';
import '../../services/sync_service.dart' show SyncStatus;

export '../../services/sync_service.dart' show SyncStatus;

const _uuidGenerator = Uuid();

abstract class BaseEntity {
  /// Database auto-generated ID.
  /// INTERNAL USE ONLY - never reference outside persistence layer.
  /// Use [uuid] for all external identification.
  int id = 0;

  /// Universal unique identifier for this entity.
  /// Use for HNSW index, edges, sync, cross-type lookups, APIs.
  /// Auto-generated on entity creation.
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

  /// IndexedDB-specific: Sync status as int for storage
  int get dbSyncStatus => syncStatus.index;
  set dbSyncStatus(int value) => syncStatus = SyncStatus.values[value];
}
