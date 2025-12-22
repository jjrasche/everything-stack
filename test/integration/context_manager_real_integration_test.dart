/// Real Integration Tests for ContextManager
/// Tests actual handleEvent() execution with mocked dependencies

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/event.dart';
import 'package:everything_stack_template/domain/personality.dart';
import 'package:everything_stack_template/domain/personality_repository.dart';
import 'package:everything_stack_template/domain/namespace.dart' as domain;
import 'package:everything_stack_template/domain/namespace_repository.dart';
import 'package:everything_stack_template/domain/tool.dart';
import 'package:everything_stack_template/domain/tool_repository.dart';
import 'package:everything_stack_template/tools/task/entities/task.dart';
import 'package:everything_stack_template/tools/task/repositories/task_repository.dart';
import 'package:everything_stack_template/tools/timer/entities/timer.dart';
import 'package:everything_stack_template/tools/timer/repositories/timer_repository.dart';
import 'package:everything_stack_template/domain/context_manager_invocation.dart';
import 'package:everything_stack_template/domain/context_manager_invocation_repository.dart';
import 'package:everything_stack_template/services/context_manager.dart';
import 'package:everything_stack_template/services/llm_service.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

// ============ Mock Implementations ============

class MockPersonalityRepository implements PersonalityRepository {
  Personality? mockActivePersonality;

  @override
  Future<Personality?> getActive() async {
    if (mockActivePersonality != null) {
      mockActivePersonality!.loadAfterRead();
    }
    return mockActivePersonality;
  }

  @override
  Future<List<Personality>> findAll() async => [];

  @override
  Future<int> save(Personality entity) async => 1;

  @override
  Future<bool> delete(int id) async => true;

  @override
  Future<Personality?> findById(int id) async => null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockNamespaceRepository implements NamespaceRepository {
  List<domain.Namespace> mockNamespaces = [];

  @override
  Future<List<domain.Namespace>> findAll() async => mockNamespaces;

  @override
  Future<int> save(domain.Namespace entity) async => 1;

  @override
  Future<bool> delete(int id) async => true;

  @override
  Future<domain.Namespace?> findById(int id) async => null;

  @override
  Future<domain.Namespace?> findByName(String name) async {
    try {
      return mockNamespaces.firstWhere((ns) => ns.name == name);
    } catch (e) {
      return null;
    }
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockToolRepository implements ToolRepository {
  List<Tool> mockTools = [];

  @override
  Future<List<Tool>> findByNamespace(String namespaceId) async {
    return mockTools.where((t) => t.namespaceId == namespaceId).toList();
  }

  @override
  Future<List<Tool>> findAll() async => mockTools;

  @override
  Future<int> save(Tool entity) async => 1;

  @override
  Future<bool> delete(int id) async => true;

  @override
  Future<Tool?> findById(int id) async => null;

  @override
  Future<Tool?> findByFullName(String fullName) async {
    try {
      return mockTools.firstWhere((t) => t.fullName == fullName);
    } catch (e) {
      return null;
    }
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockTaskRepository implements TaskRepository {
  List<Task> mockTasks = [];

  @override
  Future<List<Task>> findIncomplete() async {
    return mockTasks.where((t) => !t.completed).toList();
  }

  @override
  Future<List<Task>> findAll() async => mockTasks;

  @override
  Future<int> save(Task entity) async => 1;

  @override
  Future<bool> delete(int id) async => true;

  @override
  Future<Task?> findById(int id) async => null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockTimerRepository implements TimerRepository {
  List<Timer> mockTimers = [];

  @override
  Future<List<Timer>> findActive() async {
    return mockTimers.where((t) => t.isActive).toList();
  }

  @override
  Future<List<Timer>> findAll() async => mockTimers;

  @override
  Future<int> save(Timer entity) async => 1;

  @override
  Future<bool> delete(int id) async => true;

  @override
  Future<Timer?> findById(int id) async => null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockContextManagerInvocationRepository
    implements ContextManagerInvocationRepository {
  final savedInvocations = <ContextManagerInvocation>[];

  @override
  Future<int> save(ContextManagerInvocation entity) async {
    savedInvocations.add(entity);
    return 1;
  }

  @override
  Future<List<ContextManagerInvocation>> findAll() async => savedInvocations;

  @override
  Future<bool> delete(int id) async => true;

  @override
  Future<ContextManagerInvocation?> findById(int id) async => null;

  @override
  Future<List<ContextManagerInvocation>> findByCorrelationId(
      String correlationId) async {
    return savedInvocations
        .where((inv) => inv.correlationId == correlationId)
        .toList();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockLLMService extends LLMService {
  LLMResponse? mockResponse;
  LLMException? mockException;
  List<Map<String, dynamic>> lastMessages = [];
  List<LLMTool>? lastTools;

  @override
  Future<void> initialize() async {
    // No-op for testing
  }

  @override
  Stream<String> chat({
    required List<Message> history,
    required String userMessage,
    String? systemPrompt,
    int? maxTokens,
  }) async* {
    throw UnimplementedError('Streaming not used in tests');
  }

  @override
  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    // Capture call details for verification
    lastMessages = messages;
    lastTools = tools;

    if (mockException != null) {
      throw mockException!;
    }
    if (mockResponse == null) {
      throw Exception('MockLLMService: No response configured');
    }
    return mockResponse!;
  }

  @override
  void dispose() {
    // No-op for testing
  }

  @override
  bool get isReady => true;
}

class MockEmbeddingService extends EmbeddingService {
  List<double> mockEmbedding = List.filled(384, 0.5);

  @override
  Future<List<double>> generate(String text) async => mockEmbedding;
}

// ============ Real Integration Tests ============

void main() {
  late MockPersonalityRepository personalityRepo;
  late MockNamespaceRepository namespaceRepo;
  late MockToolRepository toolRepo;
  late MockTaskRepository taskRepo;
  late MockTimerRepository timerRepo;
  late MockContextManagerInvocationRepository invocationRepo;
  late MockLLMService llmService;
  late MockEmbeddingService embeddingService;
  late ContextManager contextManager;

  setUp(() {
    personalityRepo = MockPersonalityRepository();
    namespaceRepo = MockNamespaceRepository();
    toolRepo = MockToolRepository();
    taskRepo = MockTaskRepository();
    timerRepo = MockTimerRepository();
    invocationRepo = MockContextManagerInvocationRepository();
    llmService = MockLLMService();
    embeddingService = MockEmbeddingService();

    contextManager = ContextManager(
      personalityRepo: personalityRepo,
      namespaceRepo: namespaceRepo,
      toolRepo: toolRepo,
      taskRepo: taskRepo,
      timerRepo: timerRepo,
      invocationRepo: invocationRepo,
      llmService: llmService,
      embeddingService: embeddingService,
    );
  });

  group('ContextManager Real Integration - Success Flow', () {
    test('Event "create task" → selects task namespace → calls task.create',
        () async {
      // ARRANGE
      // 1. Setup personality with thresholds
      final personality = Personality(
        name: 'Task Planner',
        systemPrompt: 'You help users manage tasks',
      );
      personality.namespaceAttention.setThreshold('task', 0.6);
      personality.namespaceAttention.setThreshold('timer', 0.7);

      final taskTools = personality.getToolAttention('task');
      taskTools.setSuccessRate('create', 0.9);
      taskTools.setKeywordWeight('create', 'add', 1.5);

      personality.prepareForSave();
      personalityRepo.mockActivePersonality = personality;

      // 2. Setup namespaces
      final taskNs = domain.Namespace(
        name: 'task',
        description: 'Manage tasks and to-dos',
        keywords: ['task', 'todo', 'remind'],
        semanticCentroid: List.filled(384, 0.5), // Will match embedding (0.5)
      );
      namespaceRepo.mockNamespaces = [taskNs];

      // 3. Setup tools
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
        semanticCentroid: List.filled(384, 0.5), // High match
      );
      toolRepo.mockTools = [createTool];

      // 4. Setup tasks for context injection
      taskRepo.mockTasks = [
        Task(title: 'Existing task', priority: 'high'),
      ];

      // 5. Setup embedding (will match 0.5 centroid)
      embeddingService.mockEmbedding = List.filled(384, 0.5);

      // 6. Setup LLM response
      llmService.mockResponse = LLMResponse(
        id: 'chatcmpl-123',
        content: null,
        toolCalls: [
          LLMToolCall(
            id: 'call_abc123',
            toolName: 'task.create',
            params: {'title': 'Buy groceries', 'priority': 'high'},
          ),
        ],
        tokensUsed: 150,
      );

      // 7. Create event
      final event = Event(
        correlationId: 'corr_001',
        source: 'user',
        payload: {'transcription': 'create a task to buy groceries'},
      );

      // ACT
      final result = await contextManager.handleEvent(event);

      // ASSERT
      // 1. No error
      expect(result.hasError, false, reason: 'Should not have error');
      expect(result.error, isNull);

      // 2. Namespace selected correctly
      expect(result.selectedNamespace, 'task');

      // 3. Tool called
      expect(result.hasToolCalls, true);
      expect(result.toolCalls.length, 1);
      expect(result.toolCalls.first.toolName, 'task.create');
      expect(result.toolCalls.first.params['title'], 'Buy groceries');
      expect(result.toolCalls.first.params['priority'], 'high');

      // 4. Confidence is derived from scores (not hardcoded)
      expect(result.confidence, greaterThan(0.0));
      expect(result.toolCalls.first.confidence, greaterThan(0.0));

      // 5. Context was injected
      expect(result.assembledContext['tasks'], isNotNull);
      expect(result.assembledContext['tasks'].length, 1);

      // 6. Invocation was logged
      expect(invocationRepo.savedInvocations.length, 1);
      final invocation = invocationRepo.savedInvocations.first;
      expect(invocation.correlationId, 'corr_001');
      expect(invocation.selectedNamespace, 'task');
      expect(invocation.toolsCalled, ['task.create']);
      expect(invocation.confidence, greaterThan(0.0));

      // 7. LLM was called with correct tools
      expect(llmService.lastTools, isNotNull);
      expect(llmService.lastTools!.length, 1);
      expect(llmService.lastTools!.first.name, 'task.create');
    });

    test('Event "set timer" → selects timer namespace → calls timer.set',
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

      personality.prepareForSave();
      personalityRepo.mockActivePersonality = personality;

      final timerNs = domain.Namespace(
        name: 'timer',
        description: 'Set timers and alarms',
        semanticCentroid: List.filled(384, 0.5),
      );
      namespaceRepo.mockNamespaces = [timerNs];

      final setTool = Tool(
        name: 'set',
        namespaceId: 'timer',
        description: 'Set a timer',
        parameters: {
          'type': 'object',
          'properties': {
            'label': {'type': 'string'},
            'duration': {'type': 'integer'},
          },
          'required': ['duration'],
        },
        semanticCentroid: List.filled(384, 0.5),
      );
      toolRepo.mockTools = [setTool];

      embeddingService.mockEmbedding = List.filled(384, 0.5);

      llmService.mockResponse = LLMResponse(
        id: 'chatcmpl-456',
        content: null,
        toolCalls: [
          LLMToolCall(
            id: 'call_xyz789',
            toolName: 'timer.set',
            params: {'label': '5 min break', 'duration': 300},
          ),
        ],
        tokensUsed: 80,
      );

      final event = Event(
        correlationId: 'corr_002',
        source: 'user',
        payload: {'transcription': 'set a timer for 5 minutes'},
      );

      // ACT
      final result = await contextManager.handleEvent(event);

      // ASSERT
      expect(result.hasError, false);
      expect(result.selectedNamespace, 'timer');
      expect(result.hasToolCalls, true);
      expect(result.toolCalls.first.toolName, 'timer.set');
      expect(result.toolCalls.first.params['duration'], 300);
    });
  });

  group('ContextManager Real Integration - Error Cases', () {
    test('No namespace passes threshold → returns noNamespace error',
        () async {
      // ARRANGE
      final personality = Personality(
        name: 'Strict',
        systemPrompt: 'Test',
      );
      // Very high thresholds
      personality.namespaceAttention.setThreshold('task', 0.9);
      personality.namespaceAttention.setThreshold('timer', 0.9);

      personality.prepareForSave();
      personalityRepo.mockActivePersonality = personality;

      final taskNs = domain.Namespace(
        name: 'task',
        description: 'Tasks',
        // Create orthogonal vector (0.5 in first half, -0.5 in second half)
        semanticCentroid:
            List.generate(384, (i) => i < 192 ? 0.5 : -0.5),
      );
      namespaceRepo.mockNamespaces = [taskNs];

      // Embedding opposite direction (-0.5 in first half, 0.5 in second half)
      // This gives negative cosine similarity, failing threshold
      embeddingService.mockEmbedding =
          List.generate(384, (i) => i < 192 ? -0.5 : 0.5);

      final event = Event(
        correlationId: 'corr_003',
        source: 'user',
        payload: {'transcription': 'hello'},
      );

      // ACT
      final result = await contextManager.handleEvent(event);

      // ASSERT
      expect(result.hasError, true);
      expect(result.errorType, 'no_namespace');
      expect(result.selectedNamespace, isNull);
      expect(result.toolCalls, isEmpty);
      expect(result.confidence, 0.0);

      // Invocation was still logged
      expect(invocationRepo.savedInvocations.length, 1);
      expect(invocationRepo.savedInvocations.first.errorType, isNull);
    });

    test('Namespace selected but no tools pass → returns noTools error',
        () async {
      // ARRANGE
      final personality = Personality(
        name: 'Test',
        systemPrompt: 'Test',
      );
      personality.namespaceAttention.setThreshold('task', 0.6);
      personality.prepareForSave();
      personalityRepo.mockActivePersonality = personality;

      // Namespace centroid matches embedding (will pass threshold)
      final taskNs = domain.Namespace(
        name: 'task',
        description: 'Tasks',
        semanticCentroid: List.filled(384, 0.7), // Same direction as embedding
      );
      namespaceRepo.mockNamespaces = [taskNs];

      // Tool centroid opposite to embedding (will fail threshold)
      final createTool = Tool(
        name: 'create',
        namespaceId: 'task',
        description: 'Create task',
        // Opposite direction: negative values
        semanticCentroid: List.filled(384, -0.7),
      );
      toolRepo.mockTools = [createTool];

      // Embedding: all positive
      // - Namespace: cosine([0.7, 0.7, ...], [0.7, 0.7, ...]) = 1.0 ✓ passes 0.6
      // - Tool: cosine([0.7, 0.7, ...], [-0.7, -0.7, ...]) = -1.0
      //   combined = 0.6 * (-1.0) + 0.4 * 0 = -0.6 ✗ fails 0.5
      embeddingService.mockEmbedding = List.filled(384, 0.7);

      final event = Event(
        correlationId: 'corr_004',
        source: 'user',
        payload: {'transcription': 'do something'},
      );

      // ACT
      final result = await contextManager.handleEvent(event);

      // ASSERT
      expect(result.hasError, true);
      expect(result.errorType, 'no_tools');
      expect(result.selectedNamespace, 'task');
      expect(result.toolCalls, isEmpty);
    });

    test('LLM timeout → returns llm_timeout error', () async {
      // ARRANGE
      final personality = Personality(
        name: 'Test',
        systemPrompt: 'Test',
      );
      personality.namespaceAttention.setThreshold('task', 0.6);
      personality.prepareForSave();
      personalityRepo.mockActivePersonality = personality;

      final taskNs = domain.Namespace(
        name: 'task',
        description: 'Task management',
        semanticCentroid: List.filled(384, 0.5),
      );
      namespaceRepo.mockNamespaces = [taskNs];

      final createTool = Tool(
        name: 'create',
        namespaceId: 'task',
        description: 'Create',
        semanticCentroid: List.filled(384, 0.5),
      );
      toolRepo.mockTools = [createTool];

      embeddingService.mockEmbedding = List.filled(384, 0.5);

      // Configure LLM to throw timeout
      llmService.mockException = LLMTimeoutException('Timeout after 30s');

      final event = Event(
        correlationId: 'corr_005',
        source: 'user',
        payload: {'transcription': 'create task'},
      );

      // ACT
      final result = await contextManager.handleEvent(event);

      // ASSERT
      expect(result.hasError, true);
      expect(result.errorType, 'llm_timeout');
      expect(result.error, contains('Timeout'));
    });

    test('No active personality → returns no_personality error', () async {
      // ARRANGE
      personalityRepo.mockActivePersonality = null; // No personality!

      final event = Event(
        correlationId: 'corr_006',
        source: 'user',
        payload: {'transcription': 'do something'},
      );

      // ACT
      final result = await contextManager.handleEvent(event);

      // ASSERT
      expect(result.hasError, true);
      expect(result.errorType, 'no_personality');
    });

    test('Empty utterance → returns empty_input error', () async {
      // ARRANGE
      final personality = Personality(name: 'Test', systemPrompt: 'Test');
      personalityRepo.mockActivePersonality = personality;

      final event = Event(
        correlationId: 'corr_007',
        source: 'user',
        payload: {'transcription': ''}, // Empty!
      );

      // ACT
      final result = await contextManager.handleEvent(event);

      // ASSERT
      expect(result.hasError, true);
      expect(result.errorType, 'empty_input');
    });
  });

  group('ContextManager Real Integration - Context Injection', () {
    test('Task namespace injects incomplete tasks into context', () async {
      // ARRANGE
      final personality = Personality(
        name: 'Task Helper',
        systemPrompt: 'Help with tasks',
      );
      personality.namespaceAttention.setThreshold('task', 0.6);
      personality.prepareForSave();
      personalityRepo.mockActivePersonality = personality;

      final taskNs = domain.Namespace(
        name: 'task',
        description: 'Task management',
        semanticCentroid: List.filled(384, 0.5),
      );
      namespaceRepo.mockNamespaces = [taskNs];

      final listTool = Tool(
        name: 'list',
        namespaceId: 'task',
        description: 'List tasks',
        semanticCentroid: List.filled(384, 0.5),
      );
      toolRepo.mockTools = [listTool];

      // Add 2 incomplete tasks, 1 completed
      taskRepo.mockTasks = [
        Task(title: 'Task 1', priority: 'high'),
        Task(title: 'Task 2', priority: 'low'),
        Task(title: 'Task 3', priority: 'medium', completed: true),
      ];

      embeddingService.mockEmbedding = List.filled(384, 0.5);

      llmService.mockResponse = LLMResponse(
        id: 'chatcmpl-789',
        content: 'Here are your tasks...',
        toolCalls: [], // No tool calls, just text response
        tokensUsed: 60,
      );

      final event = Event(
        correlationId: 'corr_008',
        source: 'user',
        payload: {'transcription': 'show my tasks'},
      );

      // ACT
      final result = await contextManager.handleEvent(event);

      // ASSERT
      expect(result.hasError, false);
      expect(result.assembledContext['tasks'], isNotNull);

      final tasks = result.assembledContext['tasks'] as List;
      expect(tasks.length, 2, reason: 'Only incomplete tasks should be injected');
      expect(tasks[0]['title'], 'Task 1');
      expect(tasks[1]['title'], 'Task 2');

      // Verify LLM received context
      expect(llmService.lastMessages.length, greaterThan(1));
      final contextMsg = llmService.lastMessages.firstWhere(
        (msg) => msg['content'].toString().contains('Open tasks:'),
        orElse: () => {},
      );
      expect(contextMsg, isNotEmpty);
    });
  });
}
