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

    final optimizer = _getOrCreateOptimizer(userId);

    final state = await getAdaptationState(userId: userId);
    final params = state.dataJson?.isNotEmpty == true
        ? deserializeData(state.dataJson!)
        : createDefaultData();

    final feedbackReward =
        feedback.action == domain_feedback.FeedbackAction.confirm ? 1.0 : -1.0;

    await optimizer.recordTrial({
      'conversationThreadSize': params.conversationThreadSize,
      'conversationHalfLifeHours': params.conversationHalfLifeHours,
      'maxSemanticResults': params.maxSemanticResults,
      'semanticHalfLifeHours': params.semanticHalfLifeHours,
      'semanticThreshold': params.semanticThreshold,
      'similarityAlpha': params.similarityAlpha,
      'decayBeta': params.decayBeta,
    }, feedbackReward);

    final suggestedParams = await optimizer.suggestNext();

    final newParams = params.copyWith(
      conversationThreadSize: suggestedParams['conversationThreadSize'] as int,
      conversationHalfLifeHours:
          suggestedParams['conversationHalfLifeHours'] as double,
      maxSemanticResults: suggestedParams['maxSemanticResults'] as int,
      semanticHalfLifeHours: suggestedParams['semanticHalfLifeHours'] as double,
      semanticThreshold: suggestedParams['semanticThreshold'] as double,
      similarityAlpha: suggestedParams['similarityAlpha'] as double,
      decayBeta: suggestedParams['decayBeta'] as double,
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

  Future<ContextBundle> selectContext({
    required String eventId,
    required String transcription,
    String? userId,
  }) async {
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

    print('\n[1/4] Loading and scoring conversation thread (LLM invocations)...');
    final allInvocations = await invocationRepo.findAll();
    final llmInvocations = allInvocations
        .where((invocation) => invocation.componentType == 'llm')
        .toList();

    // Only consider invocations within 3x half-life window to limit embedding API calls
    final cutoffHours = params.conversationHalfLifeHours * 3;
    final cutoffTime = now.subtract(Duration(hours: cutoffHours.round()));
    final candidates = llmInvocations
        .where((invocation) => invocation.updatedAt.isAfter(cutoffTime))
        .toList();

    print('   ${candidates.length} candidates within ${cutoffHours.toStringAsFixed(0)}h window');

    final queryEmbedding = await embeddingService.generate(transcription);

    final scoredCandidates = <(Invocation, double, double, double)>[];
    for (final llmInvocation in candidates) {
      final chunkableContent = llmInvocation.toChunkableInput();
      if (chunkableContent.isEmpty) continue;

      final invocationEmbedding = await embeddingService.generate(chunkableContent);

      final similarity = _cosineSimilarity(queryEmbedding, invocationEmbedding);

      final ageHours = now.difference(llmInvocation.updatedAt).inMinutes / 60.0;
      final decay = _computeDecay(ageHours, params.conversationHalfLifeHours);

      final fusedScore = pow(similarity, params.similarityAlpha) *
          pow(decay, params.decayBeta);

      scoredCandidates.add((llmInvocation, similarity, decay, fusedScore.toDouble()));
    }

    scoredCandidates.sort((a, b) => b.$4.compareTo(a.$4));
    final topCandidates =
        scoredCandidates.take(params.conversationThreadSize).toList();

    final conversationThread = topCandidates.map((candidate) => candidate.$1).toList()
      ..sort((olderInv, newerInv) => olderInv.createdAt.compareTo(newerInv.createdAt));

    print('✅ Conversation thread: ${conversationThread.length} LLM invocations');

    for (final candidate in topCandidates) {
      final llmInvocation = candidate.$1;
      final similarity = candidate.$2;
      final decay = candidate.$3;
      final fusedScore = candidate.$4;
      final ageHours = now.difference(llmInvocation.updatedAt).inMinutes / 60.0;
      print('   LLM (${ageHours.toStringAsFixed(1)}h ago): '
          'sim=${similarity.toStringAsFixed(3)}, '
          'decay=${decay.toStringAsFixed(3)}, '
          'fused=${fusedScore.toStringAsFixed(3)}');
    }

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

    // Dedup: remove chunks from entities already in conversation thread
    print('\n[3/4] Deduplicating (removing conversation thread from semantic results)...');
    final uuidsInConversation =
        conversationThread.map((inv) => inv.uuid).toSet();
    final filteredResults = semanticResults
        .where((searchResult) =>
            searchResult.sourceEntity == null ||
            !uuidsInConversation.contains(searchResult.sourceEntity!.uuid))
        .toList();
    print('✅ After dedup: ${filteredResults.length} chunks');

    print('\n[4/4] Applying fused scoring and filtering...');
    final scoredChunks = filteredResults.map((searchResult) {
      final entityTime = searchResult.sourceEntity?.updatedAt ?? now;
      final ageHours = now.difference(entityTime).inMinutes / 60.0;
      final decay = _computeDecay(ageHours, params.semanticHalfLifeHours);
      final fusedScore = searchResult.similarity * decay;
      return (searchResult, fusedScore, decay);
    }).toList();

    final topChunks = scoredChunks
        .where((scoredChunk) => scoredChunk.$1.similarity >= params.semanticThreshold)
        .toList()
      ..sort((chunkA, chunkB) => chunkB.$2.compareTo(chunkA.$2));

    final limitedChunks = topChunks.take(params.maxSemanticResults).toList();

    print('✅ Top semantic context: ${limitedChunks.length} chunks');
    for (final scoredChunk in limitedChunks.take(5)) {
      final searchResult = scoredChunk.$1;
      final fusedScore = scoredChunk.$2;
      final decay = scoredChunk.$3;
      final entityType = searchResult.chunk.sourceEntityType;
      print('   $entityType chunk: '
          'similarity=${searchResult.similarity.toStringAsFixed(3)}, '
          'decay=${decay.toStringAsFixed(3)}, '
          'fused=${fusedScore.toStringAsFixed(3)}');
    }

    final bundle = ContextBundle(
      conversationThread: conversationThread,
      semanticContext: limitedChunks.map((scoredChunk) => scoredChunk.$1).toList(),
      params: params,
    );

    print('\n✅ ContextBundle created: ${bundle.summary}');

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
  double _cosineSimilarity(List<double> embeddingA, List<double> embeddingB) {
    if (embeddingA.length != embeddingB.length) return 0.0;

    var dotProduct = 0.0;
    var normSquaredA = 0.0;
    var normSquaredB = 0.0;

    for (var i = 0; i < embeddingA.length; i++) {
      dotProduct += embeddingA[i] * embeddingB[i];
      normSquaredA += embeddingA[i] * embeddingA[i];
      normSquaredB += embeddingB[i] * embeddingB[i];
    }

    if (normSquaredA == 0 || normSquaredB == 0) return 0.0;

    final similarity = dotProduct / (sqrt(normSquaredA) * sqrt(normSquaredB));
    // Clamp to [0, 1] (cosine can be negative for opposing directions)
    return similarity.clamp(0.0, 1.0);
  }
}
