/// # NarrativeRepository
///
/// ## What it does
/// Repository for NarrativeEntry entities. Manages CRUD operations,
/// scope-based queries, and semantic search across narrative entries.
///
/// ## Usage - Production
/// ```dart
/// final adapter = NarrativeObjectBoxAdapter(store);
/// final repo = NarrativeRepository.production(
///   adapter: adapter,
/// );
/// ```
///
/// ## Usage - Testing
/// ```dart
/// final repo = NarrativeRepository(
///   adapter: adapter,
///   embeddingService: MockEmbeddingService(),
/// );
/// ```

import '../core/entity_repository.dart';
import '../core/persistence/persistence_adapter.dart';
import '../core/persistence/transaction_manager.dart';
import '../services/embedding_service.dart';
import '../services/embedding_queue_service.dart';
import '../bootstrap.dart' show embeddingQueueService;
import 'narrative_entry.dart';

class NarrativeRepository extends EntityRepository<NarrativeEntry> {
  final EmbeddingQueueService? _embeddingQueueService;

  /// Full constructor for testing and infrastructure setup.
  NarrativeRepository({
    required PersistenceAdapter<NarrativeEntry> adapter,
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
  factory NarrativeRepository.production({
    required PersistenceAdapter<NarrativeEntry> adapter,
  }) {
    return NarrativeRepository(
      adapter: adapter,
      embeddingService: EmbeddingService.instance,
      embeddingQueueService: embeddingQueueService,
    );
  }

  // ============ Repository Overrides ============

  /// Override save to enqueue background embedding generation.
  @override
  Future<int> save(NarrativeEntry entity) async {
    final id = await super.save(entity);

    // Enqueue for background embedding if queue service is available
    if (_embeddingQueueService != null && !entity.isArchived) {
      if (entity.content.isNotEmpty) {
        await _embeddingQueueService!.enqueue(
          entityUuid: entity.uuid,
          entityType: 'NarrativeEntry',
          text: entity.content,
        );
      }
    }

    return id;
  }

  // ============ Scope-Based Queries ============

  /// Find all entries in a specific scope (session, day, week, project, life)
  /// Returns newest first (by updatedAt)
  Future<List<NarrativeEntry>> findByScope(String scope,
      {bool includeArchived = false}) async {
    final all = await findAll();
    final filtered = all.where((entry) {
      if (entry.scope != scope) return false;
      if (!includeArchived && entry.isArchived) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  /// Find active entries (non-archived) in a scope
  Future<List<NarrativeEntry>> findActiveByScope(String scope) async {
    return findByScope(scope, includeArchived: false);
  }

  /// Find entries for a specific project
  Future<List<NarrativeEntry>> findByProject(String projectId,
      {bool includeArchived = false}) async {
    final all = await findAll();
    final filtered = all.where((entry) {
      if (entry.projectId != projectId) return false;
      if (!includeArchived && entry.isArchived) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  /// Find entries by type (learning, project, exploration)
  Future<List<NarrativeEntry>> findByType(String type,
      {String? scope, bool includeArchived = false}) async {
    final all = await findAll();
    final filtered = all.where((entry) {
      if (entry.type != type) return false;
      if (scope != null && entry.scope != scope) return false;
      if (!includeArchived && entry.isArchived) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  // ============ Semantic Search ============

  /// Find relevant narrative entries by semantic similarity to a query.
  /// Returns top-K entries above threshold, sorted by similarity (highest first).
  ///
  /// Parameters:
  /// - query: The text to search for (typically the current utterance)
  /// - topK: Maximum number of results to return (default 5)
  /// - threshold: Minimum cosine similarity (0-1, default 0.65)
  /// - scopes: List of scopes to search in (default: all active scopes)
  /// - excludeArchived: If true, skip archived entries (default true)
  ///
  /// Returns empty list if no entries match threshold.
  Future<List<NarrativeEntry>> findRelevant(
    String query, {
    int topK = 5,
    double threshold = 0.65,
    List<String>? scopes,
    bool excludeArchived = true,
  }) async {
    // Generate embedding for query
    final queryEmbedding = await embeddingService.embed(query);
    if (queryEmbedding == null) {
      return []; // Embedding service unavailable
    }

    // Get all entries
    final all = await findAll();

    // Filter by scope and archive status
    final candidates = all.where((entry) {
      if (excludeArchived && entry.isArchived) return false;
      if (scopes != null && !scopes.contains(entry.scope)) return false;
      if (entry.embedding == null || entry.embedding!.isEmpty) return false;
      return true;
    }).toList();

    // Score and filter by threshold
    final scored = <(NarrativeEntry, double)>[];
    for (final entry in candidates) {
      final similarity = _cosineSimilarity(queryEmbedding, entry.embedding!);
      if (similarity >= threshold) {
        scored.add((entry, similarity));
      }
    }

    // Sort by similarity (highest first) and take top-K
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(topK).map((pair) => pair.$1).toList();
  }

  // ============ Archival ============

  /// Archive an entry (soft delete). Sets isArchived=true and archivedAt.
  Future<void> archive(String uuid) async {
    final entry = await findByUuid(uuid);
    if (entry != null) {
      entry.isArchived = true;
      entry.archivedAt = DateTime.now();
      await save(entry);
    }
  }

  /// Unarchive an entry. Sets isArchived=false and clears archivedAt.
  Future<void> unarchive(String uuid) async {
    final entry = await findByUuid(uuid);
    if (entry != null) {
      entry.isArchived = false;
      entry.archivedAt = null;
      await save(entry);
    }
  }

  /// Delete archived entries older than specified duration.
  /// Used for cleanup (e.g., delete Sessions older than 30 days).
  Future<int> purgeArchivedBefore(
    Duration duration, {
    String? scope,
  }) async {
    final threshold = DateTime.now().subtract(duration);
    final all = await findAll();

    int deleted = 0;
    for (final entry in all) {
      if (entry.isArchived &&
          entry.archivedAt != null &&
          entry.archivedAt!.isBefore(threshold)) {
        if (scope == null || entry.scope == scope) {
          await delete(entry.uuid);
          deleted++;
        }
      }
    }
    return deleted;
  }

  // ============ Helpers ============

  /// Compute cosine similarity between two vectors
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    if (a.isEmpty) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = (normA * normB).sqrt();
    if (denominator == 0.0) return 0.0;
    return dotProduct / denominator;
  }
}
