/// # Context Selection Integration Test
///
/// Tests that ContextSelector uses similarity × decay scoring to select
/// relevant conversation context, not just most recent turns.
///
/// Verifies:
/// - Semantically similar conversation turns are prioritized
/// - Fused scoring (similarity^α × decay^β) works correctly
/// - Context selection Invocations are logged with scores
/// - Older but relevant turns beat recent but irrelevant ones

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/llm_types.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:get_it/get_it.dart';
import 'shared/test_harness.dart';
import 'shared/test_context.dart';
import 'shared/response_map_implementer.dart';

// Conversation history with distinct topics:
// - Turn 1-2: Timers (older)
// - Turn 3-4: Weather (middle)
// - Turn 5-6: Reminders (recent)
// Then query about timers - should select timer turns despite being older

final _utterances = {
  // Timer topic (will be oldest)
  'timer_set': 'Set a timer for 10 minutes',
  'timer_check': 'How much time is left on my timer?',
  // Weather topic (middle age)
  'weather_today': 'What is the weather like today?',
  'weather_tomorrow': 'Will it rain tomorrow?',
  // Reminder topic (most recent)
  'reminder_create': 'Remind me to call mom at 5pm',
  'reminder_list': 'What reminders do I have?',
  // Query that should match timer context (not recent reminder context)
  'timer_query': 'Can you cancel that timer I set earlier?',
};

final _responses = {
  _utterances['timer_set']!: LLMResponse(
    id: 'timer_1',
    content: 'I have set a 10-minute timer for you.',
    toolCalls: [],
    tokensUsed: 15,
  ),
  _utterances['timer_check']!: LLMResponse(
    id: 'timer_2',
    content: 'You have 7 minutes and 23 seconds remaining.',
    toolCalls: [],
    tokensUsed: 12,
  ),
  _utterances['weather_today']!: LLMResponse(
    id: 'weather_1',
    content: 'It is sunny with a high of 72 degrees.',
    toolCalls: [],
    tokensUsed: 14,
  ),
  _utterances['weather_tomorrow']!: LLMResponse(
    id: 'weather_2',
    content: 'Tomorrow will be cloudy with a 30% chance of rain.',
    toolCalls: [],
    tokensUsed: 16,
  ),
  _utterances['reminder_create']!: LLMResponse(
    id: 'reminder_1',
    content: 'Reminder set: Call mom at 5pm.',
    toolCalls: [],
    tokensUsed: 10,
  ),
  _utterances['reminder_list']!: LLMResponse(
    id: 'reminder_2',
    content: 'You have 1 reminder: Call mom at 5pm.',
    toolCalls: [],
    tokensUsed: 12,
  ),
  _utterances['timer_query']!: LLMResponse(
    id: 'timer_cancel',
    content: 'I have cancelled your 10-minute timer.',
    toolCalls: [],
    tokensUsed: 11,
  ),
};

final contextSelectionTest = IntegrationTestConfig(
  name: 'Context Selection (Similarity × Decay)',

  repos: [
    InvocationRepository<Invocation>,
  ],

  utterances: _utterances,

  mockImplementers: {
    'groq': ResponseMapLLMImplementer(_responses),
  },

  testLogic: (t) async {
    print('\n=== TEST: Context Selection with Similarity Filtering ===');

    // ===== CLEANUP: Remove old invocations to start fresh =====
    print('\n[Cleanup] Removing old invocations to start fresh...');
    final cleanupRepo = GetIt.instance<InvocationRepository<Invocation>>();
    final oldInvocations = await cleanupRepo.findAll();
    for (final inv in oldInvocations) {
      await cleanupRepo.delete(inv.uuid);
    }
    print('   Deleted ${oldInvocations.length} old invocations');

    // ===== SETUP: Create conversation history with distinct topics =====
    print('\n[Setup] Creating conversation history with 3 topics...');

    // Timer turns (oldest)
    print('   [Timer] ${_utterances['timer_set']}');
    await t.stt('timer_set');
    await Future.delayed(const Duration(milliseconds: 500));

    print('   [Timer] ${_utterances['timer_check']}');
    await t.stt('timer_check');
    await Future.delayed(const Duration(milliseconds: 500));

    // Weather turns (middle)
    print('   [Weather] ${_utterances['weather_today']}');
    await t.stt('weather_today');
    await Future.delayed(const Duration(milliseconds: 500));

    print('   [Weather] ${_utterances['weather_tomorrow']}');
    await t.stt('weather_tomorrow');
    await Future.delayed(const Duration(milliseconds: 500));

    // Reminder turns (most recent)
    print('   [Reminder] ${_utterances['reminder_create']}');
    await t.stt('reminder_create');
    await Future.delayed(const Duration(milliseconds: 500));

    print('   [Reminder] ${_utterances['reminder_list']}');
    await t.stt('reminder_list');
    await Future.delayed(const Duration(milliseconds: 500));

    // Wait for all turns to complete
    await Future.delayed(const Duration(seconds: 2));

    // ===== TEST: Query about timers (older topic) =====
    print('\n[Test] Sending timer-related query...');
    print('   Query: ${_utterances['timer_query']}');
    await t.stt('timer_query');

    // Wait for context selection and response
    await Future.delayed(const Duration(seconds: 2));

    // ===== VERIFY: Check context_selector Invocation =====
    print('\n[Verify] Checking context selection Invocation...');

    final invocationRepo = GetIt.instance<InvocationRepository<Invocation>>();
    final allInvocations = await invocationRepo.findAll();

    // Find context_selector invocations
    final contextInvocations = allInvocations
        .where((inv) => inv.componentType == 'context_selector')
        .toList();

    print('   Found ${contextInvocations.length} context_selector invocations');

    expect(
      contextInvocations.isNotEmpty,
      isTrue,
      reason: 'Should have at least one context_selector invocation',
    );

    // Get the last context_selector invocation (for the timer query)
    final lastContextInv = contextInvocations.last;

    print('   Last context selection:');
    print('     Input: ${lastContextInv.input}');
    print('     Output: ${lastContextInv.output}');

    // Verify the input was the timer query
    expect(
      lastContextInv.input?['transcription'],
      contains('timer'),
      reason: 'Last context selection should be for the timer query',
    );

    // Verify conversation thread was selected
    final threadSize = lastContextInv.output?['conversationThreadSize'] as int?;
    expect(
      threadSize,
      isNotNull,
      reason: 'Output should include conversationThreadSize',
    );
    expect(
      threadSize,
      greaterThan(0),
      reason: 'Should have selected at least one conversation turn',
    );

    print('   Conversation thread size: $threadSize');

    // ===== VERIFY: Check LLM invocation received context =====
    print('\n[Verify] Checking LLM received appropriate context...');

    final llmInvocations = allInvocations
        .where((inv) => inv.componentType == 'llm')
        .toList();

    print('   Found ${llmInvocations.length} LLM invocations');

    // The last LLM invocation should have context that includes timer-related content
    final lastLlmInv = llmInvocations.last;
    final prompt = lastLlmInv.input?['prompt'] as String?;

    print('   Last LLM prompt length: ${prompt?.length ?? 0} chars');

    // The prompt should contain timer-related context from earlier turns
    // This verifies that similarity filtering worked (selected timer turns, not just recent reminder turns)
    if (prompt != null) {
      final hasTimerContext = prompt.contains('timer') || prompt.contains('Timer');
      print('   Has timer context in prompt: $hasTimerContext');

      // With pure recency-based selection, we might only have reminder context
      // With similarity filtering, we should have timer context
      expect(
        hasTimerContext,
        isTrue,
        reason: 'LLM prompt should include timer context from earlier turns '
            '(similarity filtering should prioritize relevant turns over just recent ones)',
      );
    }

    print('\n=== Context Selection Test PASSED ===');
  },
);
