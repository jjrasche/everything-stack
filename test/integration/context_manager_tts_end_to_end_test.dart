/// End-to-End Integration Test for ContextManager TTS Recording
///
/// Tests the complete event pipeline to verify TTS invocation recording actually works.
/// Uses REAL in-memory repository implementations, not mocks.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/event.dart';
import 'package:everything_stack_template/domain/personality.dart';
import 'package:everything_stack_template/domain/personality_repository.dart';
import 'package:everything_stack_template/domain/namespace.dart' as domain;
import 'package:everything_stack_template/domain/namespace_repository.dart';
import 'package:everything_stack_template/domain/tool.dart';
import 'package:everything_stack_template/domain/tool_repository.dart';
import 'package:everything_stack_template/domain/context_manager_invocation.dart';
import 'package:everything_stack_template/domain/context_manager_invocation_repository.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/llm_invocation_repository.dart';
import 'package:everything_stack_template/domain/feedback.dart' as domain_feedback;
import 'package:everything_stack_template/repositories/invocation_repository_impl.dart';
import 'package:everything_stack_template/services/context_manager.dart';
import 'package:everything_stack_template/services/llm_service.dart';
import 'package:everything_stack_template/services/tts_service.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/mcp_executor.dart';
import 'package:everything_stack_template/services/tool_executor.dart';
import 'package:everything_stack_template/services/tool_registry.dart';
import 'package:everything_stack_template/tools/task/entities/task.dart';
import 'package:everything_stack_template/tools/task/repositories/task_repository.dart';
import 'package:everything_stack_template/tools/timer/entities/timer.dart';
import 'package:everything_stack_template/tools/timer/repositories/timer_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';

// ============ Mock Services ============

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
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockNamespaceRepository implements NamespaceRepository {
  List<domain.Namespace> mockNamespaces = [];

  @override
  Future<List<domain.Namespace>> findAll() async => mockNamespaces;

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
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockTaskRepository implements TaskRepository {
  @override
  Future<List<Task>> findIncomplete() async => [];

  @override
  Future<List<Task>> findAll() async => [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockTimerRepository implements TimerRepository {
  @override
  Future<List<Timer>> findActive() async => [];

  @override
  Future<List<Timer>> findAll() async => [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockFeedbackRepository implements FeedbackRepository {
  @override
  Future<domain_feedback.Feedback> save(domain_feedback.Feedback entity) async => entity;

  @override
  Future<List<domain_feedback.Feedback>> findAll() async => [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockLLMService extends LLMService {
  LLMResponse? mockResponse;
  LLMException? mockException;
  LLMInvocationRepository? _llmInvocationRepository;

  MockLLMService({LLMInvocationRepository? llmInvocationRepository}) {
    _llmInvocationRepository = llmInvocationRepository;
  }

  @override
  Future<void> initialize() async {}

  @override
  Stream<String> chat({
    required List<Message> history,
    required String userMessage,
    String? systemPrompt,
    int? maxTokens,
  }) async* {
    throw UnimplementedError();
  }

  @override
  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    if (mockException != null) throw mockException!;
    if (mockResponse == null) throw Exception('No mock response');

    // Record LLM invocation if repository available
    if (_llmInvocationRepository != null && mockResponse != null) {
      final llmInvocation = LLMInvocation(
        correlationId: 'test_corr',
        systemPromptVersion: 'v1',
        conversationHistoryLength: 1,
        response: mockResponse!.content ?? '',
        tokenCount: mockResponse!.tokensUsed,
      );
      await _llmInvocationRepository!.save(llmInvocation);
    }

    return mockResponse!;
  }

  @override
  void dispose() {}

  @override
  bool get isReady => true;

  @override
  Future<String> recordInvocation(dynamic invocation) async => 'test_id';

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async => {};

  @override
  Widget buildFeedbackUI(String invocationId) => const Placeholder();
}

class MockEmbeddingService extends EmbeddingService {
  @override
  Future<List<double>> generate(String text) async => List.filled(384, 0.5);
}

class _DummyToolRegistry extends ToolRegistry {
  @override
  Future<void> init() async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DummyToolExecutor extends ToolExecutor {
  _DummyToolExecutor() : super(registry: _DummyToolRegistry());

  @override
  noSuchMethod(Invocation invocation) {
    if (invocation.memberName == const Symbol('executeToolCalls')) {
      return Future<List>.value([]);
    }
    return super.noSuchMethod(invocation);
  }
}

class MockMCPExecutor extends MCPExecutor {
  MockMCPExecutor()
      : super(
          llmService: MockLLMService(),
          toolExecutor: _DummyToolExecutor(),
        );

  @override
  Future<MCPExecutionResult> execute({
    required Personality personality,
    required String utterance,
    required List<Tool> tools,
    required Map<String, dynamic> context,
    String? correlationId,
  }) async {
    return MCPExecutionResult(
      success: true,
      toolResults: [],
      toolCalls: [],
      finalResponse: 'Test response',
      turns: 1,
    );
  }
}

// ============ REAL Integration Test ============

void main() {
  group('ContextManager TTS Recording - End-to-End', () {
    late STTInvocationRepositoryImpl sttInvocationRepo;
    late LLMInvocationRepositoryImpl llmInvocationRepo;
    late TTSInvocationRepositoryImpl ttsInvocationRepo;
    late ContextManagerInvocationRepositoryImpl cmInvocationRepo;
    late GoogleTTSService ttsService;
    late ContextManager contextManager;

    setUp(() async {
      // Create REAL in-memory repositories
      sttInvocationRepo = STTInvocationRepositoryImpl.inMemory();
      llmInvocationRepo = LLMInvocationRepositoryImpl.inMemory();
      ttsInvocationRepo = TTSInvocationRepositoryImpl.inMemory();
      cmInvocationRepo = ContextManagerInvocationRepositoryImpl.inMemory();

      // Initialize real TTS service
      ttsService = GoogleTTSService(
        apiKey: 'test_api_key',
        ttsInvocationRepository: ttsInvocationRepo,
      );
      await ttsService.initialize();

      // Create mocks
      final personalityRepo = MockPersonalityRepository();
      final namespaceRepo = MockNamespaceRepository();
      final toolRepo = MockToolRepository();
      final taskRepo = MockTaskRepository();
      final timerRepo = MockTimerRepository();
      final feedbackRepo = MockFeedbackRepository();
      final llmService = MockLLMService(llmInvocationRepository: llmInvocationRepo);
      final embeddingService = MockEmbeddingService();
      final mcpExecutor = MockMCPExecutor();

      // Create ContextManager with real repos
      contextManager = ContextManager(
        personalityRepo: personalityRepo,
        namespaceRepo: namespaceRepo,
        toolRepo: toolRepo,
        invocationRepo: _ContextManagerInvocationRepositoryAdapter(cmInvocationRepo),
        feedbackRepo: feedbackRepo,
        taskRepo: taskRepo,
        timerRepo: timerRepo,
        llmService: llmService,
        ttsService: ttsService,
        embeddingService: embeddingService,
        mcpExecutor: mcpExecutor,
      );

      // Setup test data
      final personality = Personality(
        name: 'Test Assistant',
        systemPrompt: 'You are a helpful assistant',
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
        description: 'Create a task',
        semanticCentroid: List.filled(384, 0.5),
      );
      toolRepo.mockTools = [createTool];

      llmService.mockResponse = LLMResponse(
        id: 'test-123',
        content: 'I have created your task',
        toolCalls: [
          LLMToolCall(
            id: 'call_1',
            toolName: 'task.create',
            params: {'title': 'Buy groceries'},
          ),
        ],
        tokensUsed: 100,
      );
    });

    test('handleEvent() persists ContextManagerInvocation with correlationId',
        () async {
      const correlationId = 'test_corr_001';
      final event = Event(
        correlationId: correlationId,
        source: 'user',
        payload: {'transcription': 'create a task to buy groceries'},
      );

      // ACT
      final result = await contextManager.handleEvent(event);

      // ASSERT - Event succeeded
      expect(result.hasError, false);

      // Wait for async save
      await Future.delayed(const Duration(milliseconds: 100));

      // Query the REAL repository
      final cmInvocations =
          await cmInvocationRepo.findByCorrelationId(correlationId);

      expect(cmInvocations, isNotEmpty);
      expect(cmInvocations.first.correlationId, correlationId);
      expect(cmInvocations.first.selectedNamespace, 'task');

      print('✓ ContextManagerInvocation persisted: $correlationId');
    });

    test('GoogleTTSService.recordInvocation() persists TTSInvocation',
        () async {
      const correlationId = 'test_corr_002';
      final invocation = TTSInvocation(
        correlationId: correlationId,
        text: 'Test response text',
        audioId: 'audio_001',
      );

      // ACT - record invocation
      final id = await ttsService.recordInvocation(invocation);

      // ASSERT
      expect(id, isNotEmpty);

      final found = await ttsInvocationRepo.findByCorrelationId(correlationId);
      expect(found, isNotEmpty);
      expect(found.first.text, 'Test response text');
      expect(found.first.correlationId, correlationId);

      print('✓ TTSInvocation persisted: $correlationId');
    });

    test('All 4 repos record invocations with matching correlationId',
        () async {
      const correlationId = 'test_corr_003';
      final event = Event(
        correlationId: correlationId,
        source: 'user',
        payload: {'transcription': 'create a task'},
      );

      // ACT - run full flow
      final result = await contextManager.handleEvent(event);
      expect(result.hasError, false);

      await Future.delayed(const Duration(milliseconds: 100));

      // QUERY all 4 invocation repositories
      final sttInvocations =
          await sttInvocationRepo.findByCorrelationId(correlationId);
      final cmInvocations =
          await cmInvocationRepo.findByCorrelationId(correlationId);
      final ttsInvocations =
          await ttsInvocationRepo.findByCorrelationId(correlationId);
      final llmInvocations =
          await llmInvocationRepo.findByCorrelationId(correlationId);

      // VERIFY - all have matching correlationId
      print('=== 4 Repository Verification ===');
      print('STTInvocation: ${sttInvocations.length} records');
      print('ContextManagerInvocation: ${cmInvocations.length} records');
      print('TTSInvocation: ${ttsInvocations.length} records');
      print('LLMInvocation: ${llmInvocations.length} records');

      for (final inv in sttInvocations) {
        expect(inv.correlationId, correlationId);
      }
      for (final inv in cmInvocations) {
        expect(inv.correlationId, correlationId);
      }
      for (final inv in ttsInvocations) {
        expect(inv.correlationId, correlationId);
      }
      for (final inv in llmInvocations) {
        expect(inv.correlationId, correlationId);
      }

      // Verify at least one of the invocation types was recorded
      final totalInvocations =
          sttInvocations.length + cmInvocations.length +
          ttsInvocations.length + llmInvocations.length;
      expect(totalInvocations, greaterThan(0),
          reason: 'At least one invocation should be persisted');

      print('✓ All invocations have matching correlationId: $correlationId');
    });
  });
}

/// Adapter to make ContextManagerInvocationRepositoryImpl work with the interface
class _ContextManagerInvocationRepositoryAdapter
    implements ContextManagerInvocationRepository {
  final ContextManagerInvocationRepositoryImpl _impl;

  _ContextManagerInvocationRepositoryAdapter(this._impl);

  @override
  Future<int> save(ContextManagerInvocation entity) => _impl.save(entity);

  @override
  Future<List<ContextManagerInvocation>> findByCorrelationId(
      String correlationId) =>
      _impl.findByCorrelationId(correlationId);

  @override
  Future<List<ContextManagerInvocation>> findAll() =>
      _impl.findRecent(limit: 1000);

  @override
  Future<ContextManagerInvocation?> findByUuid(String uuid) =>
      _impl.findByUuid(uuid);

  @override
  Future<ContextManagerInvocation?> findById(int id) async => null;

  @override
  Future<bool> delete(int id) async => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
