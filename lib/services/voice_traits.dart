/// # VoiceTraits
///
/// ## What it does
/// Retrieves contrastive few-shot examples from past interactions
/// based on user feedback. Uses semantic similarity to find relevant
/// examples and feedback signals to classify as positive/negative.
///
/// ## How it works
/// 1. Search chunks similar to current query (via SemanticSearchService)
/// 2. Filter to LLM invocations only
/// 3. Look up feedback for each invocation
/// 4. Score by similarity × decay (learned parameters)
/// 5. Return top examples for contrastive prompting
///
/// ## Why Trainable?
/// VoiceTraits learns optimal retrieval parameters from feedback:
/// - How many examples improve response quality
/// - Similarity threshold for relevance
/// - How much to weight recent vs old examples (decay)
///
/// ## Why contrastive few-shot?
/// - Shows model what "good" responses look like
/// - Shows model what to avoid
/// - Learned from actual user feedback, not hardcoded
/// - Personalized to user's preferences over time
///
/// ## Usage
/// ```dart
/// final examples = await voiceTraits.getExamples(
///   query: 'Set a timer for 5 minutes',
///   eventId: 'evt_123',
/// );
///
/// // Use in prompt
/// final prompt = voiceTraits.formatPrompt(examples);
/// // Inject into system message or context
/// ```

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../core/trainable.dart';
import '../core/invocation.dart';
import '../core/invocation_repository.dart';
import '../core/adaptation_state_repository.dart';
import '../core/feedback_repository.dart';
import '../domain/feedback.dart' as domain_feedback;
import 'semantic_search/semantic_search_service.dart';
import 'types/voice_traits_types.dart';

class VoiceTraits with Trainable<VoiceTraitsAdaptationData> {
  final SemanticSearchService searchService;
  final InvocationRepository<Invocation> invocationRepo;
  final FeedbackRepository feedbackRepo;

  VoiceTraits({
    required this.searchService,
    required this.invocationRepo,
    required this.feedbackRepo,
  });

  // ============ Trainable Implementation ============

  @override
  String get componentType => 'voice_traits';

  @override
  VoiceTraitsAdaptationData createDefaultData() =>
      VoiceTraitsAdaptationData.defaults();

  @override
  VoiceTraitsAdaptationData deserializeData(String json) {
    if (json.isEmpty || json == '{}') {
      return createDefaultData();
    }
    return VoiceTraitsAdaptationData.fromJson(
      Map<String, dynamic>.from(
        const JsonDecoder().convert(json) as Map,
      ),
    );
  }

  @override
  Map<String, (double, double)> getParameterBounds() {
    return {
      'maxPositiveExamples': (1.0, 5.0),
      'maxNegativeExamples': (0.0, 3.0),
      'minSimilarity': (0.1, 0.7),
      'decayAlpha': (0.5, 2.0),
      'decayRate': (0.01, 0.5),
    };
  }

  @override
  Widget buildFeedbackUI(BuildContext context, Invocation invocation) {
    final output = invocation.output;
    final positiveCount = output?['positiveCount'] as int? ?? 0;
    final negativeCount = output?['negativeCount'] as int? ?? 0;
    final avgScore = output?['avgScore'] as double? ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Voice Traits:',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Positive examples: $positiveCount'),
              Text('Negative examples: $negativeCount'),
              Text('Avg score: ${(avgScore * 100).toStringAsFixed(1)}%'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Were the examples helpful?',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ElevatedButton(
              onPressed: () {
                // TODO: Record positive feedback
              },
              child: const Text('Yes, helpful'),
            ),
            OutlinedButton(
              onPressed: () {
                // TODO: Record "need more" feedback
              },
              child: const Text('Need more examples'),
            ),
            OutlinedButton(
              onPressed: () {
                // TODO: Record "too many" feedback
              },
              child: const Text('Too many examples'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> trainFromFeedback(
    Invocation invocation,
    domain_feedback.Feedback feedback,
  ) async {
    // 1. Get current adaptation state
    final adaptationStateRepo = GetIt.instance<AdaptationStateRepository>();
    final state = await getAdaptationState();
    final params = state.dataJson.isNotEmpty
        ? deserializeData(state.dataJson)
        : createDefaultData();

    // 2. Adjust based on feedback
    var newParams = params;
    final feedbackText = feedback.correctedData?.toLowerCase() ?? '';

    if (feedback.action == domain_feedback.FeedbackAction.confirm) {
      // Positive feedback - current settings work well
      print('📊 [VoiceTraits] Positive feedback for current settings');
    } else if (feedback.action == domain_feedback.FeedbackAction.deny) {
      // Negative feedback - adjust based on correction text
      if (feedbackText.contains('more') || feedbackText.contains('few')) {
        // Need more examples
        newParams = params.copyWith(
          maxPositiveExamples: (params.maxPositiveExamples + 1).clamp(1, 5),
        );
        print('📊 [VoiceTraits] Increasing positive examples: ${params.maxPositiveExamples} → ${newParams.maxPositiveExamples}');
      } else if (feedbackText.contains('many') || feedbackText.contains('too')) {
        // Too many examples
        newParams = params.copyWith(
          maxPositiveExamples: (params.maxPositiveExamples - 1).clamp(1, 5),
        );
        print('📊 [VoiceTraits] Decreasing positive examples: ${params.maxPositiveExamples} → ${newParams.maxPositiveExamples}');
      } else if (feedbackText.contains('old') || feedbackText.contains('stale')) {
        // Examples too old - increase decay rate
        newParams = params.copyWith(
          decayRate: (params.decayRate * 1.2).clamp(0.01, 0.5),
        );
        print('📊 [VoiceTraits] Increasing decay rate: ${params.decayRate} → ${newParams.decayRate}');
      }
    }

    // 3. Save updated state if changed
    if (newParams != params) {
      state.dataJson = newParams.toJson();
      state.version++;
      state.lastUpdatedAt = DateTime.now();
      state.lastUpdateReason = 'trainFromFeedback';
      state.feedbackCountApplied++;

      await adaptationStateRepo.save(state);
      print('✅ [VoiceTraits] Adaptation state saved');
    }
  }

  // ============ Example Retrieval ============

  /// Retrieve contrastive examples similar to query.
  ///
  /// Searches for past LLM invocations similar to the current query,
  /// then filters by feedback to get positive and negative examples.
  /// Uses learned parameters for similarity threshold, example counts,
  /// and decay scoring.
  Future<ContrastiveExamples> getExamples({
    required String query,
    required String eventId,
    String? userId,
  }) async {
    print('\n🎭 [VoiceTraits] Searching for contrastive examples...');
    print('   Query: "${query.length > 50 ? '${query.substring(0, 50)}...' : query}"');

    try {
      // 1. Get learned parameters
      final state = await getAdaptationState(userId: userId);
      final params = state.dataJson.isNotEmpty
          ? deserializeData(state.dataJson)
          : createDefaultData();

      print('   Params: max+=${params.maxPositiveExamples}, max-=${params.maxNegativeExamples}, sim>=${params.minSimilarity}');

      // 2. Search for similar chunks (search more than we need for filtering)
      final searchLimit = (params.maxPositiveExamples + params.maxNegativeExamples) * 5;
      final searchResults = await searchService.search(
        query,
        entityTypes: ['Invocation'],
        limit: searchLimit,
      );

      print('   Found ${searchResults.length} similar invocations');

      if (searchResults.isEmpty) {
        print('   ⚠️ No similar invocations found');
        await _recordInvocation(eventId, query, 0, ContrastiveExamples.empty());
        return ContrastiveExamples.empty();
      }

      // 3. Get invocation UUIDs and look up feedback
      final invocationIds = searchResults
          .where((r) => r.sourceEntity != null)
          .map((r) => r.sourceEntity!.uuid)
          .toList();

      print('   Invocation IDs from search (${invocationIds.length} total):');
      for (var i = 0; i < invocationIds.length && i < 3; i++) {
        print('     [$i] ${invocationIds[i]}');
      }

      final feedbackList = await feedbackRepo.findByInvocationIds(invocationIds);
      print('   Found ${feedbackList.length} feedback records');
      if (feedbackList.isNotEmpty) {
        print('   Feedback invocation IDs:');
        for (final fb in feedbackList) {
          print('     - ${fb.invocationId} (action=${fb.action})');
        }
      }

      // 4. Build map of invocation -> feedback
      final feedbackMap = <String, domain_feedback.Feedback>{};
      for (final f in feedbackList) {
        // Only consider LLM feedback, prefer most recent
        if (f.componentType == 'llm') {
          final existing = feedbackMap[f.invocationId];
          if (existing == null || f.timestamp.isAfter(existing.timestamp)) {
            feedbackMap[f.invocationId] = f;
          }
        }
      }

      // 5. Build examples with feedback and decay scoring
      final now = DateTime.now();
      final allPositive = <FeedbackExample>[];
      final allNegative = <FeedbackExample>[];

      for (final result in searchResults) {
        if (result.sourceEntity == null) continue;
        if (result.similarity < params.minSimilarity) continue;

        final invocation = result.sourceEntity as Invocation;
        final feedback = feedbackMap[invocation.uuid];

        // Skip invocations without feedback
        if (feedback == null) continue;

        // Skip ignored feedback
        if (feedback.action == domain_feedback.FeedbackAction.ignore) continue;

        // Extract query and response from invocation
        final invQuery = _extractQuery(invocation);
        final invResponse = _extractResponse(invocation);

        if (invQuery == null || invResponse == null) continue;

        // Compute age and score with decay
        final age = now.difference(invocation.createdAt);
        final score = params.computeScore(result.similarity, age);

        final example = FeedbackExample(
          query: invQuery,
          response: invResponse,
          feedbackAction: feedback.action,
          similarity: result.similarity,
          invocationId: invocation.uuid,
          timestamp: invocation.createdAt,
          score: score,
        );

        // Classify by feedback action
        if (feedback.action == domain_feedback.FeedbackAction.confirm) {
          allPositive.add(example);
        } else if (feedback.action == domain_feedback.FeedbackAction.deny) {
          allNegative.add(example);
        }
      }

      // 6. Sort by score and take top-k
      allPositive.sort((a, b) => b.score.compareTo(a.score));
      allNegative.sort((a, b) => b.score.compareTo(a.score));

      final positiveExamples = allPositive.take(params.maxPositiveExamples).toList();
      final negativeExamples = allNegative.take(params.maxNegativeExamples).toList();

      print('   ✅ Found ${positiveExamples.length} positive, ${negativeExamples.length} negative examples');

      final examples = ContrastiveExamples(
        positive: positiveExamples,
        negative: negativeExamples,
      );

      // 7. Record invocation for training
      await _recordInvocation(eventId, query, searchResults.length, examples);

      return examples;
    } catch (e) {
      // Search may fail if index is stale - degrade gracefully
      print('   ⚠️ VoiceTraits search failed: $e');
      return ContrastiveExamples.empty();
    }
  }

  /// Record invocation for training.
  Future<void> _recordInvocation(
    String eventId,
    String query,
    int candidatesSearched,
    ContrastiveExamples examples,
  ) async {
    final allExamples = [...examples.positive, ...examples.negative];
    final avgScore = allExamples.isEmpty
        ? 0.0
        : allExamples.map((e) => e.score).reduce((a, b) => a + b) / allExamples.length;

    await recordInvocation(
      eventId,
      Invocation(
        eventId: eventId,
        componentType: componentType,
        implementer: null,
        success: true,
        confidence: avgScore,
        input: VoiceTraitsInvocationInput(
          query: query,
          candidatesSearched: candidatesSearched,
        ).toJson(),
        output: VoiceTraitsInvocationOutput(
          positiveCount: examples.positive.length,
          negativeCount: examples.negative.length,
          exampleIds: allExamples.map((e) => e.invocationId).toList(),
          avgScore: avgScore,
        ).toJson(),
      ),
    );
  }

  /// Format contrastive examples as a prompt section.
  ///
  /// Returns a string suitable for injection into system message
  /// or context. Returns empty string if no examples.
  String formatPrompt(ContrastiveExamples examples) {
    if (!examples.hasExamples) return '';

    final buffer = StringBuffer();
    buffer.writeln('## Response Style');
    buffer.writeln();

    // Positive examples
    if (examples.positive.isNotEmpty) {
      buffer.writeln('Examples of good responses for similar questions:');
      buffer.writeln();
      for (final ex in examples.positive) {
        buffer.writeln('User: ${ex.query}');
        buffer.writeln('Assistant: ${ex.response}');
        buffer.writeln();
      }
    }

    // Negative examples
    if (examples.negative.isNotEmpty) {
      buffer.writeln('What to avoid:');
      buffer.writeln();
      for (final ex in examples.negative) {
        buffer.writeln('User: ${ex.query}');
        buffer.writeln('Assistant: ${ex.response}');
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Extract user query from LLM invocation input.
  String? _extractQuery(Invocation invocation) {
    if (invocation.componentType != 'llm') return null;

    final input = invocation.input;
    if (input == null) return null;

    // Try to extract from messages array
    final messages = input['messages'] as List<dynamic>?;
    if (messages != null && messages.isNotEmpty) {
      // Find last user message
      for (int i = messages.length - 1; i >= 0; i--) {
        final msg = messages[i] as Map<String, dynamic>;
        if (msg['role'] == 'user') {
          return msg['content'] as String?;
        }
      }
    }

    // Try utterance field
    return input['utterance'] as String?;
  }

  /// Extract assistant response from LLM invocation output.
  String? _extractResponse(Invocation invocation) {
    if (invocation.componentType != 'llm') return null;

    final output = invocation.output;
    if (output == null) return null;

    // Try content field directly
    final content = output['content'] as String?;
    if (content != null && content.isNotEmpty) return content;

    // Try response field
    return output['response'] as String?;
  }
}
