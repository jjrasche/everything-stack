import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/core/event.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/tools/timer/repositories/timer_repository.dart';
import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';

/// Multi-turn timer conversation test (event-driven pattern).
///
/// ## Architecture Under Test
/// ```
/// Event → EventBus → Coordinator listener → orchestrate() → ContextSelector → LLM → ToolExecutor → TimerRepository
/// ```
///
/// ## What This Verifies
/// 1. EventBus: event publishing and subscription
/// 2. Coordinator: event-driven orchestration (listener pattern)
/// 3. ContextSelector: multi-turn context with conversation history
/// 4. ToolExecutor: timer.set, timer.cancel execution
/// 5. TimerRepository: persistence and state changes
///
/// ## Scenario
/// Turn 1: "Set a timer for 5 minutes" → timer created (300s)
/// Turn 2: "Make it 10 minutes instead" → old timer cancelled, new timer created (600s)
/// Turn 3: "Cancel the timer" → all timers cancelled
Future<void> runTimerConversationTest() async {
  print('\n🚀 [Timer Conversation Test] Starting event-driven multi-turn test...');

  final getIt = GetIt.instance;
  final eventBus = getIt<EventBus>();
  final timerRepo = getIt<TimerRepository>();
  final invocationRepo = getIt<EntityRepository<Invocation>>();

  print('✅ Services initialized (all REAL internal logic)');

  // ========== TURN 1: "Set a timer for 5 minutes" ==========
  print('\n' + '=' * 60);
  print('📢 TURN 1: Set a timer for 5 minutes');
  print('=' * 60);

  final turn1CorrelationId = 'timer_turn1_${DateTime.now().millisecondsSinceEpoch}';
  final turn1Event = Event(
    eventType: 'transcription_complete',
    correlationId: turn1CorrelationId,
    source: 'stt',
    payloadJson: jsonEncode({
      'transcript': 'Set a timer for 5 minutes',
      'confidence': 0.95,
    }),
  );

  print('📤 Publishing event to EventBus...');
  await eventBus.publish(turn1Event);

  // Wait for Coordinator listener to process event
  print('⏳ Waiting for Coordinator to process event...');
  await Future.delayed(const Duration(seconds: 2));

  // Verify event was published
  final turn1Events = eventBus.getEventsByCorrelationId(turn1CorrelationId);
  expect(turn1Events.isNotEmpty, isTrue, reason: 'Event should be published to EventBus');
  print('✅ Event published: ${turn1Events.length} events with correlationId');

  // Verify timer was created and persisted
  final timersAfterTurn1 = await timerRepo.findActive();
  print('📋 Active timers after Turn 1: ${timersAfterTurn1.length}');

  expect(timersAfterTurn1.length, equals(1), reason: 'Should have 1 active timer');

  final timer1 = timersAfterTurn1.first;
  print('   Duration: ${timer1.durationSeconds}s');
  print('   Label: ${timer1.label}');
  print('   Fired: ${timer1.fired}');

  expect(timer1.durationSeconds, equals(300), reason: 'Timer should be 5 minutes (300s)');
  expect(timer1.label, equals('Timer'));
  expect(timer1.fired, isFalse);

  print('✅ Turn 1 complete: Timer created and persisted');

  // ========== TURN 2: "Make it 10 minutes instead" ==========
  print('\n' + '=' * 60);
  print('📢 TURN 2: Make it 10 minutes instead');
  print('=' * 60);

  final turn2CorrelationId = 'timer_turn2_${DateTime.now().millisecondsSinceEpoch}';
  final turn2Event = Event(
    eventType: 'transcription_complete',
    correlationId: turn2CorrelationId,
    source: 'stt',
    payloadJson: jsonEncode({
      'transcript': 'Make it 10 minutes instead',
      'confidence': 0.95,
    }),
  );

  print('📤 Publishing event to EventBus...');
  await eventBus.publish(turn2Event);

  print('⏳ Waiting for Coordinator to process event...');
  await Future.delayed(const Duration(seconds: 2));

  final turn2Events = eventBus.getEventsByCorrelationId(turn2CorrelationId);
  expect(turn2Events.isNotEmpty, isTrue, reason: 'Event should be published to EventBus');
  print('✅ Event published: ${turn2Events.length} events with correlationId');

  // Verify old timer cancelled, new timer created
  final timersAfterTurn2 = await timerRepo.findActive();
  print('📋 Active timers after Turn 2: ${timersAfterTurn2.length}');

  expect(timersAfterTurn2.length, equals(1), reason: 'Should have 1 active timer (old cancelled, new created)');

  final timer2 = timersAfterTurn2.first;
  print('   Duration: ${timer2.durationSeconds}s');
  print('   Label: ${timer2.label}');

  expect(timer2.durationSeconds, equals(600), reason: 'Timer should be 10 minutes (600s)');
  expect(timer2.label, equals('Timer'));

  print('✅ Turn 2 complete: Timer updated');

  // ========== TURN 3: "Cancel the timer" ==========
  print('\n' + '=' * 60);
  print('📢 TURN 3: Cancel the timer');
  print('=' * 60);

  final turn3CorrelationId = 'timer_turn3_${DateTime.now().millisecondsSinceEpoch}';
  final turn3Event = Event(
    eventType: 'transcription_complete',
    correlationId: turn3CorrelationId,
    source: 'stt',
    payloadJson: jsonEncode({
      'transcript': 'Cancel the timer',
      'confidence': 0.95,
    }),
  );

  print('📤 Publishing event to EventBus...');
  await eventBus.publish(turn3Event);

  print('⏳ Waiting for Coordinator to process event...');
  await Future.delayed(const Duration(seconds: 2));

  final turn3Events = eventBus.getEventsByCorrelationId(turn3CorrelationId);
  expect(turn3Events.isNotEmpty, isTrue, reason: 'Event should be published to EventBus');
  print('✅ Event published: ${turn3Events.length} events with correlationId');

  // Verify all timers cancelled
  final timersAfterTurn3 = await timerRepo.findActive();
  print('📋 Active timers after Turn 3: ${timersAfterTurn3.length}');

  expect(timersAfterTurn3.length, equals(0), reason: 'All timers should be cancelled');

  print('✅ Turn 3 complete: All timers cancelled');

  // ========== FINAL VERIFICATION ==========
  print('\n' + '=' * 60);
  print('✅ FINAL VERIFICATION');
  print('=' * 60);

  // Verify invocations were recorded for training
  final allInvocations = await invocationRepo.findAll();
  final recentInvocations = allInvocations
      .where((inv) => inv.createdAt.isAfter(DateTime.now().subtract(const Duration(minutes: 2))))
      .toList();

  print('📊 Recent invocations: ${recentInvocations.length}');

  final componentTypes = recentInvocations.map((inv) => inv.componentType).toSet();
  print('   Components: ${componentTypes.join(", ")}');

  expect(componentTypes.contains('tool_executor'), isTrue, reason: 'ToolExecutor should be invoked');
  expect(componentTypes.contains('context_selector'), isTrue, reason: 'ContextSelector should be invoked');

  // Verify final timer state
  final finalActiveTimers = await timerRepo.findActive();
  final allTimers = await timerRepo.findAll();

  print('📊 Final timer state:');
  print('   Active timers: ${finalActiveTimers.length}');
  print('   Total timers ever created: ${allTimers.length}');

  print('\n🎉 Multi-turn timer test PASSED');
  print('   - Event-driven architecture: ✅');
  print('   - EventBus publishing: ✅');
  print('   - Coordinator listener: ✅');
  print('   - ContextSelector multi-turn context: ✅');
  print('   - ToolExecutor execution: ✅');
  print('   - TimerRepository persistence: ✅');
}
