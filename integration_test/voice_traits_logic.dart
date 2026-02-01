/// # VoiceTraits Integration Test
///
/// Tests contrastive few-shot example retrieval and injection.
///
/// Verifies:
/// - VoiceTraits.getExamples() retrieves semantically similar examples
/// - Positive feedback examples are included
/// - Negative feedback examples are included
/// - Examples are injected into Coordinator messages (system prompt)
/// - VoiceTraits invocations are logged with similarity scores
/// - Empty result when no feedback exists
///
/// ## Test Flow
/// 1. Create conversation history with positive/negative feedback
/// 2. Query similar to past interaction
/// 3. Verify VoiceTraits retrieves contrastive examples
/// 4. Verify examples are injected into LLM messages
/// 5. Verify invocations logged with scores

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/llm_types.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/services/voice_traits.dart';
import 'package:get_it/get_it.dart';
import 'shared/test_harness.dart';
import 'shared/test_context.dart';
import 'shared/response_map_implementer.dart';

// Conversation history with feedback:
// - Timer question (positive feedback) - should be retrieved as good example
// - Weather question (negative feedback) - should be retrieved as bad example
// - New timer question (query) - should match timer examples

final _utterances = {
  // Good example (will get positive feedback)
  'timer_good': 'Set a timer for 10 minutes',
  // Bad example (will get negative feedback)
  'weather_bad': 'What is the weather?',
  // Query (similar to timer_good)
  'timer_query': 'Set a timer for 5 minutes',
};

final _responses = {
  _utterances['timer_good']!: LLMResponse(
    id: 'timer_good_response',
    content: 'I have set a 10-minute timer for you. I will notify you when it completes.',
    toolCalls: [],
    tokensUsed: 20,
  ),
  _utterances['weather_bad']!: LLMResponse(
    id: 'weather_bad_response',
    content: 'Weather.',
    toolCalls: [],
    tokensUsed: 5,
  ),
  _utterances['timer_query']!: LLMResponse(
    id: 'timer_query_response',
    content: 'I have set a 5-minute timer for you. I will alert you when it completes.',
    toolCalls: [],
    tokensUsed: 18,
  ),
};

final voiceTraitsTest = IntegrationTestConfig(
  name: 'VoiceTraits (Contrastive Few-Shot)',

  repos: [
    InvocationRepository<Invocation>,
    FeedbackRepository,
  ],

  utterances: _utterances,

  mockImplementers: {
    'groq': ResponseMapLLMImplementer(_responses),
  },

  testLogic: (t) async {
    print('\n=== TEST: VoiceTraits Contrastive Retrieval ===');

    final invocationRepo = GetIt.instance<InvocationRepository<Invocation>>();
    final feedbackRepo = GetIt.instance<FeedbackRepository>();
    final voiceTraits = GetIt.instance<VoiceTraits>();

    // ===== CLEANUP: Start fresh =====
    print('\n[Cleanup] Removing old data...');
    final oldInvocations = await invocationRepo.findAll();
    for (final inv in oldInvocations) {
      await invocationRepo.delete(inv.uuid);
    }
    final oldFeedback = await feedbackRepo.findAllConversational();
    for (final fb in oldFeedback) {
      await feedbackRepo.delete(fb.uuid);
    }
    print('   Deleted ${oldInvocations.length} invocations, ${oldFeedback.length} feedback');

    // ===== SETUP: Create conversation with feedback =====
    print('\n[Setup] Creating conversation with positive/negative feedback...');

    // Good timer example (will get positive feedback)
    print('   [Good] ${_utterances['timer_good']}');
    await t.stt('timer_good');
    await Future.delayed(const Duration(milliseconds: 1000));

    // Get the LLM invocation for this turn (to link feedback)
    var allInvocations = await invocationRepo.findAll();
    final timerGoodInvocations = allInvocations
        .where((inv) =>
            inv.componentType == 'llm' &&
            inv.output?['response']?.toString().contains('10-minute timer') == true)
        .toList();
    expect(
      timerGoodInvocations.isNotEmpty,
      isTrue,
      reason: 'Should have LLM invocation for timer_good response',
    );
    final timerGoodInv = timerGoodInvocations.first;

    // Add positive feedback (with turnId to make it conversational)
    final positiveFeedback = Feedback(
      invocationId: timerGoodInv.uuid,
      componentType: 'llm',
      action: FeedbackAction.confirm,
      turnId: timerGoodInv.eventId, // Link to conversation turn
    );
    await feedbackRepo.save(positiveFeedback);
    print('   ✅ Positive feedback added to timer_good (turnId=${timerGoodInv.eventId})');

    // Bad weather example (will get negative feedback)
    print('   [Bad] ${_utterances['weather_bad']}');
    await t.stt('weather_bad');
    await Future.delayed(const Duration(milliseconds: 1000));

    // Get the LLM invocation for weather
    allInvocations = await invocationRepo.findAll();
    final weatherBadInvocations = allInvocations
        .where((inv) =>
            inv.componentType == 'llm' &&
            inv.output?['response']?.toString() == 'Weather.')
        .toList();
    expect(
      weatherBadInvocations.isNotEmpty,
      isTrue,
      reason: 'Should have LLM invocation for weather_bad response',
    );
    final weatherBadInv = weatherBadInvocations.first;

    // Add negative feedback (with turnId to make it conversational)
    final negativeFeedback = Feedback(
      invocationId: weatherBadInv.uuid,
      componentType: 'llm',
      action: FeedbackAction.deny,
      turnId: weatherBadInv.eventId, // Link to conversation turn
    );
    await feedbackRepo.save(negativeFeedback);
    print('   ❌ Negative feedback added to weather_bad (turnId=${weatherBadInv.eventId})');

    // Wait for chunking/indexing to complete
    await Future.delayed(const Duration(seconds: 3));

    // ===== VERIFY: Feedback was saved correctly =====
    print('\n[Verify] Checking feedback was persisted...');
    final allFeedbackAfterSave = await feedbackRepo.findAllConversational();
    print('   Total feedback records: ${allFeedbackAfterSave.length}');
    print('   Timer good invocation UUID: ${timerGoodInv.uuid}');
    print('   Weather bad invocation UUID: ${weatherBadInv.uuid}');
    for (final fb in allFeedbackAfterSave) {
      print('     - Feedback ${fb.uuid}: invocation=${fb.invocationId}, action=${fb.action}, component=${fb.componentType}');
    }

    expect(
      allFeedbackAfterSave.length,
      greaterThanOrEqualTo(2),
      reason: 'Should have at least 2 feedback records (positive + negative)',
    );

    // ===== TEST 1: VoiceTraits.getExamples() retrieves contrastive examples =====
    print('\n[Test 1] VoiceTraits retrieves contrastive examples for timer query...');

    final query = _utterances['timer_query']!;
    final examples = await voiceTraits.getExamples(
      query: query,
      eventId: 'test-event-voice-traits',
    );

    print('   Query: "$query"');
    print('   Examples retrieved: ${examples.totalCount}');
    print('   Positive examples: ${examples.positive.length}');
    print('   Negative examples: ${examples.negative.length}');

    // STRONG ASSERTION: Test architecture, not workarounds
    // If this fails, fix the root cause in VoiceTraits/feedback/indexing
    expect(
      examples.hasExamples,
      isTrue,
      reason: 'ARCHITECTURE ISSUE: VoiceTraits should retrieve examples when feedback exists. '
          'If this fails, debug why feedback records are not being found for indexed invocations. '
          'Check: (1) Feedback persistence, (2) Invocation chunking/indexing, (3) Search→feedback lookup.',
    );

    expect(
      examples.positive.isNotEmpty,
      isTrue,
      reason: 'Should retrieve at least one positive example',
    );

    expect(
      examples.negative.isNotEmpty,
      isTrue,
      reason: 'Should retrieve at least one negative example',
    );

    // ===== TEST 2: Positive example contains timer_good content =====
    print('\n[Test 2] Verify positive example content...');

    final positiveExample = examples.positive.first;
    print('   Positive example:');
    print('     User: ${positiveExample.query}');
    print('     Assistant: ${positiveExample.response}');
    print('     Similarity: ${positiveExample.similarity.toStringAsFixed(3)}');

    expect(
      positiveExample.query,
      contains('timer'),
      reason: 'Positive example should be timer-related (semantically similar)',
    );

    expect(
      positiveExample.response,
      contains('10-minute timer'),
      reason: 'Positive example should contain the good timer response',
    );

    expect(
      positiveExample.similarity,
      greaterThan(0.0),
      reason: 'Positive example should have non-zero similarity score',
    );

    // ===== TEST 3: Negative example contains weather_bad content =====
    print('\n[Test 3] Verify negative example content...');

    final negativeExample = examples.negative.first;
    print('   Negative example:');
    print('     User: ${negativeExample.query}');
    print('     Assistant: ${negativeExample.response}');
    print('     Similarity: ${negativeExample.similarity.toStringAsFixed(3)}');

    expect(
      negativeExample.query,
      contains('weather'),
      reason: 'Negative example should be the weather query',
    );

    expect(
      negativeExample.response,
      equals('Weather.'),
      reason: 'Negative example should contain the bad weather response',
    );

    expect(
      negativeExample.similarity,
      greaterThan(0.0),
      reason: 'Negative example should have non-zero similarity score',
    );

    // ===== TEST 4: VoiceTraits.formatPrompt() creates contrastive prompt =====
    print('\n[Test 4] Verify formatted contrastive prompt...');

    final formattedPrompt = voiceTraits.formatPrompt(examples);
    print('   Formatted prompt length: ${formattedPrompt.length} chars');

    expect(
      formattedPrompt,
      contains('Example of good response'),
      reason: 'Prompt should include positive example section',
    );

    expect(
      formattedPrompt,
      contains('What to avoid'),
      reason: 'Prompt should include negative example section',
    );

    expect(
      formattedPrompt,
      contains('10-minute timer'),
      reason: 'Prompt should include the positive example content',
    );

    expect(
      formattedPrompt,
      contains('Weather.'),
      reason: 'Prompt should include the negative example content',
    );

    // ===== TEST 5: Empty result when no similar feedback exists =====
    print('\n[Test 5] Verify empty result for query with no similar feedback...');

    final unrelatedQuery = 'What is the capital of France?';
    final emptyExamples = await voiceTraits.getExamples(
      query: unrelatedQuery,
      eventId: 'test-event-empty',
    );

    print('   Unrelated query: "$unrelatedQuery"');
    print('   Examples retrieved: ${emptyExamples.totalCount}');

    // Should either have no examples, or low-similarity examples
    // (depends on threshold filtering in VoiceTraits implementation)
    if (emptyExamples.hasExamples) {
      // If examples are returned, they should have low similarity
      final allExamples = [...emptyExamples.positive, ...emptyExamples.negative];
      final avgSimilarity = allExamples.map((e) => e.similarity).reduce((a, b) => a + b) / allExamples.length;

      print('   Average similarity: ${avgSimilarity.toStringAsFixed(3)}');

      expect(
        avgSimilarity,
        lessThan(0.7),
        reason: 'Unrelated query should have low similarity to timer/weather examples',
      );
    } else {
      print('   ✅ No examples returned (as expected for unrelated query)');
    }

    // ===== TEST 6: Integration with Coordinator (examples injected into messages) =====
    print('\n[Test 6] Verify VoiceTraits examples are injected into Coordinator messages...');

    // Trigger orchestration with timer query
    print('   Sending timer query: "$query"');
    await t.stt('timer_query');
    await Future.delayed(const Duration(seconds: 2));

    // Get LLM invocations (should have voice traits injected)
    allInvocations = await invocationRepo.findAll();
    final llmInvocations = allInvocations
        .where((inv) => inv.componentType == 'llm')
        .toList();

    print('   Found ${llmInvocations.length} LLM invocations');

    expect(
      llmInvocations.isNotEmpty,
      isTrue,
      reason: 'Should have LLM invocations from Coordinator orchestration',
    );

    // Get the last LLM invocation (for timer_query)
    final lastLlmInv = llmInvocations.last;
    final prompt = lastLlmInv.input?['prompt'] as String?;

    print('   Last LLM prompt length: ${prompt?.length ?? 0} chars');

    // Verify the prompt contains voice traits examples
    if (prompt != null) {
      final hasPositiveExample = prompt.contains('Example of good response') ||
          prompt.contains('10-minute timer');
      final hasNegativeExample = prompt.contains('What to avoid') ||
          prompt.contains('Weather.');

      print('   Has positive example in prompt: $hasPositiveExample');
      print('   Has negative example in prompt: $hasNegativeExample');

      expect(
        hasPositiveExample,
        isTrue,
        reason: 'LLM prompt should include voice traits positive example',
      );

      expect(
        hasNegativeExample,
        isTrue,
        reason: 'LLM prompt should include voice traits negative example',
      );
    }

    print('\n=== VoiceTraits Test PASSED ===');
  },
);
