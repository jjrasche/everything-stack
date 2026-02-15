import 'dart:math' show exp, ln2, pow, sqrt;
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
import 'semantic_search/semantic_search_service.dart';
import 'semantic_search/search_result.dart';

class ContextSelector with Trainable<ContextSelectorAdaptationData> {
  final EntityRepository<Invocation> invocationRepo;
  final EmbeddingService embeddingService;
  final SemanticSearchService semanticSearchService;

  ContextSelector({
    required this.invocationRepo,
    required this.embeddingService,
    required this.semanticSearchService,
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
        'conversationHalfLifeHours': (1.0, 72.0), // 1 hour to 3 days
        'maxSemanticResults': (5.0, 25.0),
        'semanticHalfLifeHours': (168.0, 2160.0), // 1 week to 3 months
        'semanticThreshold': (0.5, 0.9),
        'similarityAlpha': (0.0, 2.0), // 0 = ignore similarity, 2 = similarity^2
        'decayBeta': (0.0, 2.0), // 0 = ignore recency, 2 = decay^2
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
    final reward =
        feedback.action == domain_feedback.FeedbackAction.confirm ? 1.0 : -1.0;

    // Record trial (persists to database)
    await optimizer.recordTrial({
      'conversationThreadSize': params.conversationThreadSize,
      'conversationHalfLifeHours': params.conversationHalfLifeHours,
      'maxSemanticResults': params.maxSemanticResults,
      'semanticHalfLifeHours': params.semanticHalfLifeHours,
      'semanticThreshold': params.semanticThreshold,
      'similarityAlpha': params.similarityAlpha,
      'decayBeta': params.decayBeta,
    }, reward);

    // Get GP suggestion (loads historical trials from database)
    final suggested = await optimizer.suggestNext();

    // Update AdaptationState with new parameters
    final newParams = params.copyWith(
      conversationThreadSize: suggested['conversationThreadSize'] as int,
      conversationHalfLifeHours:
          suggested['conversationHalfLifeHours'] as double,
      maxSemanticResults: suggested['maxSemanticResults'] as int,
      semanticHalfLifeHours: suggested['semanticHalfLifeHours'] as double,
      semanticThreshold: suggested['semanticThreshold'] as double,
      similarityAlpha: suggested['similarityAlpha'] as double,
      decayBeta: suggested['decayBeta'] as double,
    );

    state.dataJson = newParams.toJson();
    state.version++;
    state.lastUpdatedAt = DateTime.now();
    state.lastUpdateReason = 'trainFromFeedback';
    state.feedbackCountApplied++;

    await GetIt.I<AdaptationStateRepository>().save(state);

    print('✅ [ContextSelector.trainFromFeedback] Updated parameters:');
    print(
        '   conversationThreadSize: ${params.conversationThreadSize} → ${newParams.conversationThreadSize}');
    print(
        '   conversationHalfLifeHours: ${params.conversationHalfLifeHours.toStringAsFixed(1)}h → ${newParams.conversationHalfLifeHours.toStringAsFixed(1)}h');
    print(
        '   maxSemanticResults: ${params.maxSemanticResults} → ${newParams.maxSemanticResults}');
    print(
        '   semanticHalfLifeHours: ${params.semanticHalfLifeHours.toStringAsFixed(1)}h → ${newParams.semanticHalfLifeHours.toStringAsFixed(1)}h');
    print(
        '   semanticThreshold: ${params.semanticThreshold.toStringAsFixed(2)} → ${newParams.semanticThreshold.toStringAsFixed(2)}');
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
  /// - conversationThread: Recent LLM invocations (each has input.prompt + output.response)
  /// - semanticContext: Relevant chunks from ANY entity (via SemanticSearchService)
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
        'threshold=${params.semanticThreshold}, '
        'α=${params.similarityAlpha}, β=${params.decayBeta}');

    final now = DateTime.now();

    // 1. Get conversation thread with similarity × decay scoring
    print('\n[1/4] Loading and scoring conversation thread (LLM invocations)...');
    final allInvocations = await invocationRepo.findAll();
    final llmInvocations = allInvocations
        .where((inv) => inv.componentType == 'llm')
        .toList();

    // Apply time cutoff: only consider invocations within 3x half-life window
    // This limits embedding API calls while covering relevant candidates
    final cutoffHours = params.conversationHalfLifeHours * 3;
    final cutoffTime = now.subtract(Duration(hours: cutoffHours.round()));
    final candidates = llmInvocations
        .where((inv) => inv.updatedAt.isAfter(cutoffTime))
        .toList();

    print('   ${candidates.length} candidates within ${cutoffHours.toStringAsFixed(0)}h window');

    // Generate query embedding
    final queryEmbedding = await embeddingService.generate(transcription);

    // Score each candidate: similarity^α × decay^β
    final scoredCandidates = <(Invocation, double, double, double)>[];
    for (final inv in candidates) {
      // Get embeddable content from invocation
      final content = inv.toChunkableInput();
      if (content.isEmpty) continue;

      // Generate embedding for this invocation
      final invEmbedding = await embeddingService.generate(content);

      // Compute cosine similarity
      final similarity = _cosineSimilarity(queryEmbedding, invEmbedding);

      // Compute temporal decay
      final ageHours = now.difference(inv.updatedAt).inMinutes / 60.0;
      final decay = _computeDecay(ageHours, params.conversationHalfLifeHours);

      // Compute fused score: similarity^α × decay^β
      final fusedScore = pow(similarity, params.similarityAlpha) *
          pow(decay, params.decayBeta);

      scoredCandidates.add((inv, similarity, decay, fusedScore.toDouble()));
    }

    // Sort by fused score (highest first) and take top N
    scoredCandidates.sort((a, b) => b.$4.compareTo(a.$4));
    final topCandidates =
        scoredCandidates.take(params.conversationThreadSize).toList();

    // Extract invocations and sort chronologically for context
    final conversationThread = topCandidates.map((c) => c.$1).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    print('✅ Conversation thread: ${conversationThread.length} LLM invocations');

    // Log conversation thread with similarity and decay scores
    for (final candidate in topCandidates) {
      final inv = candidate.$1;
      final similarity = candidate.$2;
      final decay = candidate.$3;
      final fusedScore = candidate.$4;
      final ageHours = now.difference(inv.updatedAt).inMinutes / 60.0;
      print('   LLM (${ageHours.toStringAsFixed(1)}h ago): '
          'sim=${similarity.toStringAsFixed(3)}, '
          'decay=${decay.toStringAsFixed(3)}, '
          'fused=${fusedScore.toStringAsFixed(3)}');
    }

    // 2. Semantic search via SemanticSearchService (searches chunks from ALL entities)
    print('\n[2/4] Semantic search across all chunkable entities...');
    List<SemanticSearchResult> semanticResults = [];

    try {
      semanticResults = await semanticSearchService.search(
        transcription,
        limit: 100, // Get more candidates, we'll filter down
      );
      print('✅ Semantic search returned ${semanticResults.length} chunks');
    } catch (e) {
      print('⚠️ Semantic search failed (index may need rebuild): $e');
      // Continue with empty results - search failure shouldn't block response
    }

    // 3. Filter out chunks from conversation thread entities (dedup)
    print('\n[3/4] Deduplicating (removing conversation thread from semantic results)...');
    final uuidsInConversation =
        conversationThread.map((inv) => inv.uuid).toSet();
    final filteredResults = semanticResults
        .where((result) =>
            result.sourceEntity == null ||
            !uuidsInConversation.contains(result.sourceEntity!.uuid))
        .toList();
    print('✅ After dedup: ${filteredResults.length} chunks');

    // 4. Apply fused score: semantic similarity * temporal decay, then filter
    print('\n[4/4] Applying fused scoring and filtering...');
    final scored = filteredResults.map((result) {
      // Get timestamp from source entity if available
      final entityTime = result.sourceEntity?.updatedAt ?? now;
      final ageHours = now.difference(entityTime).inMinutes / 60.0;
      final decay = _computeDecay(ageHours, params.semanticHalfLifeHours);
      final fusedScore = result.similarity * decay;
      return (result, fusedScore, decay);
    }).toList();

    // Filter by threshold and sort by fused score
    final topResults = scored
        .where((item) => item.$1.similarity >= params.semanticThreshold)
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2)); // Sort by fused score

    final limitedResults = topResults.take(params.maxSemanticResults).toList();

    print('✅ Top semantic context: ${limitedResults.length} chunks');
    for (final item in limitedResults.take(5)) {
      final result = item.$1;
      final fusedScore = item.$2;
      final decay = item.$3;
      final entityType = result.chunk.sourceEntityType;
      print('   $entityType chunk: '
          'similarity=${result.similarity.toStringAsFixed(3)}, '
          'decay=${decay.toStringAsFixed(3)}, '
          'fused=${fusedScore.toStringAsFixed(3)}');
    }

    final bundle = ContextBundle(
      conversationThread: conversationThread,
      semanticContext: limitedResults.map((item) => item.$1).toList(),
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

  /// Compute cosine similarity between two embedding vectors
  ///
  /// Returns value in [0, 1] where 1 = identical direction
  /// Normalized embeddings give similarity = dot product
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) return 0.0;

    final similarity = dot / (sqrt(normA) * sqrt(normB));
    // Clamp to [0, 1] (cosine can be negative for opposing directions)
    return similarity.clamp(0.0, 1.0);
  }
}
