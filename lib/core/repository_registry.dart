/// # RepositoryRegistry
///
/// ## What it does
/// Maps entity type strings to their repositories.
/// Allows workers to fetch entities by uuid + type string.
///
/// ## Why needed
/// EnrichmentWorkers receive entityUuid and entityType (string) from QueueItem.
/// They need to fetch the actual entity to process it.
/// This registry provides type→repository lookup.
///
/// ## Usage
/// ```dart
/// // Bootstrap: Register repositories
/// final registry = RepositoryRegistry();
/// registry.register<Invocation>(invocationRepo);
/// registry.register<Task>(taskRepo);
///
/// // Worker: Fetch entity
/// final entity = await registry.fetchEntity(item.entityUuid, item.entityType);
/// ```

import 'base_entity.dart';
import 'entity_repository.dart';

class RepositoryRegistry {
  final Map<String, EntityRepository<dynamic>> _repos = {};

  /// Register a repository for an entity type.
  void register<T extends BaseEntity>(EntityRepository<T> repo) {
    _repos[T.toString()] = repo;
  }

  /// Get repository for an entity type string.
  EntityRepository<dynamic>? getRepository(String typeName) {
    return _repos[typeName];
  }

  /// Fetch any entity by uuid + type string.
  ///
  /// Returns null if:
  /// - No repository registered for the type
  /// - Entity not found by uuid
  Future<BaseEntity?> fetchEntity(String uuid, String typeName) async {
    final repo = _repos[typeName];
    if (repo == null) return null;
    final result = await repo.findByUuid(uuid);
    return result as BaseEntity?;
  }

  /// Check if a repository is registered for a type.
  bool hasRepository(String typeName) {
    return _repos.containsKey(typeName);
  }

  /// List all registered type names.
  List<String> get registeredTypes => _repos.keys.toList();
}
