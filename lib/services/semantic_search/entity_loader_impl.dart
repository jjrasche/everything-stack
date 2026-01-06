import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'semantic_search_service.dart';

/// Concrete implementation of EntityLoader for cross-repository entity lookup.
///
/// Resolves entity UUIDs back to their source entities by trying each
/// repository in sequence. Used by SemanticSearchService to reconstruct
/// entities from chunk metadata after HNSW search results.
class EntityLoaderImpl extends EntityLoader {
  @override
  Future<BaseEntity?> getById(String uuid) async {
    // Try Invocation repository first
    try {
      final repo = GetIt.instance<InvocationRepository<Invocation>>();
      // InvocationRepository is EntityRepository<Invocation> via factory function
      // EntityRepository has findByUuid method
      if (repo is InvocationRepository<Invocation>) {
        // Cast to EntityRepository to access findByUuid
        final entityRepo = repo as dynamic;
        final invocation = await entityRepo.findByUuid(uuid);
        if (invocation != null) return invocation;
      }
    } catch (e) {
      // Repository not available, continue to next
    }

    // Add other repositories as needed (Task, Note, etc.)
    // For now, only Invocation is required for this feature

    return null;
  }
}
