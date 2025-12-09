/// # Versionable
/// 
/// ## What it does
/// Tracks change history for entities. Records who changed what, when.
/// Enables undo, audit trails, and conflict resolution.
/// 
/// ## What it enables
/// - "What changed?" - see modification history
/// - "Who changed it?" - audit trail
/// - Undo/redo functionality
/// - Conflict resolution in sync scenarios
/// - Compliance and accountability
/// 
/// ## Schema addition
/// ```dart
/// int version = 1;
/// String? lastModifiedBy;
/// // History stored in separate Version entities
/// ```
/// 
/// ## Usage
/// ```dart
/// class Contract extends BaseEntity with Versionable {
///   String terms;
/// }
/// 
/// // Before modifying
/// contract.recordChange(
///   userId: currentUser.id,
///   changes: {'terms': contract.terms},
/// );
/// contract.terms = newTerms;
/// await contractRepo.save(contract);
/// 
/// // View history
/// final history = await versionRepo.getHistory(contract.id);
/// 
/// // Revert to previous version
/// await contract.revertTo(version: 3);
/// ```
/// 
/// ## Performance
/// - Version number increment is O(1)
/// - History queries scale with number of changes
/// - Consider pruning old versions for high-churn entities
/// - Snapshot strategy for large entities (store full state periodically)
/// 
/// ## Testing approach
/// History tests:
/// - Modify entity multiple times
/// - Verify version increments correctly
/// - Verify history contains all changes with correct metadata
/// - Test revert functionality
/// - Test conflict detection (same version modified twice)
/// 
/// ## Integrates with
/// - Ownable: Track who made each change
/// - Sync: Conflict resolution using versions

mixin Versionable {
  /// Current version number, increments on each save
  int version = 1;
  
  /// User ID of last modifier
  String? lastModifiedBy;
  
  /// Increment version before save
  void incrementVersion(String userId) {
    version++;
    lastModifiedBy = userId;
  }
  
  /// Check if this version conflicts with expected version
  bool hasConflict(int expectedVersion) {
    return version != expectedVersion;
  }
}

/// Represents a historical version of an entity.
/// Store these in a separate collection/table.
class Version {
  /// Auto-generated ID
  int? id;
  
  /// Type of entity this versions
  String entityType;
  
  /// ID of entity this versions
  int entityId;
  
  /// Version number
  int versionNumber;
  
  /// Who made this change
  String modifiedBy;
  
  /// When this change was made
  DateTime modifiedAt;
  
  /// What changed (JSON of field -> old value)
  Map<String, dynamic> changes;
  
  /// Optional: full snapshot for periodic checkpoints
  Map<String, dynamic>? snapshot;
  
  Version({
    required this.entityType,
    required this.entityId,
    required this.versionNumber,
    required this.modifiedBy,
    required this.modifiedAt,
    required this.changes,
    this.snapshot,
  });
}
