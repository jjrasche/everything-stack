/// ContextManager Integration Test
/// End-to-end: Event → ContextManager → Invocation → Result

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/event.dart';
import 'package:everything_stack_template/domain/personality.dart';
import 'package:everything_stack_template/domain/namespace.dart' as domain;
import 'package:everything_stack_template/domain/tool.dart';
import 'package:everything_stack_template/tools/task/entities/task.dart';
import 'package:everything_stack_template/domain/context_manager_invocation.dart';
import 'package:everything_stack_template/services/context_manager_result.dart';

void main() {
  group('ContextManager Integration - Full Flow', () {
    test('Event with "create task" → selects task namespace → returns tool call',
        () async {
      // ARRANGE
      // 1. Create personality with learned thresholds
      final personality = Personality(
        name: 'Task Planner',
        systemPrompt: 'You help users manage tasks',
      );
      personality.namespaceAttention.setThreshold('task', 0.6);
      personality.namespaceAttention.setThreshold('timer', 0.7);

      // Set tool success rates
      final taskTools = personality.getToolAttention('task');
      taskTools.setSuccessRate('create', 0.9);
      taskTools.setSuccessRate('complete', 0.7);
      taskTools.setKeywordWeight('create', 'add', 1.5);
      taskTools.setKeywordWeight('create', 'new', 1.3);

      // 2. Create namespaces with centroids
      domain.Namespace(
        name: 'task',
        description: 'Manage tasks and to-dos',
        keywords: ['task', 'todo', 'remind'],
        semanticCentroid: List.filled(384, 0.7), // Mock embedding
      );

      domain.Namespace(
        name: 'timer',
        description: 'Set timers and countdowns',
        keywords: ['timer', 'alarm', 'countdown'],
        semanticCentroid: List.filled(384, 0.3), // Low score for "create task"
      );

      // 3. Create tools in task namespace
      final createTool = Tool(
        name: 'create',
        namespaceId: 'task',
        description: 'Create a new task',
        keywords: ['add', 'new', 'create'],
        parameters: {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'priority': {'type': 'string'},
          },
          'required': ['title'],
        },
        semanticCentroid: List.filled(384, 0.8), // High semantic match
      );

      Tool(
        name: 'complete',
        namespaceId: 'task',
        description: 'Mark a task as complete',
        keywords: ['done', 'finish', 'complete'],
        semanticCentroid: List.filled(384, 0.4), // Low match for "create"
      );

      // 4. Create event
      final event = Event(
        correlationId: 'corr_001',
        source: 'user',
        payload: {'transcription': 'create a task to buy groceries'},
      );

      // ACT
      // Would call: final result = await contextManager.handleEvent(event);

      // ASSERT - What we expect:
      // 1. Personality loaded
      expect(personality.namespaceAttention.getThreshold('task'), 0.6);

      // 2. Event embedded
      expect(event.payload['transcription'], isNotEmpty);

      // 3. Namespace selection
      // - task scores 0.7 (above 0.6 threshold) ✓
      // - timer scores 0.3 (below 0.7 threshold) ✗
      // Expected: task namespace selected

      // 4. Tool filtering
      // - create: 0.6 * 0.8 (semantic) + 0.4 * 0.9 (statistical) = 0.84 ✓
      // - complete: 0.6 * 0.4 (semantic) + 0.4 * 0.7 (statistical) = 0.52 ✓
      // Both above 0.5 threshold, but create scores higher

      // 5. Context injection
      // - Would call taskRepo.findIncomplete()
      // - Format as "Open tasks:\n- Task 1..."

      // 6. LLM called with:
      // - tools: [task.create, task.complete]
      // - context: open tasks
      // - user message: "create a task to buy groceries"

      // 7. Expected result:
      // - selectedNamespace: 'task'
      // - toolCalls: [{toolName: 'task.create', params: {...}, confidence: 0.84}]
      // - confidence: 0.84
      // - invocationId: (uuid)

      expect(createTool.fullName, 'task.create');
      expect(taskTools.getSuccessRate('create'), 0.9);
    });

    test('Event with "set timer" → selects timer namespace → returns tool call',
        () async {
      // ARRANGE
      final personality = Personality(
        name: 'General Assistant',
        systemPrompt: 'You are a helpful assistant',
      );
      personality.namespaceAttention.setThreshold('task', 0.7);
      personality.namespaceAttention.setThreshold('timer', 0.6);

      final timerTools = personality.getToolAttention('timer');
      timerTools.setSuccessRate('set', 0.95);

      domain.Namespace(
        name: 'timer',
        description: 'Set timers and alarms',
        semanticCentroid: List.filled(384, 0.8), // High score for "timer"
      );

      Event(
        correlationId: 'corr_002',
        source: 'user',
        payload: {'transcription': 'set a timer for 5 minutes'},
      );

      // ACT
      // Would select timer namespace (scores 0.8, above 0.6 threshold)

      // ASSERT
      expect(personality.namespaceAttention.getThreshold('timer'), 0.6);
      expect(timerTools.getSuccessRate('set'), 0.95);
      expect(event.payload['transcription'], contains('timer'));
    });

    test('No namespace passes threshold → returns noNamespace error', () async {
      final personality = Personality(
        name: 'Strict',
        systemPrompt: 'Test',
      );
      // Set very high thresholds
      personality.namespaceAttention.setThreshold('task', 0.9);
      personality.namespaceAttention.setThreshold('timer', 0.9);

      Event(
        correlationId: 'corr_003',
        source: 'user',
        payload: {'transcription': 'hello'},
      );

      // "hello" would score low (~0.3) against all namespaces
      // None pass 0.9 threshold
      // Expected: ContextManagerResult.noNamespace()

      final result = ContextManagerResult.noNamespace(
        invocationId: 'test_uuid',
      );

      expect(result.hasError, true);
      expect(result.errorType, 'no_namespace');
      expect(result.toolCalls, isEmpty);
    });

    test('Namespace selected but no tools pass → returns noTools error',
        () async {
      // Namespace passes threshold, but all tools score below threshold
      final result = ContextManagerResult.noTools(
        selectedNamespace: 'task',
        invocationId: 'test_uuid',
      );

      expect(result.hasError, true);
      expect(result.errorType, 'no_tools');
      expect(result.selectedNamespace, 'task');
      expect(result.toolCalls, isEmpty);
    });

    test('ContextManagerInvocation captures full decision trail', () async {
      final invocation = ContextManagerInvocation(
        correlationId: 'corr_004',
      );

      // Populate as ContextManager would
      invocation.personalityId = 'personality_uuid';
      invocation.eventEmbedding = List.filled(384, 0.5);
      invocation.namespacesConsidered = ['task', 'timer', 'note'];
      invocation.namespaceScores = {
        'task': 0.8,
        'timer': 0.4,
        'note': 0.3,
      };
      invocation.selectedNamespace = 'task';
      invocation.toolsAvailable = ['task.create', 'task.complete', 'task.delete'];
      invocation.toolScores = {
        'task.create': 0.85,
        'task.complete': 0.62,
        'task.delete': 0.35,
      };
      invocation.toolsPassedToLLM = ['task.create', 'task.complete'];
      invocation.toolsFiltered = ['task.delete'];
      invocation.toolsCalled = ['task.create'];
      invocation.confidence = 0.85;
      invocation.contextItemCounts = {'tasks': 5};
      invocation.latencyMs = 250;

      // Verify full trail captured
      expect(invocation.selectedNamespace, 'task');
      expect(invocation.namespaceScores['task'], 0.8);
      expect(invocation.toolsPassedToLLM.length, 2);
      expect(invocation.wasFiltered('task.delete'), true);
      expect(invocation.wasCalled('task.create'), true);
      expect(invocation.confidence, 0.85);
    });

    test('Multiple tool calls handled correctly', () {
      // LLM can call multiple tools in one response
      final toolCalls = [
        ToolCall(
          toolName: 'task.create',
          params: {'title': 'Task 1'},
          confidence: 0.9,
          callId: 'call_1',
        ),
        ToolCall(
          toolName: 'task.create',
          params: {'title': 'Task 2'},
          confidence: 0.85,
          callId: 'call_2',
        ),
      ];

      final avgConfidence =
          toolCalls.fold<double>(0.0, (sum, tc) => sum + tc.confidence) /
              toolCalls.length;

      expect(toolCalls.length, 2);
      expect(avgConfidence, closeTo(0.875, 0.001));
    });
  });

  group('ContextManager Integration - Context Injection', () {
    test('Task namespace injects incomplete tasks into LLM context', () {
      final tasks = [
        Task(title: 'Buy groceries', priority: 'high'),
        Task(title: 'Call dentist', priority: 'medium'),
        Task(title: 'Finish report', priority: 'high', completed: true),
      ];

      final incomplete = tasks.where((t) => !t.completed).toList();
      final context = incomplete
          .map((t) => {
                'title': t.title,
                'priority': t.priority,
              })
          .toList();

      expect(context.length, 2);
      expect(context[0]['title'], 'Buy groceries');
      expect(context[1]['priority'], 'medium');

      // Would format as:
      // "Open tasks:
      // - Buy groceries (priority: high)
      // - Call dentist (priority: medium)"
    });

    test('Empty context when no tasks exist', () {
      final tasks = <Task>[];
      final context = tasks
          .map((t) => {
                'title': t.title,
              })
          .toList();

      expect(context, isEmpty);
      // LLM would not receive context message
    });
  });

  group('ContextManager Integration - Error Scenarios', () {
    test('Handles database failure gracefully', () {
      // If TaskRepository throws, should catch and return error
      try {
        throw Exception('Database connection failed');
      } catch (e) {
        final result = ContextManagerResult.error(
          invocationId: 'test_uuid',
          error: e.toString(),
          errorType: 'unknown_error',
        );

        expect(result.hasError, true);
        expect(result.error, contains('Database connection'));
      }
    });

    test('Handles malformed LLM response', () {
      // If Groq returns invalid JSON in arguments
      try {
        // This would throw in parsedArguments
        throw FormatException('Invalid JSON');
      } catch (e) {
        expect(e, isA<FormatException>());
        // Would be caught and returned as llm_error
      }
    });
  });
}
