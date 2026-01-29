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
import 'shared/test_harness.dart';
import 'shared/test_context.dart';
import 'shared/response_map_implementer.dart';
import 'mocks/mock_flutter_tts_implementer.dart';

// Define utterances once - used in both test logic and mock responses
final _utterances = {
  'turn1': 'Set a timer for 5 minutes',
  'turn2': 'Make it 10 minutes instead',
  'turn3': 'Cancel the timer',
};

final _responses = {
  _utterances['turn1']!: LLMResponse(
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
  _utterances['turn2']!: LLMResponse(
    id: 'mock_2',
    content: 'Setting new 10-minute timer',
    toolCalls: [
      LLMToolCall(
        id: 'call_2',
        toolName: 'timer.set',
        params: {'duration_seconds': 600, 'label': 'Timer'},
      ),
    ],
    tokensUsed: 20,
  ),
  _utterances['turn3']!: LLMResponse(
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
};

final timerMultiturnTest = IntegrationTestConfig(
  name: 'Multi-Turn Timer Conversation',

  repos: [
    TimerRepository,
    InvocationRepository<Invocation>,
  ],

  utterances: _utterances,

  mockImplementers: {
    'groq': ResponseMapLLMImplementer(_responses),
    'tts': MockFlutterTTSImplementer(),
  },

  testLogic: (t) async {
    // Clear any leftover timers from previous test runs
    final existingTimers = await t.timerRepo.findActive();
    for (final timer in existingTimers) {
      timer.cancel();
      await t.timerRepo.save(timer);
    }

    // ===== TURN 1: Set timer for 5 minutes =====
    await t.stt('turn1');

    var timers = await t.timerRepo.findActive();
    expect(timers.length, equals(1), reason: 'Should have 1 active timer');

    var timer = timers.first;
    expect(timer.durationSeconds, equals(300), reason: 'Timer should be 5 minutes (300s)');
    expect(timer.label, isNotEmpty, reason: 'Timer should have a label');
    expect(timer.fired, isFalse);

    // ===== TURN 2: Change to 10 minutes =====
    await t.stt('turn2');

    timers = await t.timerRepo.findActive();
    expect(timers.length, equals(1), reason: 'Should have 1 active timer (old cancelled, new created)');

    timer = timers.first;
    expect(timer.durationSeconds, equals(600), reason: 'Timer should be 10 minutes (600s)');
    expect(timer.label, isNotEmpty, reason: 'Timer should have a label');

    // ===== TURN 3: Cancel timer =====
    await t.stt('turn3');

    timers = await t.timerRepo.findActive();
    expect(timers.length, equals(0), reason: 'All timers should be cancelled');

    // ===== VERIFY: Invocations recorded =====
    // Wait a bit for async TTS invocations to be persisted
    await Future.delayed(const Duration(milliseconds: 500));

    final invocations = await t.invocationRepo.findAll();
    final recent = invocations
        .where((i) => i.createdAt.isAfter(
            DateTime.now().subtract(const Duration(minutes: 2))))
        .toList();

    expect(recent.isNotEmpty, isTrue, reason: 'Should have invocations logged');

    final componentTypes = recent.map((i) => i.componentType).toSet();
    expect(componentTypes.contains('llm'), isTrue,
        reason: 'LLM should be invoked');
    expect(componentTypes.contains('tts'), isTrue,
        reason: 'TTS should be invoked');
    expect(componentTypes.contains('context_selector'), isTrue,
        reason: 'ContextSelector should be invoked');
    expect(componentTypes.contains('tool_executor'), isTrue,
        reason: 'ToolExecutor should be invoked');
  },
);
