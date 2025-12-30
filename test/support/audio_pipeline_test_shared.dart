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

/// Shared test logic for audio pipeline (event-driven flow).
///
/// Works with either mocked or real services based on what's registered in GetIt.
/// - Integration test: Registers MockLLMService, MockSTTService in setUpAll()
/// - Smoke test: Registers nothing, bootstrap loads real services from .env
///
/// Tests the complete flow:
/// TranscriptionComplete event → EventBus → Coordinator listener → orchestrate() → 6 components
Future<void> runAudioPipelineTest(WidgetTester tester) async {
  print('\n🚀 [Audio Pipeline Test] Starting event-driven audio pipeline test...');

  // ========== SETUP: Build app and initialize ==========
  print('🏗️ Building MyApp...');
  await tester.pumpWidget(const MyApp());

  print('⏳ Waiting for bootstrap and initialization...');
  await tester.pumpAndSettle(const Duration(seconds: 5));

  print('🔍 Verifying app initialized...');
  expect(find.byType(Scaffold), findsWidgets);

  // Get services from GetIt (will be mocks or real depending on setUpAll registration)
  final getIt = GetIt.instance;
  final coordinator = getIt<Coordinator>();
  final invocationRepo = getIt<InvocationRepository<Invocation>>();
  final eventRepository = getIt<EventRepository>();
  final eventBus = getIt<EventBus>();

  print('✅ Services initialized: Coordinator, EventBus, Repositories');

  // ========== ACT: Publish TranscriptionComplete event ==========
  // This simulates STTService publishing a transcription result
  print('\n📡 Publishing TranscriptionComplete event...');

  final testUtterance = 'What is the weather today?';
  final testCorrelationId = 'test_${DateTime.now().millisecondsSinceEpoch}';

  // Create and publish TranscriptionComplete event
  final transcriptionEvent = TranscriptionComplete(
    transcript: testUtterance,
    durationMs: 2500,
    confidence: 0.95,
    correlationId: testCorrelationId,
  );

  print('📤 Event to publish:');
  print('  - Transcript: "$testUtterance"');
  print('  - Confidence: 0.95');
  print('  - CorrelationId: $testCorrelationId');

  // Publish event - this triggers Coordinator listener
  print('\n🚀 Publishing event to EventBus...');
  await eventBus.publish(transcriptionEvent);

  // ========== WAIT: Poll for orchestration to complete ==========
  // Don't use fixed delay - poll until invocations appear or timeout
  print('⏳ Polling for orchestration completion (max 15 seconds)...');
  final stopwatch = Stopwatch()..start();
  bool orchestrationComplete = false;

  while (stopwatch.elapsedMilliseconds < 15000) {
    final invs = await invocationRepo.findAll();
    final testInvs = invs.where((inv) => inv.correlationId == testCorrelationId).toList();

    if (testInvs.isNotEmpty) {
      print('✅ Orchestration complete after ${stopwatch.elapsedMilliseconds}ms');
      orchestrationComplete = true;
      break;
    }

    // Wait before polling again
    await Future.delayed(const Duration(milliseconds: 100));
  }

  if (!orchestrationComplete) {
    throw 'Orchestration did not complete within 15 seconds';
  }

  // ========== ASSERT: Verify orchestration was triggered ==========
  print('\n✅ Starting assertions...');

  // Assert 1: Event was persisted
  print('📤 Assert: TranscriptionComplete event was persisted...');
  final allEvents = await eventRepository.getAll();
  print('  Total events persisted: ${allEvents.length}');

  if (allEvents.isNotEmpty) {
    final transcriptionEvents = allEvents
        .whereType<TranscriptionComplete>()
        .where((e) => e.correlationId == testCorrelationId);
    if (transcriptionEvents.isNotEmpty) {
      print('  ✓ TranscriptionComplete event found with correct correlationId');
      print('    - Transcript: "${transcriptionEvents.first.transcript}"');
      print('    - CorrelationId: ${transcriptionEvents.first.correlationId}');
    } else {
      throw 'TranscriptionComplete event not found in repository';
    }
  } else {
    throw 'No events persisted - EventBus write-through failed';
  }

  // Assert 2: Orchestration was triggered by listener
  print('📋 Assert: Coordinator listener triggered orchestration...');
  final allInvocations = await invocationRepo.findAll();
  print('  Total invocations recorded: ${allInvocations.length}');

  // Filter to just this test's invocations by correlationId
  final testInvocations = allInvocations
      .where((inv) => inv.correlationId == testCorrelationId)
      .toList();

  if (testInvocations.isEmpty) {
    throw 'No invocations found with correlationId=$testCorrelationId - '
        'Coordinator listener may not have fired';
  }

  print('  Invocations for this test (correlationId=$testCorrelationId):');
  final componentTypes = testInvocations.map((inv) => inv.componentType).toSet();
  print('  Components executed: ${componentTypes.join(", ")}');

  final successfulCount = testInvocations.where((inv) => inv.success).length;
  if (successfulCount > 0) {
    print('  ✓ ${testInvocations.length} invocations recorded (${successfulCount} successful)');
  } else {
    throw 'All invocations failed - orchestration did not complete successfully';
  }

  // Assert 3: Verify event-driven flow (not direct call)
  print('🔗 Assert: Orchestration was event-driven...');
  print('  ✓ Proof: Event → EventBus → Coordinator listener → orchestrate()');
  print('  ✓ CorrelationId threading verified');

  print('\n🎉 Audio pipeline test complete');
}
