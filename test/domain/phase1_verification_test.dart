/// Phase 1 Verification Tests
/// Tests instantiation, mixin composition, and serialization

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/namespace.dart';
import 'package:everything_stack_template/domain/tool.dart';
import 'package:everything_stack_template/domain/event.dart';
import 'package:everything_stack_template/tools/timer/entities/timer.dart';
import 'package:everything_stack_template/tools/task/entities/task.dart';
import 'package:everything_stack_template/domain/personality.dart';
import 'package:everything_stack_template/domain/namespace_adaptation_state.dart';
import 'package:everything_stack_template/domain/tool_selection_adaptation_state.dart';
import 'package:everything_stack_template/domain/context_manager_invocation.dart';
import 'package:everything_stack_template/patterns/ownable.dart';

void main() {
  group('Q3: Personality serialization', () {
    test('save and load with learned adaptation states', () {
      // Create personality with learned state
      final personality = Personality(
        name: 'Medical',
        systemPrompt: 'You are a helpful medical assistant.',
      );

      // Set namespace attention thresholds
      personality.namespaceAttention.setThreshold('health', 0.5); // LOW = high attention
      personality.namespaceAttention.setThreshold('task', 0.8); // HIGH = low attention
      personality.namespaceAttention.setCentroid('health', [0.1, 0.2, 0.3, 0.4]);

      // Set tool attention
      final healthTools = personality.getToolAttention('health');
      healthTools.setSuccessRate('diagnose', 0.9);
      healthTools.setKeywordWeight('diagnose', 'symptom', 2.5);

      // Prepare for save (serializes embedded states)
      personality.prepareForSave();

      // Simulate save/load by going through JSON
      final json = personality.toJson();
      final loaded = Personality.fromJson(json);

      // Verify thresholds preserved
      expect(loaded.namespaceAttention.getThreshold('health'), 0.5);
      expect(loaded.namespaceAttention.getThreshold('task'), 0.8);

      // Verify centroid preserved
      expect(loaded.namespaceAttention.getCentroid('health'), [0.1, 0.2, 0.3, 0.4]);

      // Verify tool attention preserved
      final loadedHealthTools = loaded.getToolAttention('health');
      expect(loadedHealthTools.getSuccessRate('diagnose'), 0.9);
      expect(loadedHealthTools.getKeywordWeight('diagnose', 'symptom'), 2.5);
    });
  });

  group('Q4: Task mixin composition', () {
    test('Task works with both Invocable and Ownable mixins', () {
      final task = Task(
        title: 'Buy groceries',
        priority: 'high',
        dueDate: DateTime.now().add(const Duration(days: 1)),
      );

      // Ownable mixin fields
      task.ownerId = 'user_123';
      task.shareWith('user_456');
      expect(task.visibility, Visibility.shared);
      expect(task.isAccessibleBy('user_123'), true);
      expect(task.isAccessibleBy('user_456'), true);
      expect(task.isAccessibleBy('user_789'), false);

      // Invocable mixin fields
      task.recordInvocation(
        correlationId: 'corr_001',
        toolName: 'task.create',
        params: {'title': 'Buy groceries'},
        confidence: 0.95,
      );
      expect(task.wasInvoked, true);
      expect(task.invokedByTool, 'task.create');
      expect(task.invocationConfidence, 0.95);
      expect(task.invocationSucceeded, true);
    });
  });

  group('Q5: Event inheritance', () {
    test('Event extends BaseEntity but no @Entity annotation', () {
      final event = Event(
        correlationId: 'corr_001',
        source: 'user',
        payload: {'transcription': 'set a timer for 5 minutes'},
      );

      // BaseEntity fields work
      expect(event.uuid.isNotEmpty, true);
      expect(event.createdAt, isNotNull);

      // Event-specific fields work
      expect(event.correlationId, 'corr_001');
      expect(event.source, 'user');
      expect(event.payload['transcription'], 'set a timer for 5 minutes');
    });
  });

  group('Q6: Constructor instantiation', () {
    test('Timer instantiates correctly', () {
      final timer = Timer(
        label: '5 minute break',
        durationSeconds: 300,
        setAt: DateTime.now(),
        endsAt: DateTime.now().add(const Duration(seconds: 300)),
      );

      expect(timer.label, '5 minute break');
      expect(timer.durationSeconds, 300);
      expect(timer.isActive, true);
      expect(timer.fired, false);

      // Record invocation
      timer.recordInvocation(
        correlationId: 'corr_002',
        toolName: 'timer.set',
        confidence: 0.88,
      );
      expect(timer.invokedByTool, 'timer.set');
    });

    test('Task instantiates correctly', () {
      final task = Task(
        title: 'Test task',
        priority: 'medium',
      );

      expect(task.title, 'Test task');
      expect(task.priority, 'medium');
      expect(task.completed, false);
    });

    test('Personality instantiates correctly', () {
      final personality = Personality(
        name: 'Task Planner',
        systemPrompt: 'You help users manage tasks.',
      );

      expect(personality.name, 'Task Planner');
      expect(personality.temperature, 0.7);
      expect(personality.namespaceAttention, isNotNull);
    });
  });

  group('Q7: Adaptation state embedding', () {
    test('States stored as JSON strings in Personality', () {
      final personality = Personality(
        name: 'Test',
        systemPrompt: 'Test prompt',
      );

      // Initially empty JSON
      expect(personality.namespaceAttentionJson, '{}');
      expect(personality.toolAttentionJson, '{}');

      // Add some state
      personality.namespaceAttention.setThreshold('task', 0.6);
      personality.getToolAttention('task').setSuccessRate('create', 0.8);

      // Call prepareForSave to serialize
      personality.prepareForSave();

      // Now JSON strings are populated
      expect(personality.namespaceAttentionJson.contains('task'), true);
      expect(personality.namespaceAttentionJson.contains('0.6'), true);
      expect(personality.toolAttentionJson.contains('task'), true);
      expect(personality.toolAttentionJson.contains('0.8'), true);

      // These JSON strings are what ObjectBox persists
      // @Transient fields (the actual objects) are rebuilt on load
    });
  });

  group('Additional: Namespace and Tool', () {
    test('Namespace instantiates correctly', () {
      final namespace = Namespace(
        name: 'task',
        description: 'Manage tasks and reminders',
        keywords: ['todo', 'reminder'],
      );

      expect(namespace.name, 'task');
      expect(namespace.keywords, ['todo', 'reminder']);
    });

    test('Tool instantiates with fullName', () {
      final tool = Tool(
        name: 'create',
        namespaceId: 'task',
        description: 'Create a new task',
        keywords: ['add', 'new'],
        parameters: {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
          },
        },
      );

      expect(tool.fullName, 'task.create');
      expect(tool.parameters['type'], 'object');
    });

    test('ContextManagerInvocation instantiates correctly', () {
      final invocation = ContextManagerInvocation(
        correlationId: 'corr_003',
      );

      invocation.toolsAvailable = ['task.create', 'task.complete'];
      invocation.toolsPassedToLLM = ['task.create'];
      invocation.toolsCalled = ['task.create'];
      invocation.confidence = 0.92;

      expect(invocation.componentType, 'context_manager');
      expect(invocation.wasFiltered('task.complete'), false);
      expect(invocation.wasCalled('task.create'), true);
    });
  });
}
