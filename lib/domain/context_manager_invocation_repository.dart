/// # ContextManagerInvocationRepository
///
/// ## What it does
/// Repository for ContextManagerInvocation entities.
/// Logs context manager decisions for training and debugging.
///
/// ## Usage
/// ```dart
/// final adapter = ContextManagerInvocationObjectBoxAdapter(store);
/// final repo = ContextManagerInvocationRepository(adapter: adapter);
///
/// // Find invocations for a correlation chain
/// final chain = await repo.findByCorrelationId('corr_001');
///
/// // Find recent invocations for training review
/// final recent = await repo.findRecent(limit: 50);
/// ```

import '../core/entity_repository.dart';
import '../core/persistence/persistence_adapter.dart';
import '../services/embedding_service.dart';
import 'context_manager_invocation.dart';

class ContextManagerInvocationRepository
    extends EntityRepository<ContextManagerInvocation> {
  ContextManagerInvocationRepository({
    required PersistenceAdapter<ContextManagerInvocation> adapter,
    EmbeddingService? embeddingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  // ============ ContextManagerInvocation-specific queries ============

  /// Find invocations by correlation ID
  /// Returns all context manager decisions in a single event chain
  Future<List<ContextManagerInvocation>> findByCorrelationId(
      String correlationId) async {
    final all = await findAll();
    return all.where((inv) => inv.correlationId == correlationId).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Find invocations by personality
  /// Useful for training analysis per personality
  Future<List<ContextManagerInvocation>> findByPersonality(
      String personalityId) async {
    final all = await findAll();
    return all.where((inv) => inv.personalityId == personalityId).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Find recent invocations for training review
  Future<List<ContextManagerInvocation>> findRecent({int limit = 50}) async {
    final all = await findAll();
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all.take(limit).toList();
  }

  /// Find invocations with errors
  /// Useful for debugging and failure analysis
  Future<List<ContextManagerInvocation>> findWithErrors() async {
    final all = await findAll();
    return all.where((inv) => inv.errorType != null).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Find invocations where a specific tool was called
  Future<List<ContextManagerInvocation>> findWhereToolCalled(
      String toolName) async {
    final all = await findAll();
    // Load transient fields
    for (final inv in all) {
      inv.loadAfterRead();
    }
    return all.where((inv) => inv.toolsCalled.contains(toolName)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Find invocations where a specific tool was filtered out
  /// Useful for understanding why tools aren't being selected
  Future<List<ContextManagerInvocation>> findWhereToolFiltered(
      String toolName) async {
    final all = await findAll();
    // Load transient fields
    for (final inv in all) {
      inv.loadAfterRead();
    }
    return all.where((inv) => inv.toolsFiltered.contains(toolName)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Get average confidence over last N invocations
  /// Useful for monitoring system health
  Future<double> getAverageConfidence({int limit = 100}) async {
    final recent = await findRecent(limit: limit);
    if (recent.isEmpty) return 0.0;
    final sum = recent.fold<double>(0.0, (sum, inv) => sum + inv.confidence);
    return sum / recent.length;
  }

  /// Override save to prepare embedded lists/maps
  @override
  Future<int> save(ContextManagerInvocation entity) async {
    // Serialize transient fields to JSON
    entity.prepareForSave();
    return super.save(entity);
  }

  /// Override findByUuid to load transient fields
  @override
  Future<ContextManagerInvocation?> findByUuid(String uuid) async {
    final invocation = await super.findByUuid(uuid);
    if (invocation != null) {
      invocation.loadAfterRead();
    }
    return invocation;
  }

  /// Override findAll to load transient fields
  @override
  Future<List<ContextManagerInvocation>> findAll() async {
    final all = await super.findAll();
    for (final inv in all) {
      inv.loadAfterRead();
    }
    return all;
  }
}
