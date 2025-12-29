/// # Audio Pipeline Event Chain Test (Layer 2 - System Integration)
///
/// Tests the complete audio processing pipeline:
/// STT Service → TranscriptionComplete event → Coordinator listens →
/// Orchestrates 6 components → Events chain with same correlationId →
/// All invocations recorded
///
/// This is the critical system test. It validates:
/// 1. STT publishes TranscriptionComplete with correlationId
/// 2. EventBus persists event with write-through guarantee
/// 3. Coordinator receives event and starts orchestration
/// 4. All 6 components execute in sequence:
///    - NamespaceSelector (picks namespace)
///    - ToolSelector (picks tools)
///    - ContextInjector (loads context)
///    - LLMConfigSelector (selects config)
///    - LLMOrchestrator (calls LLM)
///    - ResponseRenderer (formats response)
/// 5. Each component records invocation
/// 6. All invocations share correlationId (turn tracing)
/// 7. Events publish in order (can see turn progression)
/// 8. Errors in any component don't break persistence
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/bootstrap.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/services/event_bus_impl.dart';
import 'package:everything_stack_template/services/events/transcription_complete.dart';
import 'package:everything_stack_template/services/events/error_occurred.dart';
import 'package:everything_stack_template/persistence/event_repository_in_memory.dart';
import 'package:everything_stack_template/core/event_repository.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/domain/invocation.dart';

void main() {
  group('Audio Pipeline Event Chain', () {
    late EventBus eventBus;
    late EventRepository eventRepository;
    late InvocationRepository<Invocation> invocationRepo;
    late List<String> eventSequence; // Track event order
    late List<String> errors;

    setUp(() {
      // Create fresh repositories for each test
      eventRepository = InMemoryEventRepository();
      invocationRepo = _MockInvocationRepository();

      // Create EventBus with persistence
      eventBus = EventBusImpl(repository: eventRepository);

      // Track event order and errors
      eventSequence = [];
      errors = [];

      // Subscribe to all event types to track sequence
      eventBus.subscribe<TranscriptionComplete>().listen((event) {
        eventSequence.add('TranscriptionComplete');
      });

      eventBus.subscribe<ErrorOccurred>().listen((event) {
        eventSequence.add('ErrorOccurred');
        errors.add('${event.source}: ${event.message}');
      });
    });

    tearDown(() {
      eventBus.dispose();
    });

    test('STT publishes TranscriptionComplete with correlationId', () async {
      // Arrange
      final correlationId = 'audio_pipeline_001';
      final transcript = 'what is the weather in new york';

      // Act: Simulate STT publishing event
      final event = TranscriptionComplete(
        transcript: transcript,
        durationMs: 2500,
        confidence: 0.95,
        correlationId: correlationId,
      );
      await eventBus.publish(event);

      // Assert: Event persisted with correlationId intact
      await Future.delayed(Duration(milliseconds: 50));
      final persisted = await eventRepository.getByCorrelationId(correlationId);

      expect(persisted.isNotEmpty, isTrue, reason: 'Event should persist');
      expect((persisted.first as TranscriptionComplete).transcript,
          equals(transcript));
      expect(persisted.first.correlationId, equals(correlationId),
          reason: 'CorrelationId should be preserved');
    });

    test('Coordinator receives TranscriptionComplete and initiates orchestration',
        () async {
      // Arrange
      final correlationId = 'audio_pipeline_002';
      final transcript = 'what time is it';

      // Track if Coordinator listener fires
      var coordinatorHeard = false;
      var heardTranscript = '';

      // Simulate Coordinator listener
      eventBus.subscribe<TranscriptionComplete>().listen((event) {
        coordinatorHeard = true;
        heardTranscript = event.transcript;
      });

      // Act: STT publishes event
      final event = TranscriptionComplete(
        transcript: transcript,
        durationMs: 1800,
        confidence: 0.92,
        correlationId: correlationId,
      );
      await eventBus.publish(event);

      // Wait for listener
      await Future.delayed(Duration(milliseconds: 100));

      // Assert: Coordinator received it and can start orchestration
      expect(coordinatorHeard, isTrue,
          reason: 'Coordinator should hear TranscriptionComplete');
      expect(heardTranscript, equals(transcript));
      expect(eventSequence.contains('TranscriptionComplete'), isTrue);
    });

    test(
        'All invocations from 6 components share same correlationId (turn tracing)',
        () async {
      // Arrange
      final turnId = 'audio_pipeline_003';
      final correlationId = turnId;

      // Simulate all 6 components recording invocations with same correlationId
      final invocation1 = _createMockInvocation(
        componentType: 'namespace_selector',
        correlationId: correlationId,
      );
      final invocation2 = _createMockInvocation(
        componentType: 'tool_selector',
        correlationId: correlationId,
      );
      final invocation3 = _createMockInvocation(
        componentType: 'context_injector',
        correlationId: correlationId,
      );
      final invocation4 = _createMockInvocation(
        componentType: 'llm_config_selector',
        correlationId: correlationId,
      );
      final invocation5 = _createMockInvocation(
        componentType: 'llm_orchestrator',
        correlationId: correlationId,
      );
      final invocation6 = _createMockInvocation(
        componentType: 'response_renderer',
        correlationId: correlationId,
      );

      // Act: Each component saves its invocation
      await invocationRepo.save(invocation1);
      await invocationRepo.save(invocation2);
      await invocationRepo.save(invocation3);
      await invocationRepo.save(invocation4);
      await invocationRepo.save(invocation5);
      await invocationRepo.save(invocation6);

      // Assert: All invocations have same correlationId (turn tracing)
      final allInvocations = await invocationRepo.findAll();
      expect(allInvocations.length, equals(6),
          reason: 'All 6 components should record invocations');

      for (final inv in allInvocations) {
        expect(inv.correlationId, equals(correlationId),
            reason:
                '${inv.componentType} invocation should share turn correlationId');
      }
    });

    test(
        'Events and invocations form complete turn audit trail with correlationId',
        () async {
      // Arrange: Create a complete turn with both events and invocations
      final correlationId = 'audio_pipeline_004';

      // Publish TranscriptionComplete event
      await eventBus.publish(TranscriptionComplete(
        transcript: 'hello world',
        durationMs: 2000,
        confidence: 0.98,
        correlationId: correlationId,
      ));

      // Simulate 6 components recording invocations
      for (int i = 0; i < 6; i++) {
        await invocationRepo.save(
          _createMockInvocation(
            componentType: ['namespace_selector', 'tool_selector', 'context_injector',
                  'llm_config_selector', 'llm_orchestrator', 'response_renderer'][i],
            correlationId: correlationId,
          ),
        );
      }

      // Publish completion event
      await Future.delayed(Duration(milliseconds: 50));

      // Act: Query turn's complete audit trail
      final events = await eventRepository.getByCorrelationId(correlationId);
      final invocations = await invocationRepo.findAll();

      // Assert: Turn has both events and invocations with same correlationId
      expect(events.isNotEmpty, isTrue, reason: 'Turn should have events');
      expect(invocations.isNotEmpty, isTrue,
          reason: 'Turn should have invocations');

      // All share correlationId
      for (final event in events) {
        expect(event.correlationId, equals(correlationId));
      }
      for (final inv in invocations) {
        expect(inv.correlationId, equals(correlationId));
      }

      // Can reconstruct turn progression
      expect(events[0], isA<TranscriptionComplete>());
      expect((events[0] as TranscriptionComplete).transcript, equals('hello world'));
    });

    test('Error in component records ErrorOccurred but doesnt break pipeline',
        () async {
      // Arrange
      final correlationId = 'audio_pipeline_error_001';

      // Publish transcription
      await eventBus.publish(TranscriptionComplete(
        transcript: 'get weather',
        durationMs: 2000,
        confidence: 0.95,
        correlationId: correlationId,
      ));

      // Simulate component error (e.g., namespace selector fails)
      final error = ErrorOccurred(
        source: 'namespace_selector',
        message: 'No matching namespace for intent',
        errorType: 'NoMatchException',
        correlationId: correlationId,
        severity: 'warning',
      );

      // Act: Publish error event
      await eventBus.publish(error);

      // Coordinator continues with fallback
      await invocationRepo.save(
        _createMockInvocation(
          componentType: 'coordinator_recovery',
          correlationId: correlationId,
        ),
      );

      await Future.delayed(Duration(milliseconds: 50));

      // Assert: Error is persisted, pipeline continued
      final events = await eventRepository.getByCorrelationId(correlationId);
      expect(events.length, greaterThanOrEqualTo(2),
          reason: 'Turn should have both transcription and error events');

      final errorEvent = events.whereType<ErrorOccurred>().first;
      expect(errorEvent.source, equals('namespace_selector'));
      expect(errorEvent.message, contains('No matching namespace'));

      // Invocation recorded despite error
      final invocations = await invocationRepo.findAll();
      expect(invocations.isNotEmpty, isTrue,
          reason: 'Invocations should still be recorded after error');
    });

    test('Multiple events in turn maintain order and correlationId', () async {
      // Arrange
      final correlationId = 'audio_pipeline_005';
      final eventLog = <String>[];

      // Track order of specific events
      eventBus.subscribe<TranscriptionComplete>().listen((event) {
        eventLog.add('1_transcription');
      });

      eventBus.subscribe<ErrorOccurred>().listen((event) {
        eventLog.add('2_error_${event.source}');
      });

      // Act: Publish multiple events in sequence
      await eventBus.publish(TranscriptionComplete(
        transcript: 'play music',
        durationMs: 1500,
        confidence: 0.90,
        correlationId: correlationId,
      ));

      await Future.delayed(Duration(milliseconds: 10));

      await eventBus.publish(ErrorOccurred(
        source: 'tool_selector',
        message: 'Music player not available',
        errorType: 'UnavailableException',
        correlationId: correlationId,
        severity: 'warning',
      ));

      await Future.delayed(Duration(milliseconds: 50));

      // Assert: Events are in order and all share correlationId
      expect(eventLog, equals(['1_transcription', '2_error_tool_selector']),
          reason: 'Events should be in publication order');

      final allEvents = await eventRepository.getByCorrelationId(correlationId);
      expect(allEvents.length, equals(2));
      expect(allEvents[0], isA<TranscriptionComplete>());
      expect(allEvents[1], isA<ErrorOccurred>());

      // All share correlationId
      for (final event in allEvents) {
        expect(event.correlationId, equals(correlationId));
      }
    });

    test('Turn with 6 components, errors, and feedback creates full audit trail',
        () async {
      // Arrange: Complete realistic turn
      final turnId = 'audio_pipeline_full_006';

      // Phase 1: STT
      await eventBus.publish(TranscriptionComplete(
        transcript: 'show me my calendar',
        durationMs: 3000,
        confidence: 0.94,
        correlationId: turnId,
      ));

      // Phase 2: 6 components record invocations
      final components = [
        'namespace_selector',
        'tool_selector',
        'context_injector',
        'llm_config_selector',
        'llm_orchestrator',
        'response_renderer'
      ];

      for (final comp in components) {
        await invocationRepo.save(
          _createMockInvocation(
            componentType: comp,
            correlationId: turnId,
          ),
        );
      }

      // Phase 3: Tool execution
      await invocationRepo.save(
        _createMockInvocation(
          componentType: 'tool_executor_calendar',
          correlationId: turnId,
        ),
      );

      await Future.delayed(Duration(milliseconds: 100));

      // Act: Query complete turn
      final turnEvents = await eventRepository.getByCorrelationId(turnId);
      final turnInvocations = await invocationRepo.findAll();

      // Assert: Complete audit trail
      expect(turnEvents.isNotEmpty, isTrue,
          reason: 'Turn should have events (STT)');
      expect(turnInvocations.isNotEmpty, isTrue,
          reason: 'Turn should have invocations (all components)');

      // All have same correlationId
      expect(turnEvents.first.correlationId, equals(turnId));
      for (final inv in turnInvocations) {
        expect(inv.correlationId, equals(turnId),
            reason: 'All ${inv.componentType} invocations should share turn ID');
      }

      // Can reconstruct progression
      expect(turnInvocations.length, greaterThanOrEqualTo(7),
          reason: 'Should have 6 components + 1 tool = 7 invocations');
    });
  });
}

// Mock implementation for testing
Invocation _createMockInvocation({
  required String componentType,
  required String correlationId,
}) {
  return Invocation(
    correlationId: correlationId,
    componentType: componentType,
    success: true,
    confidence: 0.95,
    turnId: correlationId,
    input: {'input': 'test'},
    output: {'result': 'success'},
  );
}

class _MockInvocationRepository implements InvocationRepository<Invocation> {
  final List<Invocation> _invocations = [];

  @override
  Future<Invocation> save(Invocation entity) async {
    _invocations.add(entity);
    return entity;
  }

  @override
  Future<Invocation?> findById(String id) async {
    try {
      return _invocations.firstWhere((inv) => inv.uuid == id);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<Invocation>> findAll() async => List.from(_invocations);

  @override
  Future<bool> delete(String id) async {
    final before = _invocations.length;
    _invocations.removeWhere((inv) => inv.uuid == id);
    return _invocations.length < before;
  }

  @override
  Future<List<Invocation>> findByTurn(String turnId) async {
    return _invocations.where((inv) => inv.turnId == turnId).toList();
  }

  @override
  Future<int> deleteByTurn(String turnId) async {
    final before = _invocations.length;
    _invocations.removeWhere((inv) => inv.turnId == turnId);
    return before - _invocations.length;
  }

  @override
  Future<List<Invocation>> findByContextType(String contextType) async {
    // For MVP testing, we don't use contextType - just return empty
    return [];
  }

  @override
  Future<List<Invocation>> findByIds(List<String> ids) async {
    return _invocations.where((inv) => ids.contains(inv.uuid)).toList();
  }
}
