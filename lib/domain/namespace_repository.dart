import '../core/entity_repository.dart';
import '../core/persistence/persistence_adapter.dart';
import '../services/embedding_service.dart';
import 'namespace.dart';

class NamespaceRepository extends EntityRepository<Namespace> {
  NamespaceRepository({
    required PersistenceAdapter<Namespace> adapter,
    EmbeddingService? embeddingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  // ============ Namespace-specific queries ============

  /// Find namespace by name (e.g., "task", "timer", "health")
  /// Returns null if not found
  Future<Namespace?> findByName(String name) async {
    final all = await findAll();
    try {
      return all.firstWhere((ns) => ns.name == name);
    } catch (e) {
      return null;
    }
  }

  /// Get all namespaces ordered by name
  Future<List<Namespace>> findAllOrdered() async {
    final all = await findAll();
    return all..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Check if namespace exists by name
  Future<bool> exists(String name) async {
    final ns = await findByName(name);
    return ns != null;
  }
}
