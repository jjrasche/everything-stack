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
/// 4. Separate into positive (confirm) and negative (deny)
/// 5. Return top examples for contrastive prompting
///
/// ## Why contrastive few-shot?
/// - Shows model what "good" responses look like
/// - Shows model what to avoid
/// - Learned from actual user feedback, not hardcoded
/// - Personalized to user's preferences over time
///
/// ## NOT a Trainable
/// Unlike ModelSelector, VoiceTraits doesn't have adaptation state.
/// It retrieves from existing entities (Invocation + Feedback).
/// Learning happens implicitly through accumulated feedback.
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
import '../core/invocation.dart';
import '../core/invocation_repository.dart';
import '../core/feedback_repository.dart';
import '../domain/feedback.dart';
import 'semantic_search/semantic_search_service.dart';
import 'types/voice_traits_types.dart';

class VoiceTraits {
  final SemanticSearchService searchService;
  final InvocationRepository<Invocation> invocationRepo;
  final FeedbackRepository feedbackRepo;
  final VoiceTraitsConfig config;

  VoiceTraits({
    required this.searchService,
    required this.invocationRepo,
    required this.feedbackRepo,
    this.config = VoiceTraitsConfig.defaults,
  });

  /// Retrieve contrastive examples similar to query.
  ///
  /// Searches for past LLM invocations similar to the current query,
  /// then filters by feedback to get positive and negative examples.
  ///
  /// Returns [ContrastiveExamples] with up to [config.maxPositiveExamples]
  /// positive and [config.maxNegativeExamples] negative examples.
  Future<ContrastiveExamples> getExamples({
    required String query,
    required String eventId,
  }) async {
    print('\n🎭 [VoiceTraits] Searching for contrastive examples...');
    print('   Query: "${query.length > 50 ? '${query.substring(0, 50)}...' : query}"');

    try {
      // 1. Search for similar chunks (search more than we need for filtering)
      final searchLimit = (config.maxPositiveExamples + config.maxNegativeExamples) * 5;
      final searchResults = await searchService.search(
        query,
        entityTypes: ['Invocation'],
        limit: searchLimit,
      );

      print('   Found ${searchResults.length} similar invocations');

      if (searchResults.isEmpty) {
        print('   ⚠️ No similar invocations found');
        return ContrastiveExamples.empty();
      }

      // 2. Get invocation UUIDs and look up feedback
      final invocationIds = searchResults
          .where((r) => r.sourceEntity != null)
          .map((r) => r.sourceEntity!.uuid)
          .toList();

      print('   Invocation IDs from search: ${invocationIds.take(3).join(", ")}...');

      final feedbackList = await feedbackRepo.findByInvocationIds(invocationIds);
      print('   Found ${feedbackList.length} feedback records');
      if (feedbackList.isNotEmpty) {
        print('   Feedback invocation IDs: ${feedbackList.map((f) => f.invocationId).join(", ")}');
      }

      // 3. Build map of invocation -> feedback
      final feedbackMap = <String, Feedback>{};
      for (final f in feedbackList) {
        // Only consider LLM feedback, prefer most recent
        if (f.componentType == 'llm') {
          final existing = feedbackMap[f.invocationId];
          if (existing == null || f.timestamp.isAfter(existing.timestamp)) {
            feedbackMap[f.invocationId] = f;
          }
        }
      }

      // 4. Build examples with feedback
      final positiveExamples = <FeedbackExample>[];
      final negativeExamples = <FeedbackExample>[];

      for (final result in searchResults) {
        if (result.sourceEntity == null) continue;
        if (result.similarity < config.minSimilarity) continue;

        final invocation = result.sourceEntity as Invocation;
        final feedback = feedbackMap[invocation.uuid];

        // Skip invocations without feedback
        if (feedback == null) continue;

        // Skip ignored feedback
        if (feedback.action == FeedbackAction.ignore) continue;

        // Extract query and response from invocation
        final invQuery = _extractQuery(invocation);
        final invResponse = _extractResponse(invocation);

        if (invQuery == null || invResponse == null) continue;

        // Check age limit
        if (config.maxAge != null) {
          final age = DateTime.now().difference(invocation.createdAt);
          if (age > config.maxAge!) continue;
        }

        final example = FeedbackExample(
          query: invQuery,
          response: invResponse,
          feedbackAction: feedback.action,
          similarity: result.similarity,
          invocationId: invocation.uuid,
          timestamp: invocation.createdAt,
        );

        // Classify by feedback action
        if (feedback.action == FeedbackAction.confirm) {
          if (positiveExamples.length < config.maxPositiveExamples) {
            positiveExamples.add(example);
          }
        } else if (feedback.action == FeedbackAction.deny) {
          if (negativeExamples.length < config.maxNegativeExamples) {
            negativeExamples.add(example);
          }
        }

        // Stop early if we have enough
        if (positiveExamples.length >= config.maxPositiveExamples &&
            negativeExamples.length >= config.maxNegativeExamples) {
          break;
        }
      }

      print('   ✅ Found ${positiveExamples.length} positive, ${negativeExamples.length} negative examples');

      return ContrastiveExamples(
        positive: positiveExamples,
        negative: negativeExamples,
      );
    } catch (e) {
      // Search may fail if index is stale - degrade gracefully
      print('   ⚠️ VoiceTraits search failed: $e');
      return ContrastiveExamples.empty();
    }
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
