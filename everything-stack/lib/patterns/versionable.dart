/// # Versionable
///
/// ## What it does
/// Tracks change history for entities using Type 4 SCD with deltas.
/// Opt-in versioning for entities that need audit trails and reconstruction.
///
/// ## What it enables
/// - Point-in-time reconstruction: "What was this Note on Dec 1?"
/// - Audit trail: "Who changed what and when?"
/// - Rollback: "Restore to version N"
/// - Conflict resolution in sync scenarios
/// - Compliance and accountability
///
/// ## Schema addition
/// ```dart
/// int version = 1;
/// String? lastModifiedBy;
/// ```
///
/// ## Usage
/// ```dart
/// @Collection()
/// class Contract extends BaseEntity with Versionable {
///   String terms;
///
///   @override
///   int get snapshotFrequency => 10; // Override default if needed
/// }
///
/// // EntityRepository automatically records changes
/// contract.terms = newTerms;
/// await contractRepo.save(contract); // Versioning happens automatically
///
/// // View history
/// final history = await versionRepo.getHistory(contract.uuid);
///
/// // Reconstruct at timestamp
/// final state = await versionRepo.reconstruct(contract.uuid, targetTime);
/// ```
///
/// ## Snapshot Frequency
/// Override `snapshotFrequency` to customize per entity type:
/// - Default: 20 (snapshot every 20 versions)
/// - High-churn entities: 50-100
/// - Large entities: 10
/// - Simple configs: null (initial snapshot only)
///
/// ## Performance
/// - Version number increment is O(1)
/// - History queries scale with number of changes
/// - Reconstruction bounded by snapshot frequency
/// - Use prune() to clean up old versions
///
/// ## Testing approach
/// Integration tests:
/// - Modify entity multiple times
/// - Verify version increments correctly
/// - Verify EntityVersion records created
/// - Test reconstruction at various points
/// - Test conflict detection
///
/// ## Integrates with
/// - EntityRepository: Automatic recordChange() on save
/// - VersionRepository: Manages EntityVersion records
/// - Ownable: Track who made each change
/// - Sync: Conflict resolution using versions

mixin Versionable {
  /// Current version number, increments on each save
  int version = 1;

  /// User ID of last modifier
  String? lastModifiedBy;

  /// Snapshot frequency for this entity type.
  /// Override in concrete classes to customize.
  /// Default: 20 (snapshot every 20 versions)
  /// null = no periodic snapshots (initial only)
  int? get snapshotFrequency => 20;

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
