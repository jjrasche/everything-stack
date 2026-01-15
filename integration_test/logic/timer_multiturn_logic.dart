/// # Multi-Turn Timer Conversation Test
///
/// Tests event-driven multi-turn conversation with timer tools.
/// Verifies:
/// - EventBus → Coordinator → ContextSelector → LLM → ToolExecutor → TimerRepository
/// - Multi-turn context preservation
/// - Timer persistence to database
/// - Invocation logging

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/llm_types.dart';
import 'package:everything_stack_template/tools/timer/repositories/timer_repository.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import '../shared/test_harness.dart';
import '../shared/test_context.dart';

final timerMultiturnTest = IntegrationTestConfig(
  name: 'Multi-Turn Timer Conversation',

  repos: [
    TimerRepository,
    InvocationRepository<Invocation>,
  ],

  utterances: {
    'turn1': 'Set a timer for 5 minutes',
    'turn2': 'Make it 10 minutes instead',
    'turn3': 'Cancel the timer',
  },

  mockResponses: {
    'groq': {
      'Set a timer for 5 minutes': LLMResponse(
        id: 'mock_1',
        content: 'Setting a 5-minute timer',
        toolCalls: [
          LLMToolCall(
            id: 'call_1',
            toolName: 'timer.set',
            params: {'duration_seconds': 300, 'label': 'Timer'},
          ),
        ],
        tokensUsed: 20,
      ),
      'Make it 10 minutes instead': LLMResponse(
        id: 'mock_2',
        content: 'Cancelling old timer and setting new 10-minute timer',
        toolCalls: [
          LLMToolCall(
            id: 'call_2a',
            toolName: 'timer.cancel',
            params: {},
          ),
          LLMToolCall(
            id: 'call_2b',
            toolName: 'timer.set',
            params: {'duration_seconds': 600, 'label': 'Timer'},
          ),
        ],
        tokensUsed: 25,
      ),
      'Cancel the timer': LLMResponse(
        id: 'mock_3',
        content: 'Cancelling timer',
        toolCalls: [
          LLMToolCall(
            id: 'call_3',
            toolName: 'timer.cancel',
            params: {},
          ),
        ],
        tokensUsed: 15,
      ),
    },
    'tts': {}, // Empty map - TTS doesn't use LLM responses, but we need it registered
  },

  testLogic: (t) async {
    print('\n🧪 [Timer Multiturn] Starting 3-turn test...');

    // Clear any leftover timers from previous test runs
    final existingTimers = await t.timerRepo.findActive();
    for (final timer in existingTimers) {
      timer.cancel();
      await t.timerRepo.save(timer);
    }
    print('🧹 Cleared ${existingTimers.length} existing timers');

    // ===== TURN 1: Set timer for 5 minutes =====
    print('\n📢 TURN 1: Set a timer for 5 minutes');
    await t.stt('turn1');

    var timers = await t.timerRepo.findActive();
    print('📋 Active timers: ${timers.length}');
    expect(timers.length, equals(1), reason: 'Should have 1 active timer');

    var timer = timers.first;
    print('   Duration: ${timer.durationSeconds}s');
    print('   Label: ${timer.label}');
    expect(timer.durationSeconds, equals(300), reason: 'Timer should be 5 minutes (300s)');
    expect(timer.label, equals('Timer'));
    expect(timer.fired, isFalse);
    print('✅ Turn 1 passed: Timer created with 300s duration');

    // ===== TURN 2: Change to 10 minutes =====
    print('\n📢 TURN 2: Make it 10 minutes instead');
    await t.stt('turn2');

    timers = await t.timerRepo.findActive();
    print('📋 Active timers: ${timers.length}');
    expect(timers.length, equals(1), reason: 'Should have 1 active timer (old cancelled, new created)');

    timer = timers.first;
    print('   Duration: ${timer.durationSeconds}s');
    print('   Label: ${timer.label}');
    expect(timer.durationSeconds, equals(600), reason: 'Timer should be 10 minutes (600s)');
    expect(timer.label, equals('Timer'));
    print('✅ Turn 2 passed: Timer updated to 600s');

    // ===== TURN 3: Cancel timer =====
    print('\n📢 TURN 3: Cancel the timer');
    await t.stt('turn3');

    timers = await t.timerRepo.findActive();
    print('📋 Active timers: ${timers.length}');
    expect(timers.length, equals(0), reason: 'All timers should be cancelled');
    print('✅ Turn 3 passed: All timers cancelled');

    // ===== VERIFY: Invocations recorded =====
    print('\n📊 VERIFY: Invocations logged to database');
    final invocations = await t.invocationRepo.findAll();
    final recent = invocations
        .where((i) => i.createdAt.isAfter(
            DateTime.now().subtract(const Duration(minutes: 2))))
        .toList();

    print('   Recent invocations: ${recent.length}');
    expect(recent.isNotEmpty, isTrue, reason: 'Should have invocations logged');

    final componentTypes = recent.map((i) => i.componentType).toSet();
    print('   Components: ${componentTypes.join(", ")}');
    // Verify all components are logging invocations via Trainable pattern
    expect(componentTypes.contains('llm'), isTrue,
        reason: 'LLM should be invoked');
    expect(componentTypes.contains('tts'), isTrue,
        reason: 'TTS should be invoked');
    expect(componentTypes.contains('context_selector'), isTrue,
        reason: 'ContextSelector should be invoked');
    expect(componentTypes.contains('tool_executor'), isTrue,
        reason: 'ToolExecutor should be invoked');

    print('\n🎉 Timer multiturn test PASSED');
    print('   - Event-driven flow: ✅');
    print('   - Multi-turn context: ✅');
    print('   - Timer persistence: ✅');
    print('   - Invocation logging: ✅');
  },
);
