import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'semantic_search_service.dart';

/// Type signature for repository lookup functions.
/// Takes UUID, returns entity or null.
typedef EntityLookup = Future<BaseEntity?> Function(String uuid);

/// Concrete implementation of EntityLoader for cross-repository entity lookup.
///
/// Any SemanticIndexable entity can be chunked and indexed. When semantic
/// search returns chunks, this loader resolves sourceEntityId back to the
/// actual entity by querying the appropriate repository.
class EntityLoaderImpl extends EntityLoader {
  /// Registry mapping entity type names to lookup functions.
  final Map<String, EntityLookup> _registry = {};

  /// Register a repository lookup for an entity type.
  ///
  /// Call this during bootstrap for each entity type that can be indexed.
  void registerEntityType(String entityType, EntityLookup lookup) {
    _registry[entityType] = lookup;
  }

  /// Register default entity types (Invocation).
  ///
  /// Call this during bootstrap to set up standard lookups.
  /// Additional entity types can be registered separately.
  void registerDefaults() {
    print('🔍 [EntityLoader] registerDefaults() called');
    registerEntityType('Invocation', (uuid) async {
      try {
        final repo = GetIt.instance<InvocationRepository<Invocation>>();
        final result = await repo.findById(uuid);
        return result;
      } catch (e) {
        debugPrint('⚠️ [EntityLoader] Invocation lookup failed: $e');
        return null;
      }
    });
    print('🔍 [EntityLoader] Registered types: ${registeredTypes}');

    // Add more default types as they become SemanticIndexable:
    // registerEntityType('Task', ...);
    // registerEntityType('Note', ...);
    // registerEntityType('Document', ...);
  }

  @override
  Future<BaseEntity?> getById(String uuid, {String? entityType}) async {
    // If entityType is specified, query that repository directly
    if (entityType != null) {
      final lookup = _registry[entityType];
      if (lookup != null) {
        final entity = await lookup(uuid);
        if (entity != null) return entity;
      }
      debugPrint('⚠️ [EntityLoader] entityType "$entityType" not in registry. Keys: ${_registry.keys.toList()}');
      return null;
    }

    // No entityType specified - try all registered repositories
    for (final entry in _registry.entries) {
      try {
        final entity = await entry.value(uuid);
        if (entity != null) return entity;
      } catch (e) {
        // Repository lookup failed, continue to next
      }
    }

    return null;
  }

  /// Get list of registered entity types.
  /// Useful for debugging and validation.
  List<String> get registeredTypes => _registry.keys.toList();
}
