/// Phase 1 Repository Verification
/// Tests that all 6 repositories have the required query methods

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/namespace.dart';
import 'package:everything_stack_template/domain/namespace_repository.dart';
import 'package:everything_stack_template/domain/tool.dart';
import 'package:everything_stack_template/domain/tool_repository.dart';
import 'package:everything_stack_template/tools/timer/entities/timer.dart';
import 'package:everything_stack_template/tools/timer/repositories/timer_repository.dart';
import 'package:everything_stack_template/tools/task/entities/task.dart';
import 'package:everything_stack_template/tools/task/repositories/task_repository.dart';
import 'package:everything_stack_template/domain/personality.dart';
import 'package:everything_stack_template/domain/personality_repository.dart';
import 'package:everything_stack_template/domain/context_manager_invocation.dart';
import 'package:everything_stack_template/domain/context_manager_invocation_repository.dart';
import 'package:everything_stack_template/core/persistence/mock_persistence_adapter.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

void main() {
  late EmbeddingService mockEmbedding;

  setUp(() {
    mockEmbedding = EmbeddingService.mock();
  });

  group('NamespaceRepository', () {
    test('findByName works', () async {
      final adapter = MockPersistenceAdapter<Namespace>();
      final repo = NamespaceRepository(
        adapter: adapter,
        embeddingService: mockEmbedding,
      );

      final ns = Namespace(name: 'task', description: 'Task management');
      adapter.mockEntities = [ns];

      final found = await repo.findByName('task');
      expect(found?.name, 'task');
    });

    test('exists checks for namespace', () async {
      final adapter = MockPersistenceAdapter<Namespace>();
      final repo = NamespaceRepository(
        adapter: adapter,
        embeddingService: mockEmbedding,
      );

      final ns = Namespace(name: 'task', description: 'Task management');
      adapter.mockEntities = [ns];

      expect(await repo.exists('task'), true);
      expect(await repo.exists('nonexistent'), false);
    });
  });

  group('ToolRepository', () {
    test('findByNamespace works', () async {
      final adapter = MockPersistenceAdapter<Tool>();
      final repo = ToolRepository(
        adapter: adapter,
        embeddingService: mockEmbedding,
      );

      final tool1 = Tool(
        name: 'create',
        namespaceId: 'task',
        description: 'Create task',
      );
      final tool2 = Tool(
        name: 'complete',
        namespaceId: 'task',
        description: 'Complete task',
      );
      final tool3 = Tool(
        name: 'set',
        namespaceId: 'timer',
        description: 'Set timer',
      );

      adapter.mockEntities = [tool1, tool2, tool3];

      final taskTools = await repo.findByNamespace('task');
      expect(taskTools.length, 2);
      expect(taskTools.every((t) => t.namespaceId == 'task'), true);
    });

    test('findByFullName works', () async {
      final adapter = MockPersistenceAdapter<Tool>();
      final repo = ToolRepository(
        adapter: adapter,
        embeddingService: mockEmbedding,
      );

      final tool = Tool(
        name: 'create',
        namespaceId: 'task',
        description: 'Create task',
      );
      adapter.mockEntities = [tool];

      final found = await repo.findByFullName('task.create');
      expect(found?.fullName, 'task.create');
    });
  });

  group('TimerRepository', () {
    test('findActive returns only active timers', () async {
      final adapter = MockPersistenceAdapter<Timer>();
      final repo = TimerRepository(
        adapter: adapter,
        embeddingService: mockEmbedding,
      );

      final now = DateTime.now();
      final active = Timer(
        label: 'Active',
        durationSeconds: 300,
        setAt: now,
        endsAt: now.add(const Duration(seconds: 300)),
      );
      final fired = Timer(
        label: 'Fired',
        durationSeconds: 300,
        setAt: now,
        endsAt: now,
        fired: true,
      );

      adapter.mockEntities = [active, fired];

      final activeTimers = await repo.findActive();
      expect(activeTimers.length, 1);
      expect(activeTimers[0].label, 'Active');
    });
  });

  group('TaskRepository', () {
    test('findIncomplete returns incomplete tasks', () async {
      final adapter = MockPersistenceAdapter<Task>();
      final repo = TaskRepository(
        adapter: adapter,
        embeddingService: mockEmbedding,
      );

      final incomplete = Task(title: 'Incomplete', priority: 'high');
      final complete = Task(
        title: 'Complete',
        priority: 'medium',
        completed: true,
      );

      adapter.mockEntities = [incomplete, complete];

      final incompleteTasks = await repo.findIncomplete();
      expect(incompleteTasks.length, 1);
      expect(incompleteTasks[0].title, 'Incomplete');
    });

    test('findByOwner returns user tasks', () async {
      final adapter = MockPersistenceAdapter<Task>();
      final repo = TaskRepository(
        adapter: adapter,
        embeddingService: mockEmbedding,
      );

      final myTask = Task(title: 'My task', priority: 'high');
      myTask.ownerId = 'user_123';

      final otherTask = Task(title: 'Other task', priority: 'medium');
      otherTask.ownerId = 'user_456';

      adapter.mockEntities = [myTask, otherTask];

      final myTasks = await repo.findByOwner('user_123');
      expect(myTasks.length, 1);
      expect(myTasks[0].title, 'My task');
    });
  });

  group('PersonalityRepository - CRITICAL for Phase 2', () {
    test('getActive returns active personality', () async {
      final adapter = MockPersistenceAdapter<Personality>();
      final repo = PersonalityRepository(
        adapter: adapter,
        embeddingService: mockEmbedding,
      );

      final active = Personality(
        name: 'Medical',
        systemPrompt: 'Medical assistant',
      );
      active.isActive = true;

      final inactive = Personality(
        name: 'Task Planner',
        systemPrompt: 'Task planner',
      );

      adapter.mockEntities = [active, inactive];

      final result = await repo.getActive();
      expect(result?.name, 'Medical');
      expect(result?.isActive, true);
    });

    test('setActive switches personalities', () async {
      final adapter = MockPersistenceAdapter<Personality>();
      final repo = PersonalityRepository(
        adapter: adapter,
        embeddingService: mockEmbedding,
      );

      final p1 = Personality(name: 'P1', systemPrompt: 'Prompt 1');
      p1.uuid = 'uuid_1';
      p1.isActive = true;

      final p2 = Personality(name: 'P2', systemPrompt: 'Prompt 2');
      p2.uuid = 'uuid_2';

      adapter.mockEntities = [p1, p2];

      await repo.setActive('uuid_2');

      // Verify p1 was deactivated and p2 was activated
      expect(p1.isActive, false);
      expect(p2.isActive, true);
    });

    test('save prepares embedded states', () async {
      final adapter = MockPersistenceAdapter<Personality>();
      final repo = PersonalityRepository(
        adapter: adapter,
        embeddingService: mockEmbedding,
      );

      final personality = Personality(
        name: 'Test',
        systemPrompt: 'Test prompt',
      );

      // Set some adaptation state
      personality.namespaceAttention.setThreshold('task', 0.6);

      await repo.save(personality);

      // Verify prepareForSave was called (JSON should be populated)
      expect(personality.namespaceAttentionJson.contains('task'), true);
    });
  });

  group('ContextManagerInvocationRepository', () {
    test('findByCorrelationId groups by chain', () async {
      final adapter = MockPersistenceAdapter<ContextManagerInvocation>();
      final repo = ContextManagerInvocationRepository(
        adapter: adapter,
        embeddingService: mockEmbedding,
      );

      final inv1 = ContextManagerInvocation(correlationId: 'corr_001');
      final inv2 = ContextManagerInvocation(correlationId: 'corr_001');
      final inv3 = ContextManagerInvocation(correlationId: 'corr_002');

      adapter.mockEntities = [inv1, inv2, inv3];

      final chain = await repo.findByCorrelationId('corr_001');
      expect(chain.length, 2);
    });

    test('findWithErrors returns only errors', () async {
      final adapter = MockPersistenceAdapter<ContextManagerInvocation>();
      final repo = ContextManagerInvocationRepository(
        adapter: adapter,
        embeddingService: mockEmbedding,
      );

      final success = ContextManagerInvocation(correlationId: 'corr_001');
      final error = ContextManagerInvocation(correlationId: 'corr_002');
      error.errorType = 'tool_error';
      error.errorMessage = 'Tool failed';

      adapter.mockEntities = [success, error];

      final errors = await repo.findWithErrors();
      expect(errors.length, 1);
      expect(errors[0].errorType, 'tool_error');
    });
  });
}
