/// # Conversational Flow Integration Test
///
/// Tests multi-event conversational flow through the pipeline.
/// Verifies:
/// - Multiple events complete successfully (3 sequential turns)
/// - Coordinator → LLM → TTS pipeline works for each event
/// - Invocations logged correctly for each component
/// - Barge-in stops TTS during playback (REAL FlutterTtsImplementer)
///
/// Note: This test uses mock transcriptions (t.stt() publishes transcription_complete events)
/// and mock LLM responses, but uses REAL FlutterTtsImplementer to test barge-in logic.
/// For STT-specific testing (including audio persistence), see microphone_stt_logic.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/llm_types.dart';
import 'package:everything_stack_template/services/tts_service.dart';
import 'package:everything_stack_template/services/audio_storage.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/event.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:get_it/get_it.dart';
import 'dart:convert';
import 'dart:async';
import 'shared/test_harness.dart';
import 'shared/test_context.dart';
import 'shared/response_map_implementer.dart';

// Define utterances once - used in both test logic and mock responses
final _utterances = {
  'turn1': 'What time is it?',
  'turn2': 'Set a timer for 5 minutes',
  'turn3': 'Cancel the timer',
  'long_story': 'Tell me a long story',
};

final _responses = {
  _utterances['turn1']!: LLMResponse(
    id: 'mock_1',
    content: 'It is 3:45 PM',
    toolCalls: [],
    tokensUsed: 15,
  ),
  _utterances['turn2']!: LLMResponse(
    id: 'mock_2',
    content: 'Setting a 5-minute timer',
    toolCalls: [],
    tokensUsed: 20,
  ),
  _utterances['turn3']!: LLMResponse(
    id: 'mock_3',
    content: 'Timer cancelled',
    toolCalls: [],
    tokensUsed: 10,
  ),
  _utterances['long_story']!: LLMResponse(
    id: 'mock_4',
    content: 'Once upon a time, in a land far away, there lived a brave knight who embarked on an epic quest to find the legendary sword of truth.',
    toolCalls: [],
    tokensUsed: 30,
  ),
};

final conversationalFlowTest = IntegrationTestConfig(
  name: 'Conversational Flow (Multi-Event + Barge-in)',

  repos: [
    InvocationRepository<Invocation>,
  ],

  utterances: _utterances,

  mockImplementers: {
    'groq': ResponseMapLLMImplementer(_responses),
    // Use real FlutterTtsImplementer for barge-in testing
  },

  testLogic: (t) async {
    print('\n=== TEST: Conversational Flow ===');

    final testStartTime = DateTime.now();

    // ===== TEST 1: Three Sequential Events =====
    print('\n[Test 1] Three sequential events without manual restart');

    await t.stt('turn1');
    await Future.delayed(const Duration(milliseconds: 200)); // Let TTS complete

    await t.stt('turn2');
    await Future.delayed(const Duration(milliseconds: 200));

    await t.stt('turn3');
    await Future.delayed(const Duration(milliseconds: 500)); // Final processing

    // Verify: Pipeline invocations logged (LLM and TTS for each event)
    final invocations = await t.invocationRepo.findAll();
    final recentInvocations = invocations
        .where((i) => i.createdAt.isAfter(testStartTime))
        .toList();

    final llmInvocations = recentInvocations
        .where((i) => i.componentType == 'llm')
        .toList();
    final ttsInvocations = recentInvocations
        .where((i) => i.componentType == 'tts')
        .toList();

    print('\n[Test 1] Verifying pipeline invocations:');
    print('   📊 LLM invocations: ${llmInvocations.length}');
    print('   🔊 TTS invocations: ${ttsInvocations.length}');

    // Expect at least 3 LLM invocations (one per event, possibly more due to tool calls)
    expect(llmInvocations.length, greaterThanOrEqualTo(3),
        reason: 'Should have at least 3 LLM invocations (one per event)');

    // Expect at least 3 TTS invocations (one per event)
    expect(ttsInvocations.length, greaterThanOrEqualTo(3),
        reason: 'Should have at least 3 TTS invocations (one per event)');

    // Verify: All LLM invocations succeeded
    final llmSuccesses = llmInvocations.where((i) => i.success).length;
    expect(llmSuccesses, equals(llmInvocations.length),
        reason: 'All LLM invocations should succeed');

    print('\n✅ [Test 1] Three sequential events completed successfully');

    // ===== TEST 2: Barge-in Stops TTS =====
    print('\n[Test 2] Barge-in during TTS playback');

    final eventBus = GetIt.instance<EventBus>();
    final ttsService = GetIt.instance<TTSService>();

    // Create correlation ID for this test
    final bargeInEventId = 'barge_in_${DateTime.now().millisecondsSinceEpoch}';

    // Trigger a turn with long response (so TTS has time to start)
    await eventBus.publish(Event(
      eventType: 'transcription_complete',
      correlationId: bargeInEventId,
      source: 'stt',
      payloadJson: jsonEncode({'transcript': _utterances['long_story']}),
    ));

    // Wait for TTS to start (Coordinator → LLM → TTS pipeline)
    await Future.delayed(const Duration(milliseconds: 800));

    // Verify TTS is actually playing
    expect(ttsService.isPlaying, isTrue,
        reason: 'TTS should be playing before barge-in');
    print('   🔊 TTS is playing (real FlutterTtsImplementer)');

    // Simulate barge-in: user starts speaking
    await eventBus.publish(Event(
      eventType: 'start_of_turn',
      correlationId: bargeInEventId,
      source: 'stt',
      payloadJson: jsonEncode({'reason': 'user_interrupted'}),
    ));

    // Wait for event processing and stop to complete
    await Future.delayed(const Duration(milliseconds: 200));

    // Verify: TTS stopped (real stop() called on real implementer)
    expect(ttsService.isPlaying, isFalse,
        reason: 'TTS should stop immediately on barge-in');
    print('   ✅ TTS stopped on barge-in (real event handling verified)');

    print('\n✅ [Test 2] Barge-in successfully interrupted TTS');

    print('\n=== TEST: Conversational Flow PASSED ===\n');
  },
);
