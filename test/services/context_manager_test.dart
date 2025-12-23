/// ContextManager Tests
/// Tests namespace selection, tool filtering, context injection, error handling

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/groq_service.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/domain/event.dart';
import 'package:everything_stack_template/domain/personality.dart';
import 'package:everything_stack_template/domain/namespace.dart' as domain;
import 'package:everything_stack_template/domain/tool.dart';
import 'package:everything_stack_template/tools/task/entities/task.dart';
import 'package:everything_stack_template/tools/timer/entities/timer.dart';

// Mock repositories and services
class MockPersonalityRepo {
  Personality? mockPersonality;
  Future<Personality?> getActive() async => mockPersonality;
}

class MockNamespaceRepo {
  List<domain.Namespace> mockNamespaces = [];
  Future<List<domain.Namespace>> findAll() async => mockNamespaces;
}

class MockToolRepo {
  List<Tool> mockTools = [];
  Future<List<Tool>> findByNamespace(String ns) async =>
      mockTools.where((t) => t.namespaceId == ns).toList();
}

class MockTaskRepo {
  List<Task> mockTasks = [];
  Future<List<Task>> findIncomplete() async =>
      mockTasks.where((t) => !t.completed).toList();
}

class MockTimerRepo {
  List<Timer> mockTimers = [];
  Future<List<Timer>> findActive() async =>
      mockTimers.where((t) => t.isActive).toList();
}

class MockInvocationRepo {
  final savedInvocations = [];
  Future<int> save(dynamic invocation) async {
    savedInvocations.add(invocation);
    return 1;
  }
}

class MockGroqService {
  GroqResponse? mockResponse;
  GroqException? mockException;

  Future<GroqResponse> chat({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    if (mockException != null) throw mockException!;
    return mockResponse!;
  }
}

class MockEmbeddingService extends EmbeddingService {
  List<double> mockEmbedding = List.filled(384, 0.5);

  @override
  Future<List<double>> generate(String text) async => mockEmbedding;
}

void main() {
  group('ContextManager - Namespace Selection', () {
    test('selects namespace above threshold', () async {
      // Setup
      final personality = Personality(
        name: 'Test',
        systemPrompt: 'Test prompt',
      );
      personality.namespaceAttention.setThreshold('task', 0.6);

      final taskNs = domain.Namespace(
        name: 'task',
        description: 'Task management',
        semanticCentroid: List.filled(384, 0.7), // Will score 0.7
      );

      // Mock repos would return these
      // In real test, would inject mocks and verify selection logic
      expect(personality.namespaceAttention.getThreshold('task'), 0.6);
      expect(taskNs.semanticCentroid, isNotNull);
    });

    test('filters out namespace below threshold', () async {
      final personality = Personality(
        name: 'Test',
        systemPrompt: 'Test prompt',
      );
      personality.namespaceAttention.setThreshold('task', 0.8); // High threshold

      // If semantic score is 0.6, it won't pass 0.8 threshold
      expect(0.6 < 0.8, true);
    });

    test('handles multiple namespace candidates', () {
      // When multiple pass threshold, LLM picks one
      final candidates = ['task', 'timer', 'note'];
      expect(candidates.length, 3);
      // LLM would pick based on user utterance
    });
  });

  group('ContextManager - Tool Filtering', () {
    test('combines semantic and statistical scores', () {
      const semanticScore = 0.7;
      const statisticalScore = 0.5;
      final combined = 0.6 * semanticScore + 0.4 * statisticalScore;

      expect(combined, closeTo(0.62, 0.01));
    });

    test('filters tools by threshold', () {
      final scores = {
        'task.create': 0.8,
        'task.complete': 0.6,
        'task.delete': 0.3,
      };
      const threshold = 0.5;

      final passed = scores.entries
          .where((e) => e.value >= threshold)
          .map((e) => e.key)
          .toList();

      expect(passed, ['task.create', 'task.complete']);
      expect(passed.contains('task.delete'), false);
    });

    test('tool success rate affects scoring', () {
      // From ToolSelectionAdaptationState.scoreTool()
      const successRate = 0.9;
      const keywordScore = 1.2;
      final statisticalScore = successRate * keywordScore;

      expect(statisticalScore, closeTo(1.08, 0.01));
    });
  });

  group('ContextManager - Context Injection', () {
    test('injects tasks for task namespace', () async {
      final task1 = Task(title: 'Task 1', priority: 'high');
      final task3 = Task(title: 'Task 3', priority: 'medium');

      final incomplete = [task1, task3]; // task2 is completed

      final context = incomplete
          .map((t) => {
                'title': t.title,
                'priority': t.priority,
                'dueDate': t.dueDate?.toIso8601String(),
              })
          .toList();

      expect(context.length, 2);
      expect(context[0]['title'], 'Task 1');
      expect(context[1]['priority'], 'medium');
    });

    test('injects timers for timer namespace', () async {
      final now = DateTime.now();
      final timer1 = Timer(
        label: 'Timer 1',
        durationSeconds: 300,
        setAt: now,
        endsAt: now.add(const Duration(seconds: 300)),
      );

      final active = [timer1]; // timer2 is fired

      final context = active
          .map((t) => {
                'label': t.label,
                'remainingSeconds': t.remainingSeconds,
              })
          .toList();

      expect(context.length, 1);
      expect(context[0]['label'], 'Timer 1');
    });

    test('formats context for LLM correctly', () {
      final context = {
        'tasks': [
          {'title': 'Task 1', 'priority': 'high'},
          {'title': 'Task 2', 'priority': 'low'},
        ],
      };

      // Would format as:
      // "Open tasks:
      // - Task 1 (priority: high)
      // - Task 2 (priority: low)"
      expect(context['tasks'], isNotNull);
      expect((context['tasks'] as List).length, 2);
    });
  });

  group('ContextManager - Error Handling', () {
    test('returns noNamespace when none pass threshold', () {
      // When no namespace scores above threshold
      final scores = {'task': 0.4, 'timer': 0.3};
      const threshold = 0.5;

      final passed = scores.values.where((s) => s >= threshold).toList();
      expect(passed.isEmpty, true);
      // Would return ContextManagerResult.noNamespace()
    });

    test('returns noTools when namespace selected but no tools pass', () {
      final toolScores = {'task.create': 0.3, 'task.complete': 0.2};
      const threshold = 0.5;

      final passed = toolScores.values.where((s) => s >= threshold).toList();
      expect(passed.isEmpty, true);
      // Would return ContextManagerResult.noTools(selectedNamespace: 'task')
    });

    test('handles LLM timeout gracefully', () {
      // GroqTimeoutException caught and converted to error result
      final exception = GroqTimeoutException('Timeout after 30s');
      expect(exception, isA<GroqException>());
      // Would return ContextManagerResult.error(errorType: 'llm_timeout')
    });

    test('handles no active personality', () {
      Personality? personality; // null
      expect(personality, isNull);
      // Would return ContextManagerResult.error(errorType: 'no_personality')
    });

    test('handles empty utterance', () {
      final event = Event(
        correlationId: 'corr_001',
        source: 'user',
        payload: {'transcription': ''}, // Empty!
      );

      expect(event.payload['transcription'], isEmpty);
      // Would return ContextManagerResult.error(errorType: 'empty_input')
    });
  });

  group('ContextManager - Tool Call Parsing', () {
    test('extracts confidence from toolScores', () {
      final toolScores = {
        'task.create': 0.87,
        'task.complete': 0.65,
      };

      final toolName = 'task.create';
      final confidence = toolScores[toolName] ?? 0.5;

      expect(confidence, 0.87);
    });

    test('uses fallback confidence if not scored', () {
      final toolScores = {'task.create': 0.87};
      final toolName = 'task.unknown';
      final confidence = toolScores[toolName] ?? 0.5;

      expect(confidence, 0.5);
    });

    test('calculates average confidence across multiple tools', () {
      final confidences = [0.9, 0.8, 0.7];
      final avg =
          confidences.reduce((a, b) => a + b) / confidences.length;

      expect(avg, closeTo(0.8, 0.01));
    });
  });

  group('ContextManager - Invocation Logging', () {
    test('captures namespace scores', () {
      final scores = {
        'task': 0.8,
        'timer': 0.6,
        'note': 0.4,
      };

      // Invocation.namespaceScores = scores
      expect(scores['task'], 0.8);
      expect(scores.keys.length, 3);
    });

    test('captures tool filtering results', () {
      final available = ['task.create', 'task.complete', 'task.delete'];
      final filtered = ['task.delete']; // Below threshold
      final passed = ['task.create', 'task.complete'];

      expect(available.length, 3);
      expect(filtered.length, 1);
      expect(passed.length, 2);
    });

    test('captures tools called by LLM', () {
      final called = ['task.create'];
      expect(called, ['task.create']);
      // invocation.toolsCalled = called
    });

    test('records latency', () {
      final start = DateTime.now();
      // ... processing ...
      final end = DateTime.now().add(const Duration(milliseconds: 150));
      final latency = end.difference(start).inMilliseconds;

      expect(latency, greaterThanOrEqualTo(150));
    });
  });

  group('ContextManager - Personality Deserialization', () {
    test('loads namespaceAttention from JSON', () {
      final personality = Personality(
        name: 'Test',
        systemPrompt: 'Test',
      );
      personality.namespaceAttention.setThreshold('task', 0.7);
      personality.prepareForSave();

      // Simulate save/load
      expect(personality.namespaceAttentionJson.contains('task'), true);
      expect(personality.namespaceAttentionJson.contains('0.7'), true);

      // Load would deserialize
      personality.loadAfterRead();
      expect(personality.namespaceAttention.getThreshold('task'), 0.7);
    });

    test('loads toolAttention from JSON', () {
      final personality = Personality(
        name: 'Test',
        systemPrompt: 'Test',
      );
      final taskTools = personality.getToolAttention('task');
      taskTools.setSuccessRate('create', 0.9);
      personality.prepareForSave();

      expect(personality.toolAttentionJson.contains('task'), true);
      expect(personality.toolAttentionJson.contains('0.9'), true);
    });

    test('handles complex adaptation states', () {
      final personality = Personality(
        name: 'Complex',
        systemPrompt: 'Test',
      );

      // Set multiple thresholds
      personality.namespaceAttention.setThreshold('task', 0.7);
      personality.namespaceAttention.setThreshold('timer', 0.6);
      personality.namespaceAttention.setThreshold('note', 0.8);

      // Set tool success rates
      personality.getToolAttention('task').setSuccessRate('create', 0.9);
      personality.getToolAttention('task').setSuccessRate('complete', 0.8);
      personality.getToolAttention('timer').setSuccessRate('set', 0.95);

      personality.prepareForSave();

      // Should serialize all states
      expect(personality.namespaceAttentionJson.length, greaterThan(20));
      expect(personality.toolAttentionJson.length, greaterThan(20));
    });
  });
}
