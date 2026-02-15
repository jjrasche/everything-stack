import '../core/entity_repository.dart';
import '../core/persistence/persistence_adapter.dart';
import '../core/persistence/transaction_manager.dart';
import '../services/embedding_service.dart';
import '../services/embedding_queue_service.dart';
import '../bootstrap.dart' show embeddingQueueService;
import 'atomic_insight.dart';

class AtomicInsightRepository extends EntityRepository<AtomicInsight> {
  final EmbeddingQueueService? _embeddingQueueService;

  /// Full constructor for testing and infrastructure setup.
  AtomicInsightRepository({
    required PersistenceAdapter<AtomicInsight> adapter,
    EmbeddingService? embeddingService,
    TransactionManager? transactionManager,
    EmbeddingQueueService? embeddingQueueService,
  })  : _embeddingQueueService = embeddingQueueService,
        super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
          transactionManager: transactionManager,
          handlers: [],
        );

  /// Factory for production use - uses global singleton services.
  factory AtomicInsightRepository.production({
    required PersistenceAdapter<AtomicInsight> adapter,
  }) {
    return AtomicInsightRepository(
      adapter: adapter,
      embeddingService: EmbeddingService.instance,
      embeddingQueueService: embeddingQueueService,
    );
  }

  // ============ Repository Overrides ============

  /// Override save to enqueue background embedding generation.
  @override
  Future<int> save(AtomicInsight entity) async {
    final id = await super.save(entity);

    // Enqueue for background embedding if queue service is available
    if (_embeddingQueueService != null && !entity.isArchived) {
      if (entity.content.isNotEmpty) {
        await _embeddingQueueService!.enqueue(
          entityUuid: entity.uuid,
          entityType: 'AtomicInsight',
          text: entity.content,
        );
      }
    }

    return id;
  }

  // ============ Scope-Based Queries ============

  /// Find all insights in a specific scope (session, day, week, project, life)
  /// Returns newest first (by updatedAt)
  Future<List<AtomicInsight>> findByScope(String scope,
      {bool includeArchived = false}) async {
    final all = await findAll();
    final filtered = all.where((insight) {
      if (insight.scope != scope) return false;
      if (!includeArchived && insight.isArchived) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  /// Find active insights (non-archived) in a scope
  Future<List<AtomicInsight>> findActiveByScope(String scope) async {
    return findByScope(scope, includeArchived: false);
  }

  /// Find insights for a specific project
  Future<List<AtomicInsight>> findByProject(String projectId,
      {bool includeArchived = false}) async {
    final all = await findAll();
    final filtered = all.where((insight) {
      if (insight.projectId != projectId) return false;
      if (!includeArchived && insight.isArchived) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  /// Find insights by type (learning, project, exploration)
  Future<List<AtomicInsight>> findByType(String type,
      {String? scope, bool includeArchived = false}) async {
    final all = await findAll();
    final filtered = all.where((insight) {
      if (insight.type != type) return false;
      if (scope != null && insight.scope != scope) return false;
      if (!includeArchived && insight.isArchived) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  // ============ Semantic Search ============

  /// Find relevant atomic insights by semantic similarity to a query.
  /// Uses base EntityRepository.semanticSearch() with filtering.
  ///
  /// Parameters:
  /// - query: The text to search for
  /// - topK: Maximum number of results to return (default 5)
  /// - threshold: Minimum cosine similarity (0-1, default 0.65)
  /// - scopes: List of scopes to search in (default: all active scopes)
  /// - excludeArchived: If true, skip archived insights (default true)
  Future<List<AtomicInsight>> findRelevant(
    String query, {
    int topK = 5,
    double threshold = 0.65,
    List<String>? scopes,
    bool excludeArchived = true,
  }) async {
    // Use base semanticSearch with threshold
    final allResults = await semanticSearch(
      query,
      limit: topK * 2,
      minSimilarity: threshold,
    );

    // Filter by scope and archive status
    final filtered = allResults.where((insight) {
      if (excludeArchived && insight.isArchived) return false;
      if (scopes != null && !scopes.contains(insight.scope)) return false;
      return true;
    }).take(topK).toList();

    return filtered;
  }

  // ============ Archival ============

  /// Archive an insight (soft delete). Sets isArchived=true and archivedAt.
  Future<void> archive(String uuid) async {
    final insight = await findByUuid(uuid);
    if (insight != null) {
      insight.isArchived = true;
      insight.archivedAt = DateTime.now();
      await save(insight);
    }
  }

  /// Unarchive an insight. Sets isArchived=false and clears archivedAt.
  Future<void> unarchive(String uuid) async {
    final insight = await findByUuid(uuid);
    if (insight != null) {
      insight.isArchived = false;
      insight.archivedAt = null;
      await save(insight);
    }
  }

  /// Delete archived insights older than specified duration.
  /// Used for cleanup (e.g., delete Sessions older than 30 days).
  Future<int> purgeArchivedBefore(
    Duration duration, {
    String? scope,
  }) async {
    final threshold = DateTime.now().subtract(duration);
    final all = await findAll();

    int deleted = 0;
    for (final insight in all) {
      if (insight.isArchived &&
          insight.archivedAt != null &&
          insight.archivedAt!.isBefore(threshold)) {
        if (scope == null || insight.scope == scope) {
          await deleteByUuid(insight.uuid);
          deleted++;
        }
      }
    }
    return deleted;
  }
}
