/// ## Schema addition
/// ```dart
/// int version = 1;
/// String? lastModifiedBy;
/// ```
///
/// ## JSON Serialization (REQUIRED)
/// Versionable entities MUST implement toJson() and fromJson() methods.
/// Use @JsonSerializable() annotation with json_serializable package.
/// This enables delta computation and reconstruction from snapshots.
///
/// ```dart
/// import 'package:json_annotation/json_annotation.dart';
///
/// part 'contract.g.dart';
///
/// @Collection()
/// @JsonSerializable()
/// class Contract extends BaseEntity with Versionable {
///   String terms;
///
///   Map<String, dynamic> toJson() => _$ContractToJson(this);
///   factory Contract.fromJson(Map<String, dynamic> json) => _$ContractFromJson(json);
///
///   @override
///   int get snapshotFrequency => 10;
/// }
/// ```
///
/// Then run: `dart run build_runner build`
///
/// ## Usage
/// ```dart
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
