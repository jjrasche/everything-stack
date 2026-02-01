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
import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/tools/task/repositories/task_repository.dart';
import 'package:everything_stack_template/tools/regulation/repositories/person_repository.dart';
import 'package:everything_stack_template/tools/regulation/repositories/regulation_entry_repository.dart';
import 'package:everything_stack_template/tools/regulation/repositories/commitment_repository.dart';
import 'package:everything_stack_template/tools/regulation/repositories/commitment_log_repository.dart';
import 'package:everything_stack_template/core/enrichment_queue_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/services/enrichment/enrichment_runner.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/services/hnsw_index.dart';

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
      } else if (type == PersonRepository) {
        _repos[type] = getIt<PersonRepository>();
      } else if (type == RegulationEntryRepository) {
        _repos[type] = getIt<RegulationEntryRepository>();
      } else if (type == CommitmentRepository) {
        _repos[type] = getIt<CommitmentRepository>();
      } else if (type == CommitmentLogRepository) {
        _repos[type] = getIt<CommitmentLogRepository>();
      } else if (type == FeedbackRepository) {
        _repos[type] = getIt<FeedbackRepository>();
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
  PersonRepository get personRepo => get<PersonRepository>();
  RegulationEntryRepository get regulationEntryRepo => get<RegulationEntryRepository>();
  CommitmentRepository get commitmentRepo => get<CommitmentRepository>();
  CommitmentLogRepository get commitmentLogRepo => get<CommitmentLogRepository>();
  FeedbackRepository get feedbackRepo => get<FeedbackRepository>();

  // Enrichment queue related services (always available from GetIt)
  EnrichmentQueueRepository get enrichmentQueueRepo => GetIt.instance<EnrichmentQueueRepository>();
  EnrichmentRunner get enrichmentRunner => GetIt.instance<EnrichmentRunner>();
  ChunkingService get chunkingService => GetIt.instance<ChunkingService>();
  HnswIndex get hnswIndex => GetIt.instance<HnswIndex>();

  // EntityRepository for invocations (with enrichment runner wired)
  // Use this for tests that need async enrichment
  EntityRepository<Invocation> get invocationEntityRepo => GetIt.instance<EntityRepository<Invocation>>();

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
        ? const Duration(seconds: 30)  // Smoke tests: real APIs may be slower
        : const Duration(seconds: 20);  // CI tests: should be fast with mocks

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
