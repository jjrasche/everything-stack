/// # TestContext
///
/// Provides syntactic sugar for integration tests.
/// - Generic repo access via get<T>()
/// - Shortcuts for common repos (timerRepo, invocationRepo)
/// - STT helper that uses utterances map

import 'dart:async' show Completer, StreamSubscription, TimeoutException;
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/core/event.dart';
import 'package:everything_stack_template/tools/timer/repositories/timer_repository.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/tools/task/repositories/task_repository.dart';

class TestContext {
  final WidgetTester tester;
  final EventBus eventBus;
  final Map<String, String>? utterances;
  final Map<Type, dynamic> _repos = {};
  final bool isSmoke = const bool.fromEnvironment('SMOKE_TEST', defaultValue: false);

  TestContext(
    this.tester,
    List<Type> repoTypes,
    this.utterances,
  ) : eventBus = GetIt.instance<EventBus>() {
    final getIt = GetIt.instance;
    for (final type in repoTypes) {
      // Map Type → GetIt call
      if (type == TimerRepository) {
        _repos[type] = getIt<TimerRepository>();
      } else if (type == InvocationRepository<Invocation>) {
        _repos[type] = getIt<InvocationRepository<Invocation>>();
      } else if (type == TaskRepository) {
        _repos[type] = getIt<TaskRepository>();
      } else {
        throw ArgumentError('Unknown repo type: $type');
      }
    }
  }

  // Generic access
  T get<T>() => _repos[T] as T;

  // Syntactic sugar for common repos
  TimerRepository get timerRepo => get<TimerRepository>();
  InvocationRepository<Invocation> get invocationRepo => get<InvocationRepository<Invocation>>();
  TaskRepository get taskRepo => get<TaskRepository>();

  // STT helper - publishes transcription event and waits for orchestration to complete
  Future<void> stt(String key) async {
    if (utterances == null) {
      throw StateError('utterances not configured - cannot use stt()');
    }
    final transcript = utterances![key]!;

    final correlationId = 'turn_${DateTime.now().millisecondsSinceEpoch}';

    // Set up listener for orchestration_complete event BEFORE publishing
    final completer = Completer<void>();
    late StreamSubscription<Event> subscription;

    subscription = eventBus.subscribe().listen((event) {
      if (event.eventType == 'orchestration_complete' &&
          event.correlationId == correlationId) {
        completer.complete();
        subscription.cancel();
      }
    });

    // Publish transcription_complete event
    await eventBus.publish(Event(
      eventType: 'transcription_complete',
      correlationId: correlationId,
      source: 'stt',
      payloadJson: jsonEncode({'transcript': transcript}),
    ));

    // Wait for orchestration to complete (with timeout)
    final timeout = isSmoke
        ? const Duration(seconds: 15)  // Smoke tests: real APIs may be slower
        : const Duration(seconds: 10);  // CI tests: should be fast with mocks

    try {
      await completer.future.timeout(
        timeout,
        onTimeout: () {
          subscription.cancel();
          throw TimeoutException(
            'Orchestration did not complete within ${timeout.inSeconds}s for: $transcript',
          );
        },
      );
    } catch (e) {
      subscription.cancel();
      rethrow;
    }
  }
}
