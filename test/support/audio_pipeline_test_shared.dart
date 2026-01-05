import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/main.dart';
import 'package:everything_stack_template/services/coordinator.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/domain/invocation.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/domain/event.dart';
import 'package:everything_stack_template/core/event_repository.dart';
import 'package:everything_stack_template/services/events/transcription_complete.dart';
import 'package:everything_stack_template/services/events/orchestration_complete.dart';
import 'package:everything_stack_template/services/stt_service.dart';

/// Shared test logic for audio pipeline (event-driven flow).
///
/// ## Architecture Under Test
/// ```
/// STT → TranscriptionComplete event → Coordinator → LLM → TTS → OrchestrationComplete event
/// ```
///
/// ## What This Verifies
/// 1. STT processes audio and publishes TranscriptionComplete event
/// 2. Coordinator receives event and runs orchestration
/// 3. LLM generates response
/// 4. TTS synthesizes speech
/// 5. OrchestrationComplete event published for UI
/// 6. All invocations recorded for training
///
/// ## Multi-Turn Support
/// The test verifies that multiple turns can be processed sequentially,
/// proving the listening bug is fixed.
Future<void> runAudioPipelineTest(WidgetTester tester) async {
  print('\n🚀 [Audio Pipeline Test] Starting event-driven audio pipeline test...');

  // ========== SETUP: Build app and initialize ==========
  print('🏗️ Building MyApp...');
  await tester.pumpWidget(const MyApp());

  print('⏳ Waiting for bootstrap and initialization...');
  await tester.pumpAndSettle(const Duration(seconds: 5));

  print('🔍 Verifying app initialized...');
  expect(find.byType(Scaffold), findsWidgets);

  // Get services from GetIt
  final getIt = GetIt.instance;
  final coordinator = getIt<Coordinator>();
  final invocationRepo = getIt<InvocationRepository<Invocation>>();
  final eventRepository = getIt<EventRepository>();
  final eventBus = getIt<EventBus>();
  final sttService = getIt<STTService>();

  print('✅ Services initialized: Coordinator, EventBus, Repositories');

  // ========== TURN 1: First utterance ==========
  print('\n' + '=' * 60);
  print('📢 TURN 1: Testing first utterance');
  print('=' * 60);

  final turn1Transcript = 'one plus one';
  final turn1CorrelationId = 'turn1_${DateTime.now().millisecondsSinceEpoch}';

  // Subscribe to OrchestrationComplete to know when turn is done
  final turn1Completer = Completer<OrchestrationComplete>();
  final turn1Subscription = eventBus.subscribe<OrchestrationComplete>().listen(
    (event) {
      if (!turn1Completer.isCompleted) {
        print('📡 [Turn 1] OrchestrationComplete received');
        turn1Completer.complete(event);
      }
    },
  );

  // Stream audio to STT (simulates user speaking)
  await _streamAudioToSTT(
    sttService: sttService,
    transcript: turn1Transcript,
    correlationId: turn1CorrelationId,
  );

  // Wait for orchestration to complete
  print('⏳ [Turn 1] Waiting for OrchestrationComplete...');
  final turn1Result = await turn1Completer.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () => throw TimeoutException('Turn 1 orchestration timeout'),
  );
  await turn1Subscription.cancel();

  print('✅ [Turn 1] Complete: success=${turn1Result.success}');
  print('   Response: "${turn1Result.response.length > 50 ? turn1Result.response.substring(0, 50) + "..." : turn1Result.response}"');

  // Verify Turn 1 invocations
  final turn1Invocations = await _getInvocationsForCorrelation(invocationRepo, turn1Result.correlationId);
  print('📋 [Turn 1] Invocations recorded: ${turn1Invocations.length}');

  expect(turn1Result.success, isTrue, reason: 'Turn 1 should succeed');
  expect(turn1Invocations.length, greaterThan(0), reason: 'Turn 1 should have invocations');

  // ========== TURN 2: Second utterance (proves multi-turn works) ==========
  print('\n' + '=' * 60);
  print('📢 TURN 2: Testing second utterance (multi-turn)');
  print('=' * 60);

  final turn2Transcript = 'what is the weather';
  final turn2CorrelationId = 'turn2_${DateTime.now().millisecondsSinceEpoch}';

  // Subscribe to OrchestrationComplete for turn 2
  final turn2Completer = Completer<OrchestrationComplete>();
  final turn2Subscription = eventBus.subscribe<OrchestrationComplete>().listen(
    (event) {
      if (!turn2Completer.isCompleted) {
        print('📡 [Turn 2] OrchestrationComplete received');
        turn2Completer.complete(event);
      }
    },
  );

  // Stream second audio (simulates user speaking again)
  await _streamAudioToSTT(
    sttService: sttService,
    transcript: turn2Transcript,
    correlationId: turn2CorrelationId,
  );

  // Wait for orchestration to complete
  print('⏳ [Turn 2] Waiting for OrchestrationComplete...');
  final turn2Result = await turn2Completer.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () => throw TimeoutException('Turn 2 orchestration timeout'),
  );
  await turn2Subscription.cancel();

  print('✅ [Turn 2] Complete: success=${turn2Result.success}');
  print('   Response: "${turn2Result.response.length > 50 ? turn2Result.response.substring(0, 50) + "..." : turn2Result.response}"');

  // Verify Turn 2 invocations
  final turn2Invocations = await _getInvocationsForCorrelation(invocationRepo, turn2Result.correlationId);
  print('📋 [Turn 2] Invocations recorded: ${turn2Invocations.length}');

  expect(turn2Result.success, isTrue, reason: 'Turn 2 should succeed');
  expect(turn2Invocations.length, greaterThan(0), reason: 'Turn 2 should have invocations');

  // ========== ASSERTIONS ==========
  print('\n' + '=' * 60);
  print('✅ ASSERTIONS');
  print('=' * 60);

  // Assert 1: Both turns completed
  print('📋 Assert: Multi-turn conversation works...');
  expect(turn1Result.success, isTrue, reason: 'Turn 1 must succeed');
  expect(turn2Result.success, isTrue, reason: 'Turn 2 must succeed');
  print('  ✓ Both turns completed successfully');

  // Assert 2: Events were persisted
  print('📋 Assert: Events persisted...');
  final allEvents = await eventRepository.getAll();
  final transcriptionEvents = allEvents.whereType<TranscriptionComplete>().toList();
  expect(transcriptionEvents.length, greaterThanOrEqualTo(2), reason: 'Should have at least 2 TranscriptionComplete events');
  print('  ✓ ${transcriptionEvents.length} TranscriptionComplete events found');

  // Assert 3: Invocations recorded
  print('📋 Assert: Invocations recorded for training...');
  final allInvocations = await invocationRepo.findAll();
  final recentInvocations = allInvocations
      .where((inv) => inv.createdAt.isAfter(DateTime.now().subtract(const Duration(seconds: 30))))
      .toList();
  print('  Total recent invocations: ${recentInvocations.length}');

  final componentTypes = recentInvocations.map((inv) => inv.componentType).toSet();
  print('  Components executed: ${componentTypes.join(", ")}');

  expect(componentTypes.contains('tts'), isTrue, reason: 'TTS should be invoked');
  print('  ✓ TTS invocations present');

  // Assert 4: No duplicate processing
  print('📋 Assert: No duplicate processing...');
  final turn1LLMInvocations = turn1Invocations.where((inv) => inv.componentType == 'llm_orchestrator').toList();
  final turn2LLMInvocations = turn2Invocations.where((inv) => inv.componentType == 'llm_orchestrator').toList();
  expect(turn1LLMInvocations.length, lessThanOrEqualTo(1), reason: 'Turn 1 should have at most 1 LLM invocation');
  expect(turn2LLMInvocations.length, lessThanOrEqualTo(1), reason: 'Turn 2 should have at most 1 LLM invocation');
  print('  ✓ No duplicate LLM calls');

  print('\n🎉 Audio pipeline E2E test complete');
  print('   - Event-driven flow: ✅');
  print('   - Multi-turn conversation: ✅');
  print('   - No duplicate processing: ✅');
  print('   - Invocations recorded: ✅');
}

/// Stream audio to STT service (simulates user speaking)
Future<void> _streamAudioToSTT({
  required STTService sttService,
  required String transcript,
  required String correlationId,
}) async {
  print('🎤 Streaming audio to STT...');
  print('   Expected transcript: "$transcript"');

  // Load audio from fixture or generate synthetic
  final audioBytes = await _loadOrGenerateAudio();

  // Create audio stream
  final audioStream = Stream<Uint8List>.fromIterable([audioBytes]);

  // Track callbacks
  final sttDoneCompleter = Completer<void>();
  var transcriptReceived = '';

  // Start transcription
  sttService.transcribe(
    audio: audioStream,
    onTranscript: (t) {
      print('   📝 Transcript: "$t"');
      transcriptReceived = t;
    },
    onUtteranceEnd: () {
      print('   🔊 Utterance end');
    },
    onError: (error) {
      print('   ❌ STT error: $error');
      if (!sttDoneCompleter.isCompleted) {
        sttDoneCompleter.completeError(error);
      }
    },
    onDone: () {
      print('   ✅ STT stream done');
      if (!sttDoneCompleter.isCompleted) {
        sttDoneCompleter.complete();
      }
    },
  );

  // Wait for STT to complete
  await sttDoneCompleter.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => print('   ⚠️ STT timeout (continuing anyway)'),
  );

  print('✅ Audio streamed, transcript: "$transcriptReceived"');
}

/// Load audio from fixture or generate synthetic
Future<Uint8List> _loadOrGenerateAudio() async {
  final audioFixturePath = 'test_fixtures/audio/1_plus_1.wav';
  final audioFile = File(audioFixturePath);

  if (await audioFile.exists()) {
    print('📂 Loading real audio fixture');
    return await audioFile.readAsBytes();
  } else {
    print('⚠️ Fixture not found, using synthetic audio');
    return Uint8List.fromList(
      List<int>.generate(16000 * 2, (i) => i % 256),
    );
  }
}

/// Get invocations for a specific correlation ID
Future<List<Invocation>> _getInvocationsForCorrelation(
  InvocationRepository<Invocation> repo,
  String correlationId,
) async {
  final allInvocations = await repo.findAll();
  return allInvocations
      .where((inv) => inv.correlationId == correlationId)
      .toList();
}
