/// # Audio Pipeline Test
///
/// Verifies core services are accessible and functional:
/// - InvocationRepository
/// - EventBus
/// - EventRepository

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/core/event_repository.dart';
import 'shared/test_harness.dart';
import 'shared/test_context.dart';

final audioPipelineTest = IntegrationTestConfig(
  name: 'Audio Pipeline',

  repos: [
    InvocationRepository<Invocation>,
  ],

  // No mockResponses - this test doesn't need Coordinator

  testLogic: (t) async {
    // Get services from GetIt
    final getIt = GetIt.instance;
    final invocationRepo = getIt<InvocationRepository<Invocation>>();
    final eventRepository = getIt<EventRepository>();
    final eventBus = getIt<EventBus>();

    // Verify services are registered
    expect(invocationRepo, isNotNull, reason: 'InvocationRepository should be registered');
    expect(eventRepository, isNotNull, reason: 'EventRepository should be registered');
    expect(eventBus, isNotNull, reason: 'EventBus should be registered');

    // Verify InvocationRepository is functional
    final invocations = await invocationRepo.findAll();
    expect(invocations, isNotNull, reason: 'findAll should return a list');

    // Verify EventRepository is functional
    final events = await eventRepository.getAll();
    expect(events, isNotNull, reason: 'EventRepository.getAll should return a list');
  },
);
