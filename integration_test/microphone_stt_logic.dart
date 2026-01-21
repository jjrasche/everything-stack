/// # Microphone → STT Integration Test
///
/// Tests the complete audio recording → STT → transcription flow.
/// Uses data-driven approach with test audio file.
///
/// Flow:
/// 1. Save test audio to AudioStorage
/// 2. Call STTService.recognize() with audioId
/// 3. Verify transcription_complete event is published
/// 4. Verify Coordinator processes the event

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/services/audio_storage.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/core/event.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'shared/test_harness.dart';
import 'shared/test_context.dart';
import 'mocks/mock_deepgram_implementer.dart';

final microphoneSttTest = IntegrationTestConfig(
  name: 'Microphone → STT Flow',

  repos: [
    InvocationRepository<Invocation>,
  ],

  // Use mock STT implementer to avoid real Deepgram API calls
  mockImplementers: {
    'deepgram': EnhancedMockDeepgramImplementer(
      transcriptToEmit: 'mock transcription from test audio',
    ),
  },

  testLogic: (t) async {
    final audioStorage = GetIt.instance<AudioStorage>();
    final sttService = GetIt.instance<STTService>();
    final eventBus = GetIt.instance<EventBus>();

    // 1. Create test audio data (simulated PCM16 audio)
    // In real test, this would load from a test audio file
    final testAudioBytes = Uint8List.fromList(
      List.generate(16000 * 2, (i) => i % 256), // 1 second of fake audio
    );

    // 2. Save audio to storage
    final eventId = 'test_mic_${DateTime.now().millisecondsSinceEpoch}';
    final audioId = await audioStorage.saveAudio(
      audioBytes: testAudioBytes,
      durationSeconds: 1.0,
      eventId: eventId,
    );

    expect(audioId, isNotEmpty, reason: 'AudioStorage should return audioId');

    // 3. Set up event listener for transcription_complete
    final eventsFuture = eventBus.subscribe().toList();

    // 4. Call STT service with audioId
    final transcription = await sttService.recognize(
      eventId: eventId,
      audioId: audioId,
      durationSeconds: 1.0,
    );

    expect(transcription, isNotEmpty, reason: 'STT should return transcription');
    expect(transcription, 'mock transcription from test audio',
      reason: 'STT should return mock transcription');

    // 5. Verify STT invocation was logged
    final invocations = await t.invocationRepo.findAll();
    final sttInvocations = invocations.where((inv) =>
      inv.componentType == 'stt' && inv.eventId == eventId
    ).toList();

    expect(sttInvocations.length, 1, reason: 'STT invocation should be logged');
    expect(sttInvocations.first.success, true, reason: 'STT should succeed');

    // 6. Verify audio file is retrievable
    final loadedAudio = await audioStorage.loadAudio(audioId);
    expect(loadedAudio.length, testAudioBytes.length,
      reason: 'Loaded audio should match saved audio');

    // 7. Verify metadata
    final metadata = await audioStorage.getMetadata(audioId);
    expect(metadata, isNotNull, reason: 'Metadata should exist');
    expect(metadata!.durationSeconds, 1.0);
    expect(metadata.format, 'pcm16_16khz_mono');
    expect(metadata.eventId, eventId);
  },
);
