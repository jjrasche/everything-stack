/// # Conversational Flow Integration Test
///
/// Tests continuous STT with multiple sequential events.
/// Verifies:
/// - Multiple events complete successfully
/// - Audio persisted for each event
/// - Invocations logged correctly
/// - Barge-in stops TTS during playback
///
/// This is the unified test for multi-turn conversations + barge-in.
/// Replaces: barge_in_test.dart, timer_multiturn_logic.dart (multi-turn aspect)

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
import 'mocks/mock_flutter_tts_implementer.dart';

// Define utterances once - used in both test logic and mock responses
final _utterances = {
  'turn1': 'What time is it?',
  'turn2': 'Set a timer for 5 minutes',
  'turn3': 'Cancel the timer',
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
};

final conversationalFlowTest = IntegrationTestConfig(
  name: 'Conversational Flow (Multi-Event + Barge-in)',

  repos: [
    InvocationRepository<Invocation>,
  ],

  utterances: _utterances,

  mockImplementers: {
    'groq': ResponseMapLLMImplementer(_responses),
    'tts': MockFlutterTTSImplementer(),
  },

  testLogic: (t) async {
    print('\n=== TEST: Conversational Flow ===');

    final audioStorage = GetIt.instance<AudioStorage>();
    final testStartTime = DateTime.now();

    // ===== TEST 1: Three Sequential Events =====
    print('\n[Test 1] Three sequential events without manual restart');

    await t.stt('turn1');
    await Future.delayed(const Duration(milliseconds: 200)); // Let TTS complete

    await t.stt('turn2');
    await Future.delayed(const Duration(milliseconds: 200));

    await t.stt('turn3');
    await Future.delayed(const Duration(milliseconds: 500)); // Final processing

    // Verify: 3 STT invocations logged
    final invocations = await t.invocationRepo.findAll();
    final recentInvocations = invocations
        .where((i) => i.createdAt.isAfter(testStartTime))
        .toList();

    final sttInvocations = recentInvocations
        .where((i) => i.componentType == 'stt')
        .toList();

    expect(sttInvocations.length, equals(3),
        reason: 'Should have 3 STT invocations (one per event)');

    // Verify: All succeeded
    expect(sttInvocations.every((i) => i.success), isTrue,
        reason: 'All STT invocations should succeed');

    // Verify: Audio persisted for each event
    print('\n[Test 1] Verifying audio persistence');
    for (final sttInv in sttInvocations) {
      final audioId = sttInv.input?['audioId'] as String?;
      expect(audioId, isNotNull, reason: 'STT invocation should have audioId');

      final audioBytes = await audioStorage.loadAudio(audioId!);
      expect(audioBytes.length, greaterThan(0),
          reason: 'Audio should be saved for audioId: $audioId');

      print('   ✅ Audio saved: $audioId (${audioBytes.length} bytes)');
    }

    // Verify: LLM and TTS invocations also logged
    final llmInvocations = recentInvocations
        .where((i) => i.componentType == 'llm')
        .toList();
    final ttsInvocations = recentInvocations
        .where((i) => i.componentType == 'tts')
        .toList();

    expect(llmInvocations.length, greaterThanOrEqualTo(3),
        reason: 'Should have at least 3 LLM invocations');
    expect(ttsInvocations.length, greaterThanOrEqualTo(3),
        reason: 'Should have at least 3 TTS invocations');

    print('\n✅ [Test 1] Three sequential events completed successfully');

    // ===== TEST 2: Barge-in Stops TTS =====
    print('\n[Test 2] Barge-in during TTS playback');

    final eventBus = GetIt.instance<EventBus>();
    final ttsService = GetIt.instance<TTSService>();

    // Trigger a turn that will play TTS
    final bargeInEventId = 'barge_in_test_${DateTime.now().millisecondsSinceEpoch}';

    // Publish transcription_complete (will trigger orchestration → TTS)
    await eventBus.publish(Event(
      eventType: 'transcription_complete',
      correlationId: bargeInEventId,
      source: 'stt',
      payloadJson: jsonEncode({'transcript': 'Tell me a long story'}),
    ));

    // Wait for TTS to start
    await Future.delayed(const Duration(milliseconds: 500));

    // Verify TTS is playing
    expect(ttsService.isPlaying, isTrue,
        reason: 'TTS should be playing before barge-in');
    print('   🔊 TTS is playing');

    // Simulate barge-in: user starts speaking
    await eventBus.publish(Event(
      eventType: 'start_of_turn',
      correlationId: bargeInEventId,
      source: 'stt',
      payloadJson: jsonEncode({'reason': 'barge_in_test'}),
    ));

    // Wait for event processing
    await Future.delayed(const Duration(milliseconds: 200));

    // Verify: TTS stopped
    expect(ttsService.isPlaying, isFalse,
        reason: 'TTS should stop immediately on barge-in');
    print('   ✅ TTS stopped on barge-in');

    print('\n✅ [Test 2] Barge-in successfully interrupted TTS');

    print('\n=== TEST: Conversational Flow PASSED ===\n');
  },
);
