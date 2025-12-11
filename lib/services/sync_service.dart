/// # SyncService
///
/// ## What it does
/// Synchronizes local entities and blobs with Supabase.
/// Respects device connectivity (offline awareness).
/// Tracks per-entity sync status and resolves conflicts.
///
/// ## What it enables
/// - Offline-first operation with eventual consistency
/// - Automatic push of local changes when online
/// - Automatic pull of remote changes
/// - Blob sync on WiFi only (preserve bandwidth)
/// - Last-write-wins conflict resolution
/// - Per-entity sync status visibility
///
/// ## Implementations
/// - MockSyncService: In-memory for testing, controllable offline/WiFi state
/// - SupabaseSyncService: Real Supabase integration (stub)
///
/// ## Usage
/// ```dart
/// // Setup
/// SyncService.instance = SupabaseSyncService();
/// await SyncService.instance.initialize();
///
/// // Sync everything pending
/// await SyncService.instance.syncAll();
///
/// // Sync specific entity
/// final status = await SyncService.instance.syncEntity('note-uuid');
/// if (status == SyncStatus.conflict) {
///   // Handle conflict
///   await SyncService.instance.resolveConflict('note-uuid', keepLocal: true);
/// }
///
/// // Sync blobs (WiFi only)
/// final success = await SyncService.instance.syncBlobs();
///
/// // Check status
/// final status = SyncService.instance.getSyncStatus('note-uuid');
///
/// // Listen for changes
/// SyncService.instance.onSyncStatusChanged.listen((event) {
///   print('${event.entityUuid} is now ${event.status}');
/// });
/// ```
///
/// ## Testing approach
/// Mock implementation controls offline/WiFi state for testing.
/// Real implementation tested with actual Supabase instance.

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============ Enums and Data Types ============

/// Per-entity sync status
enum SyncStatus {
  local, // Only exists locally, not synced yet
  syncing, // Currently syncing
  synced, // Successfully synced to remote
  conflict, // Conflict detected, needs resolution
}

/// Sync status change event
class SyncEvent {
  /// UUID of the entity that changed
  final String entityUuid;

  /// Type of entity (e.g., 'Note', 'Attachment')
  final String entityType;

  /// New sync status
  final SyncStatus status;

  /// When the change occurred
  final DateTime timestamp;

  SyncEvent({
    required this.entityUuid,
    required this.entityType,
    required this.status,
    required this.timestamp,
  });

  @override
  String toString() =>
      'SyncEvent($entityUuid, $entityType, $status, $timestamp)';
}

// ============ Abstract Interface ============

/// Synchronizes local entities and blobs with Supabase.
abstract class SyncService {
  /// Global singleton instance (defaults to mock for safe testing)
  static SyncService instance = MockSyncService();

  /// Is the service ready (initialized)?
  bool get isReady;

  /// Stream of sync status changes
  Stream<SyncEvent> get onSyncStatusChanged;

  /// Sync all entities pending sync
  /// Returns number synced, or null if offline
  Future<int?> syncAll();

  /// Sync specific entity by UUID
  /// Returns final status, or null if offline
  Future<SyncStatus?> syncEntity(String uuid);

  /// Sync blobs (WiFi-only)
  /// Returns true if synced, false if no WiFi
  Future<bool> syncBlobs();

  /// Get current sync status of entity
  /// Returns local if not tracked
  SyncStatus getSyncStatus(String uuid);

  /// Resolve sync conflict
  /// keepLocal: true = prefer local version, false = prefer remote
  Future<void> resolveConflict(String uuid, {required bool keepLocal});

  /// Initialize service (connect to Supabase, etc.)
  Future<void> initialize();

  /// Dispose and cleanup resources
  void dispose();
}

// ============ Mock Implementation ============

/// Mock sync service for testing without Supabase.
class MockSyncService extends SyncService {
  bool _isReady = false;
  bool _isOnline = true;
  bool _wifiAvailable = true;

  final Map<String, SyncStatus> _syncStatuses = {};
  final _syncEventController = StreamController<SyncEvent>.broadcast();

  @override
  bool get isReady => _isReady;

  @override
  Stream<SyncEvent> get onSyncStatusChanged => _syncEventController.stream;

  /// Control mock state for testing
  void setMockOnline(bool online) {
    _isOnline = online;
  }

  void setMockWifiAvailable(bool available) {
    _wifiAvailable = available;
  }

  /// Helper to set sync status and emit event
  Future<void> setSyncStatus(String uuid, SyncStatus status) async {
    _syncStatuses[uuid] = status;
    _syncEventController.add(
      SyncEvent(
        entityUuid: uuid,
        entityType: 'Entity',
        status: status,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> initialize() async {
    _isReady = true;
  }

  @override
  Future<int?> syncAll() async {
    if (!_isOnline) return null;

    int count = 0;
    for (final entry in _syncStatuses.entries) {
      if (entry.value == SyncStatus.local ||
          entry.value == SyncStatus.syncing) {
        await setSyncStatus(entry.key, SyncStatus.syncing);
        await Future.delayed(Duration(milliseconds: 10));
        await setSyncStatus(entry.key, SyncStatus.synced);
        count++;
      }
    }
    return count;
  }

  @override
  Future<SyncStatus?> syncEntity(String uuid) async {
    if (!_isOnline) return null;

    final currentStatus = _syncStatuses[uuid] ?? SyncStatus.local;
    if (currentStatus == SyncStatus.synced) return SyncStatus.synced;

    await setSyncStatus(uuid, SyncStatus.syncing);
    await Future.delayed(Duration(milliseconds: 10));
    await setSyncStatus(uuid, SyncStatus.synced);

    return SyncStatus.synced;
  }

  @override
  Future<bool> syncBlobs() async {
    if (!_wifiAvailable) return false;

    // Emit mock blob sync events
    await setSyncStatus('blob-sync', SyncStatus.syncing);
    await Future.delayed(Duration(milliseconds: 10));
    await setSyncStatus('blob-sync', SyncStatus.synced);

    return true;
  }

  @override
  SyncStatus getSyncStatus(String uuid) {
    return _syncStatuses[uuid] ?? SyncStatus.local;
  }

  @override
  Future<void> resolveConflict(String uuid, {required bool keepLocal}) async {
    final status = _syncStatuses[uuid];
    if (status != SyncStatus.conflict) return;

    // Resolution always results in synced status
    await setSyncStatus(uuid, SyncStatus.synced);
  }

  @override
  void dispose() {
    _syncEventController.close();
  }
}

// ============ Real Implementation ============

/// Real Supabase sync service.
/// Syncs entities to Supabase PostgreSQL database.
/// Uses last-write-wins conflict resolution via updated_at timestamp.
class SupabaseSyncService extends SyncService {
  final String supabaseUrl;
  final String supabaseAnonKey;

  SupabaseClient? _client;
  bool _isReady = false;
  bool _simulateOffline = false;

  final Map<String, SyncStatus> _syncStatuses = {};
  final _syncEventController = StreamController<SyncEvent>.broadcast();

  /// Pending entities to sync (uuid → entity data)
  final Map<String, Map<String, dynamic>> _pendingSync = {};

  SupabaseSyncService({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  @override
  bool get isReady => _isReady;

  @override
  Stream<SyncEvent> get onSyncStatusChanged => _syncEventController.stream;

  /// Simulate offline mode for testing
  void setSimulateOffline(bool offline) {
    _simulateOffline = offline;
  }

  /// Helper to emit sync status change
  void _emitStatus(String uuid, String type, SyncStatus status) {
    _syncStatuses[uuid] = status;
    _syncEventController.add(SyncEvent(
      entityUuid: uuid,
      entityType: type,
      status: status,
      timestamp: DateTime.now(),
    ));
  }

  @override
  Future<void> initialize() async {
    if (_isReady) return;

    _client = SupabaseClient(supabaseUrl, supabaseAnonKey);
    _isReady = true;
  }

  @override
  Future<int?> syncAll() async {
    if (_simulateOffline) return null;
    if (!_isReady) await initialize();

    int synced = 0;
    for (final uuid in _syncStatuses.keys.toList()) {
      final status = _syncStatuses[uuid];
      if (status == SyncStatus.local || status == SyncStatus.syncing) {
        final result = await syncEntity(uuid);
        if (result == SyncStatus.synced) synced++;
      }
    }
    return synced;
  }

  @override
  Future<SyncStatus?> syncEntity(String uuid) async {
    if (_simulateOffline) return null;
    if (!_isReady) await initialize();

    final current = _syncStatuses[uuid] ?? SyncStatus.local;
    if (current == SyncStatus.synced) return SyncStatus.synced;

    _emitStatus(uuid, 'Entity', SyncStatus.syncing);

    try {
      // Check if entity has pending data to push
      final pending = _pendingSync[uuid];
      if (pending != null) {
        await pushEntity(
          uuid: uuid,
          type: pending['type'] as String,
          data: pending['data'] as Map<String, dynamic>,
          updatedAt: pending['updatedAt'] as DateTime?,
        );
        _pendingSync.remove(uuid);
      }

      _emitStatus(uuid, 'Entity', SyncStatus.synced);
      return SyncStatus.synced;
    } catch (e) {
      _emitStatus(uuid, 'Entity', SyncStatus.local);
      return SyncStatus.local;
    }
  }

  @override
  Future<bool> syncBlobs() async {
    if (_simulateOffline) return false;
    // Blob sync is handled by SupabaseBlobStore
    return true;
  }

  @override
  SyncStatus getSyncStatus(String uuid) {
    return _syncStatuses[uuid] ?? SyncStatus.local;
  }

  @override
  Future<void> resolveConflict(String uuid, {required bool keepLocal}) async {
    if (!_isReady) await initialize();

    final status = _syncStatuses[uuid];
    if (status != SyncStatus.conflict) return;

    if (keepLocal) {
      // Force push local version
      final pending = _pendingSync[uuid];
      if (pending != null) {
        await _forceUpsert(
          uuid: uuid,
          type: pending['type'] as String,
          data: pending['data'] as Map<String, dynamic>,
        );
      }
    }
    // If not keepLocal, remote version is already current

    _emitStatus(uuid, 'Entity', SyncStatus.synced);
  }

  @override
  void dispose() {
    _syncEventController.close();
    _client?.dispose();
    _client = null;
    _isReady = false;
  }

  // ============ Supabase-specific methods ============

  /// Push entity to Supabase with last-write-wins conflict resolution.
  /// Returns true if push succeeded.
  Future<bool> pushEntity({
    required String uuid,
    required String type,
    required Map<String, dynamic> data,
    DateTime? updatedAt,
  }) async {
    if (!_isReady) await initialize();

    final now = updatedAt ?? DateTime.now();

    try {
      // Check if entity exists and get its updated_at
      final existing = await _client!
          .from('entities')
          .select('updated_at')
          .eq('uuid', uuid)
          .maybeSingle();

      if (existing != null) {
        // Entity exists - check if our version is newer
        final remoteUpdatedAt =
            DateTime.parse(existing['updated_at'] as String);
        if (now.isBefore(remoteUpdatedAt) ||
            now.isAtSameMomentAs(remoteUpdatedAt)) {
          // Remote is newer or same - don't overwrite
          return true; // Still considered success
        }

        // Our version is newer - update
        await _client!.from('entities').update({
          'type': type,
          'data': data,
          'updated_at': now.toIso8601String(),
        }).eq('uuid', uuid);
      } else {
        // Entity doesn't exist - insert
        await _client!.from('entities').insert({
          'uuid': uuid,
          'type': type,
          'data': data,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }

      _emitStatus(uuid, type, SyncStatus.synced);
      return true;
    } catch (e) {
      // Log error for debugging
      print('SupabaseSyncService.pushEntity error: $e');
      _emitStatus(uuid, type, SyncStatus.local);
      return false;
    }
  }

  /// Force upsert without checking timestamps (for conflict resolution).
  Future<void> _forceUpsert({
    required String uuid,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    final now = DateTime.now();

    await _client!.from('entities').upsert({
      'uuid': uuid,
      'type': type,
      'data': data,
      'updated_at': now.toIso8601String(),
    });
  }

  /// Fetch entity from Supabase by UUID.
  /// Returns null if not found.
  Future<Map<String, dynamic>?> fetchEntity(String uuid) async {
    if (!_isReady) await initialize();

    try {
      final result = await _client!
          .from('entities')
          .select()
          .eq('uuid', uuid)
          .maybeSingle();

      return result;
    } catch (e) {
      print('SupabaseSyncService.fetchEntity error: $e');
      return null;
    }
  }

  /// Fetch all entities modified since a given timestamp.
  /// Useful for incremental sync.
  Future<List<Map<String, dynamic>>> fetchEntitiesSince(DateTime since) async {
    if (!_isReady) await initialize();

    try {
      final results = await _client!
          .from('entities')
          .select()
          .gt('updated_at', since.toIso8601String())
          .order('updated_at', ascending: true);

      return List<Map<String, dynamic>>.from(results);
    } catch (e) {
      return [];
    }
  }

  /// Fetch all entities of a specific type.
  Future<List<Map<String, dynamic>>> fetchEntitiesByType(String type) async {
    if (!_isReady) await initialize();

    try {
      final results = await _client!
          .from('entities')
          .select()
          .eq('type', type)
          .isFilter('deleted_at', null)
          .order('updated_at', ascending: false);

      return List<Map<String, dynamic>>.from(results);
    } catch (e) {
      return [];
    }
  }

  /// Delete entity from Supabase.
  /// Returns true if deleted, false if not found or error.
  Future<bool> deleteRemote(String uuid) async {
    if (!_isReady) await initialize();

    try {
      await _client!.from('entities').delete().eq('uuid', uuid);
      _syncStatuses.remove(uuid);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Queue entity for sync (call syncEntity later to actually sync).
  void queueForSync({
    required String uuid,
    required String type,
    required Map<String, dynamic> data,
    DateTime? updatedAt,
  }) {
    _pendingSync[uuid] = {
      'type': type,
      'data': data,
      'updatedAt': updatedAt ?? DateTime.now(),
    };
    _syncStatuses[uuid] = SyncStatus.local;
  }
}
