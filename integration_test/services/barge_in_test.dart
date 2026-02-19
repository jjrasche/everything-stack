/// # Barge-in Integration Test
///
/// Tests that user can interrupt TTS playback by starting to speak.
/// Verifies the execution loop's barge-in handling:
/// 1. TTS starts playing a response
/// 2. User starts speaking (start_of_turn event)
/// 3. TTS stops immediately
///
/// Note: Barge-in is NOT trainable (no parameters to learn), so no Invocation logging.
/// Pure event routing logic.
///
/// This is an AUTONOMOUS test - no manual interaction required.
/// Uses real services (no mocks) per TESTING.md philosophy.
///
/// Run with:
///   flutter test integration_test/services/barge_in_test.dart -d windows --dart-define=TEST_MODE=true

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:get_it/get_it.dart';

import 'package:everything_stack_template/core/event.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/services/tts_service.dart';
import 'package:everything_stack_template/bootstrap.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Barge-in Integration', () {
    late EventBus eventBus;
    late TTSService ttsService;

    setUpAll(() async {
      // Bootstrap the app (full services, real persistence)
      await app.initializeEverythingStack();
      await app.setupServiceLocator();

      // Get services from DI container
      final getIt = GetIt.instance;
      eventBus = getIt<EventBus>();
      ttsService = getIt<TTSService>();

      print('✅ [Test Setup] Services bootstrapped');
    });

    testWidgets('barge-in stops TTS when user starts speaking', (tester) async {
      // Pump the app to ensure it's fully initialized
      await tester.pumpAndSettle();

      print('\n=== TEST: Barge-in Integration ===');

      // ACT 1: Start TTS playback
      print('\n[1/3] Starting TTS playback...');
      final eventId = 'test_event_${DateTime.now().millisecondsSinceEpoch}';

      // Start TTS in background (don't await - simulates real async playback)
      final ttsFuture = ttsService.synthesize(
        eventId: eventId,
        text: 'This is a test response that should be interrupted by the user speaking.',
      );

      // Wait a bit for TTS to actually start playing
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pump();

      // VERIFY: TTS is playing
      expect(ttsService.isPlaying, isTrue, reason: 'TTS should be playing before barge-in');
      print('✅ TTS is playing');

      // ACT 2: Simulate user starting to speak (barge-in trigger)
      print('\n[2/3] Simulating user starts speaking (start_of_turn event)...');
      await eventBus.publish(Event(
        eventType: 'start_of_turn',
        correlationId: eventId,
        source: 'test',
        payloadJson: jsonEncode({
          'test': true,
          'reason': 'integration_test_barge_in',
        }),
      ));

      // Wait for event processing
      await Future.delayed(const Duration(milliseconds: 200));
      await tester.pump();

      // VERIFY: TTS stopped
      print('\n[3/3] Verifying TTS stopped...');
      expect(ttsService.isPlaying, isFalse, reason: 'TTS should have stopped after barge-in');
      print('✅ TTS stopped successfully');

      // Cleanup: Wait for TTS future to complete (it was interrupted)
      try {
        await ttsFuture.timeout(const Duration(seconds: 2));
      } catch (e) {
        // Expected - TTS was interrupted, may throw or complete with partial output
        print('ℹ️ TTS future completed/interrupted: $e');
      }

      print('\n=== TEST: Barge-in Integration PASSED ===\n');
    });

    testWidgets('no barge-in when TTS not playing', (tester) async {
      // ARRANGE: Ensure TTS is not playing
      await tester.pumpAndSettle();

      print('\n=== TEST: No Barge-in When Idle ===');

      expect(ttsService.isPlaying, isFalse, reason: 'TTS should not be playing initially');

      // ACT: Publish start_of_turn when TTS is idle
      print('[1/2] Publishing start_of_turn while TTS idle...');
      final eventId = 'test_idle_${DateTime.now().millisecondsSinceEpoch}';
      await eventBus.publish(Event(
        eventType: 'start_of_turn',
        correlationId: eventId,
        source: 'test',
        payloadJson: jsonEncode({'test': true}),
      ));

      await Future.delayed(const Duration(milliseconds: 200));
      await tester.pump();

      // VERIFY: TTS should still not be playing (no action taken)
      print('[2/2] Verifying TTS still idle...');
      expect(ttsService.isPlaying, isFalse, reason: 'TTS should remain idle when not playing');

      print('✅ No action taken (correct behavior)');
      print('=== TEST: No Barge-in When Idle PASSED ===\n');
    });
  });
}
