/// # ContextSelector
///
/// ## What it does
/// Selects relevant context for LLM using dual temporal decay:
/// - Recent conversation (STT/LLM pairs) with aggressive decay (24h half-life)
/// - Semantic context (all embeddable entities) with gentle decay (720h half-life)
///
/// ## Trainable aspects
/// - conversationThreadSize: How many recent turns to include
/// - conversationHalfLifeHours: Decay rate for conversation (default 24h)
/// - maxSemanticResults: Max semantic context items
/// - semanticHalfLifeHours: Decay rate for semantic context (default 720h = 1 month)
/// - semanticThreshold: Min similarity score to include
///
/// ## Usage
/// ```dart
/// final bundle = await contextSelector.selectContext(
///   transcription: 'Set a timer for 5 minutes',
///   userId: 'user123',
/// );
/// // bundle.conversationThread: Recent STT/LLM pairs
/// // bundle.semanticContext: Relevant facts from across system
/// ```

import 'dart:math' show exp, ln2, sqrt;
import 'dart:convert';
import 'package:get_it/get_it.dart';

import '../core/trainable.dart';
import '../core/invocation.dart';
import '../core/entity_repository.dart';
import '../domain/feedback.dart' as domain_feedback;
import '../core/adaptation_state_repository.dart';
import 'embedding_service.dart';
import 'types/context_selector_types.dart';
import 'trainer/gaussian_process_optimizer.dart';

class ContextSelector with Trainable<ContextSelectorAdaptationData> {
  final EntityRepository<Invocation> invocationRepo;
  final EmbeddingService embeddingService;

  ContextSelector({
    required this.invocationRepo,
    required this.embeddingService,
  });

  // ============ Trainable Implementation ============

  @override
  String get componentType => 'context_selector';

  @override
  ContextSelectorAdaptationData createDefaultData() =>
      ContextSelectorAdaptationData.defaults();

  @override
  ContextSelectorAdaptationData deserializeData(String json) =>
      ContextSelectorAdaptationData.fromJson(
        Map<String, dynamic>.from(
          // ignore: avoid_dynamic_calls
          const JsonDecoder().convert(json) as Map,
        ),
      );

  @override
  Map<String, (double, double)> getParameterBounds() => {
    'conversationThreadSize': (3.0, 15.0),
    'maxSemanticResults': (5.0, 25.0),
    'semanticThreshold': (0.5, 0.9),
  };

  @override
  Future<void> trainFromFeedback(
    Invocation invocation,
    domain_feedback.Feedback feedback,
  ) async {
    // TODO: Extract userId from invocation/turn context for per-user training
    // For now, use global training (userId = null)
    const String? userId = null;

    // Import needed for optimizer
    final optimizer = _getOrCreateOptimizer(userId);

    // Get current params
    final state = await getAdaptationState(userId: userId);
    final params = state.dataJson?.isNotEmpty == true
        ? deserializeData(state.dataJson!)
        : createDefaultData();

    // Convert feedback to reward
    final reward = feedback.action == domain_feedback.FeedbackAction.confirm ? 1.0 : -1.0;

    // Record trial (persists to database)
    await optimizer.recordTrial({
      'conversationThreadSize': params.conversationThreadSize,
      'maxSemanticResults': params.maxSemanticResults,
      'semanticThreshold': params.semanticThreshold,
    }, reward);

    // Get GP suggestion (loads historical trials from database)
    final suggested = await optimizer.suggestNext();

    // Update AdaptationState with new parameters
    final newParams = params.copyWith(
      conversationThreadSize: suggested['conversationThreadSize'] as int,
      maxSemanticResults: suggested['maxSemanticResults'] as int,
      semanticThreshold: suggested['semanticThreshold'] as double,
    );

    state.dataJson = newParams.toJson();
    state.version++;
    state.lastUpdatedAt = DateTime.now();
    state.lastUpdateReason = 'trainFromFeedback';
    state.feedbackCountApplied++;

    await GetIt.I<AdaptationStateRepository>().save(state);

    print('✅ [ContextSelector.trainFromFeedback] Updated parameters:');
    print('   conversationThreadSize: ${params.conversationThreadSize} → ${newParams.conversationThreadSize}');
    print('   maxSemanticResults: ${params.maxSemanticResults} → ${newParams.maxSemanticResults}');
    print('   semanticThreshold: ${params.semanticThreshold.toStringAsFixed(2)} → ${newParams.semanticThreshold.toStringAsFixed(2)}');
  }

  // ============ GP Optimizer Management ============

  final Map<String, GaussianProcessOptimizer> _optimizers = {};

  GaussianProcessOptimizer _getOrCreateOptimizer(String? userId) {
    final key = userId ?? '_global_';
    return _optimizers.putIfAbsent(
      key,
      () => GaussianProcessOptimizer(
        paramBounds: getParameterBounds(),
        componentType: componentType,
        userId: userId,
      ),
    );
  }

  // ============ Context Selection ============

  /// Select relevant context for current transcription
  ///
  /// Returns ContextBundle with:
  /// - conversationThread: Recent STT/LLM pairs (chronological order)
  /// - semanticContext: Relevant invocations from across system (scored by relevance)
  Future<ContextBundle> selectContext({
    required String eventId,
    required String transcription,
    String? userId,
  }) async {
    // Get adaptation parameters
    final adaptationState = await getAdaptationState(userId: userId);
    final params = adaptationState.dataJson != null
        ? deserializeData(adaptationState.dataJson!)
        : createDefaultData();

    print('\n🔍 [ContextSelector.selectContext] Starting context selection');
    print('   Params: threadSize=${params.conversationThreadSize}, '
        'convHalfLife=${params.conversationHalfLifeHours}h, '
        'semanticHalfLife=${params.semanticHalfLifeHours}h, '
        'threshold=${params.semanticThreshold}');

    // 1. Get embedding of transcription
    print('\n[1/6] Generating embedding for transcription...');
    final embedding = await embeddingService.generate(transcription);
    print('✅ Embedding generated: ${embedding.length} dimensions');

    // 2. Get all invocations, filter for STT/LLM (conversation thread)
    print('\n[2/6] Loading conversation thread (STT/LLM invocations)...');
    final allInvocations = await invocationRepo.findAll();
    final sttLlmInvocations = allInvocations
        .where((inv) => ['stt', 'llm'].contains(inv.componentType))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // Most recent first

    final conversationThread = sttLlmInvocations
        .take(params.conversationThreadSize)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt)); // Chronological order

    print('✅ Conversation thread: ${conversationThread.length} invocations');

    // 3. Apply decay to conversation thread (for debugging/logging)
    final now = DateTime.now();
    for (final inv in conversationThread) {
      final ageHours = now.difference(inv.updatedAt).inMinutes / 60.0;
      final decayScore = _computeDecay(ageHours, params.conversationHalfLifeHours);
      print('   ${inv.componentType} (${ageHours.toStringAsFixed(1)}h ago): decay=${decayScore.toStringAsFixed(3)}');
    }

    // 4. Semantic search ALL embeddable entities
    print('\n[3/6] Semantic search across all embeddable entities...');
    final semanticResults = await invocationRepo.semanticSearch(
      transcription, // Note: This regenerates embedding internally, but keeps code simple
      limit: 100, // Get more candidates, we'll filter down
      minSimilarity: 0.0, // Apply threshold after decay scoring
    );
    print('✅ Semantic search returned ${semanticResults.length} candidates');

    // 5. Filter out conversation thread (dedup)
    print('\n[4/6] Deduplicating (removing conversation thread from semantic results)...');
    final uuidsInConversation = conversationThread.map((inv) => inv.uuid).toSet();
    final filteredResults = semanticResults
        .where((inv) => !uuidsInConversation.contains(inv.uuid))
        .toList();
    print('✅ After dedup: ${filteredResults.length} candidates');

    // 6. Apply fused score: semantic similarity * temporal decay
    print('\n[5/6] Applying fused scoring (semantic * temporal decay)...');
    final scored = filteredResults.map((inv) {
      final ageHours = now.difference(inv.updatedAt).inMinutes / 60.0;
      final decay = _computeDecay(ageHours, params.semanticHalfLifeHours);

      // Compute semantic similarity (cosine similarity between embeddings)
      final semanticScore = inv.embedding != null
          ? _cosineSimilarity(embedding, inv.embedding!)
          : 0.0;

      final fusedScore = semanticScore * decay;
      return (inv, fusedScore, semanticScore, decay);
    }).toList();

    // 7. Filter by semantic threshold and sort by fused score
    print('\n[6/6] Filtering by threshold and selecting top results...');
    final topResults = scored
        .where((item) => item.$3 >= params.semanticThreshold) // Filter by semantic similarity
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2)) // Sort by fused score
      ..take(params.maxSemanticResults).toList();

    print('✅ Top semantic context: ${topResults.length} invocations');
    for (final item in topResults.take(5)) {
      final inv = item.$1;
      final fusedScore = item.$2;
      final semanticScore = item.$3;
      final decay = item.$4;
      final ageHours = now.difference(inv.updatedAt).inMinutes / 60.0;
      print('   ${inv.componentType} (${ageHours.toStringAsFixed(1)}h ago): '
          'semantic=${semanticScore.toStringAsFixed(3)}, '
          'decay=${decay.toStringAsFixed(3)}, '
          'fused=${fusedScore.toStringAsFixed(3)}');
    }

    final bundle = ContextBundle(
      conversationThread: conversationThread,
      semanticContext: topResults.map((item) => item.$1).toList(),
      params: params,
    );

    print('\n✅ ContextBundle created: ${bundle.summary}');

    // Log invocation for training
    await recordInvocation(
      eventId,
      Invocation(
        eventId: eventId,
        componentType: componentType,
        success: true,
        confidence: 1.0,
        input: {'transcription': transcription},
        output: {
          'conversationThreadSize': conversationThread.length,
          'semanticContextSize': bundle.semanticContext.length,
        },
      ),
    );

    return bundle;
  }

  /// Compute temporal decay score using exponential half-life formula
  ///
  /// Formula: exp(-ln(2) * age_hours / half_life_hours)
  /// - age = half_life: score = 0.5
  /// - age = 2 * half_life: score = 0.25
  /// - age = 0: score = 1.0
  double _computeDecay(double ageHours, double halfLifeHours) {
    if (ageHours <= 0) return 1.0;
    return exp(-ln2 * ageHours / halfLifeHours);
  }

  /// Compute cosine similarity between two embeddings
  ///
  /// Returns value between -1 and 1 (typically 0 to 1 for embeddings)
  /// - 1.0: Identical vectors
  /// - 0.0: Orthogonal vectors
  /// - -1.0: Opposite vectors
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0.0 || normB == 0.0) return 0.0;

    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
}
