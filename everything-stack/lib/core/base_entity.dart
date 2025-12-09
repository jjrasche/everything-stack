/// # BaseEntity
/// 
/// ## What it does
/// Foundation for all domain entities. Provides common fields and lifecycle.
/// 
/// ## What it enables
/// - Consistent entity structure across domain
/// - Common fields (id, timestamps) handled once
/// - Pattern mixins compose cleanly
/// - Repository operations work generically
/// 
/// ## Usage
/// ```dart
/// @Collection()
/// class Tool extends BaseEntity with Embeddable, Locatable {
///   String name;
///   String description;
///   
///   @override
///   String toEmbeddingInput() => '$name $description';
/// }
/// ```
/// 
/// ## Testing approach
/// BaseEntity itself needs no testing. Test domain entities that extend it.
/// Verify timestamps update correctly, IDs generate uniquely.

import 'package:isar/isar.dart';

abstract class BaseEntity {
  /// Isar auto-generated ID
  Id? id;
  
  /// When entity was created
  DateTime createdAt = DateTime.now();
  
  /// When entity was last modified
  DateTime updatedAt = DateTime.now();
  
  /// Update timestamp before save
  void touch() {
    updatedAt = DateTime.now();
  }
  
  /// For sync identification across devices
  String? syncId;
  
  /// Sync status: local, syncing, synced, conflict
  SyncStatus syncStatus = SyncStatus.local;
}

enum SyncStatus {
  local,    // Only exists locally
  syncing,  // Currently uploading
  synced,   // Matches remote
  conflict, // Local and remote differ
}
