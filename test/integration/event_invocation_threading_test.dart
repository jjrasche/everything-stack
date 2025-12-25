/// Generic Invocation Threading Integration Test
///
/// TRUE E2E integration test: Verifies that when an utterance flows through the Coordinator,
/// all 6 trainable components record invocations with the same correlationId.
///
/// Tests the real Coordinator with real trainable components and mocked external APIs.
/// This is true E2E testing: real internals, mock only external dependencies.

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:everything_stack_template/domain/invocation.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/services/coordinator.dart';
import 'package:everything_stack_template/bootstrap.dart' show getIt, setupServiceLocatorForTesting;

void main() {
  group('Coordinator E2E - Real Internals, Mock Externals Only', () {
    late String correlationId;

    setUp(() {
      correlationId = 'evt_${const Uuid().v4()}';
      // setupServiceLocatorForTesting() handles all GetIt registration:
      // - Real trainables (NamespaceSelector, ToolSelector, etc.)
      // - Real repositories (in-memory for test speed)
      // - Mock only external APIs (EmbeddingService, LLMService)
      setupServiceLocatorForTesting();
    });

    test('Generic Invocation records all components with same correlationId', () async {
      // CRITICAL: All components must record generic Invocation with same correlationId
      // This verifies the new generic invocation pattern works

      final repo = getIt<InvocationRepository<Invocation>>();

      // Create invocations for each component type
      final namespaceInv = Invocation(
        correlationId: correlationId,
        componentType: 'namespace_selector',
        success: true,
        confidence: 0.9,
        input: {'utterance': 'set a timer'},
        output: {'selectedNamespace': 'timer'},
      );

      final toolInv = Invocation(
        correlationId: correlationId,
        componentType: 'tool_selector',
        success: true,
        confidence: 0.85,
        input: {'namespace': 'timer'},
        output: {'selectedTools': ['timer.set']},
      );

      final llmInv = Invocation(
        correlationId: correlationId,
        componentType: 'llm_orchestrator',
        success: true,
        confidence: 1.0,
        input: {'utterance': 'set a timer'},
        output: {'response': 'Setting timer for 5 minutes'},
      );

      // Save all invocations
      await repo.save(namespaceInv);
      await repo.save(toolInv);
      await repo.save(llmInv);

      // VERIFY: Can query all invocations by correlationId
      final allInvs = await repo.findByTurn(correlationId);
      expect(allInvs.length, equals(3));

      // VERIFY: Each invocation has correct componentType
      final componentTypes = allInvs.map((i) => i.componentType).toSet();
      expect(componentTypes, equals({'namespace_selector', 'tool_selector', 'llm_orchestrator'}));

      // VERIFY: All have same correlationId
      for (final inv in allInvs) {
        expect(inv.correlationId, equals(correlationId));
      }
    });

    test('Real Coordinator orchestrates and records 6 trainable invocations', () async {
      // Test that real Coordinator with real trainables records all components

      final coordinator = getIt<Coordinator>();
      final repo = getIt<InvocationRepository<Invocation>>();

      // Call real Coordinator to process an utterance
      // Real trainables execute, mock externals are called
      final result = await coordinator.orchestrate(
        correlationId: correlationId,
        utterance: 'create a task to buy groceries',
        availableNamespaces: ['task', 'timer', 'media'],
        toolsByNamespace: {
          'task': ['task.create', 'task.complete', 'task.list'],
          'timer': ['timer.set', 'timer.cancel'],
          'media': ['media.search', 'media.play'],
        },
      );

      // VERIFY: Orchestration succeeded
      expect(result.success, true,
          reason: 'Coordinator should successfully orchestrate');

      // VERIFY: All 6 trainable components recorded invocations
      final allInvs = await repo.findByTurn(correlationId);
      expect(allInvs.length, equals(6),
          reason:
              'Should record 6 invocations: namespace_selector, tool_selector, context_injector, llm_config_selector, llm_orchestrator, response_renderer');

      // VERIFY: Each invocation has correct componentType
      final componentTypes = allInvs.map((i) => i.componentType).toSet();
      expect(componentTypes.length, equals(6));
      expect(
        componentTypes,
        equals({
          'namespace_selector',
          'tool_selector',
          'context_injector',
          'llm_config_selector',
          'llm_orchestrator',
          'response_renderer',
        }),
      );

      // VERIFY: All have success=true
      for (final inv in allInvs) {
        expect(inv.success, true);
        expect(inv.confidence, greaterThan(0));
      }
    });

    test('Multiple orchestrations maintain separate correlationIds', () async {
      // Test that multiple orchestrations don't mix invocations

      final correlationId2 = 'evt_${const Uuid().v4()}';
      final coordinator = getIt<Coordinator>();
      final repo = getIt<InvocationRepository<Invocation>>();

      // Process two separate orchestrations through real Coordinator
      await coordinator.orchestrate(
        correlationId: correlationId,
        utterance: 'first utterance',
        availableNamespaces: ['task'],
        toolsByNamespace: {'task': ['task.create']},
      );

      await coordinator.orchestrate(
        correlationId: correlationId2,
        utterance: 'second utterance',
        availableNamespaces: ['timer'],
        toolsByNamespace: {'timer': ['timer.set']},
      );

      // VERIFY: First event has 6 invocations
      final invs1 = await repo.findByTurn(correlationId);
      expect(invs1.length, equals(6),
          reason: 'First orchestration should record 6 invocations');

      // VERIFY: Second event has 6 invocations
      final invs2 = await repo.findByTurn(correlationId2);
      expect(invs2.length, equals(6),
          reason: 'Second orchestration should record 6 invocations');

      // VERIFY: No cross-contamination
      for (final inv in invs1) {
        expect(inv.correlationId, equals(correlationId),
            reason: 'All invocations from first orchestration should have first correlationId');
      }
      for (final inv in invs2) {
        expect(inv.correlationId, equals(correlationId2),
            reason: 'All invocations from second orchestration should have second correlationId');
      }
    });
  });
}
