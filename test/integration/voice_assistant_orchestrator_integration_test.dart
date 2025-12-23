/// VoiceAssistantOrchestrator Integration Test
///
/// Tests the complete voice assistant pipeline:
/// Audio stream → STT → ContextManager → LLM → TTS → Result
///
/// Verifies result structure and that the pipeline completes.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:mockito/mockito.dart';

import 'package:everything_stack_template/services/voice_assistant_orchestrator.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/services/tts_service.dart';
import 'package:everything_stack_template/services/llm_service.dart';
import 'package:everything_stack_template/services/mcp_executor.dart';
import 'package:everything_stack_template/services/context_manager.dart';
import 'package:everything_stack_template/services/context_manager_result.dart';
import 'package:everything_stack_template/domain/event.dart';
import 'package:everything_stack_template/domain/turn.dart';
import 'package:everything_stack_template/domain/turn_repository.dart';
import 'package:everything_stack_template/domain/stt_invocation_repository.dart';
import 'package:everything_stack_template/domain/llm_invocation_repository.dart';
import 'package:everything_stack_template/domain/tts_invocation_repository.dart';
import 'package:everything_stack_template/domain/invocations.dart';

// ============================================================================
// Mock STT Service
// ============================================================================

class MockSTTService extends Mock implements STTService {
  @override
  Future<void> initialize() async {}

  @override
  bool get isReady => true;

  @override
  void dispose() {}

  @override
  StreamSubscription<String> transcribe({
    required Stream<Uint8List> audio,
    required void Function(String) onTranscript,
    void Function()? onUtteranceEnd,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    // Simulate STT: emit transcript after a short delay, then signal utterance end
    Timer(Duration(milliseconds: 50), () {
      onTranscript('create a task to buy groceries');
      Timer(Duration(milliseconds: 50), () {
        onUtteranceEnd?.call();
      });
    });

    return Stream<String>.empty().listen(null);
  }

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    return const Uuid().v4();
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async =>
      {'status': 'baseline'};

  @override
  Widget buildFeedbackUI(String invocationId) {
    throw UnimplementedError();
  }
}

// ============================================================================
// Mock LLM Service
// ============================================================================

class MockLLMService extends Mock implements LLMService {
  @override
  Future<void> initialize() async {}

  @override
  bool get isReady => true;

  @override
  void dispose() {}

  @override
  Stream<String> chat({
    required List<Message> history,
    required String userMessage,
    String? systemPrompt,
    int? maxTokens,
  }) async* {
    yield 'Response text';
  }

  @override
  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    return LLMResponse(
      id: const Uuid().v4(),
      content: 'Your grocery task has been created',
      toolCalls: [],
      tokensUsed: 150,
    );
  }

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    return const Uuid().v4();
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async =>
      {'status': 'baseline'};

  @override
  Widget buildFeedbackUI(String invocationId) {
    throw UnimplementedError();
  }
}

// ============================================================================
// Mock TTS Service
// ============================================================================

class MockTTSService extends Mock implements TTSService {
  @override
  Future<void> initialize() async {}

  @override
  bool get isReady => true;

  @override
  void dispose() {}

  @override
  Stream<Uint8List> synthesize(
    String text, {
    String? voice,
    String? languageCode,
  }) async* {
    // Return mock audio chunks
    yield Uint8List.fromList([1, 2, 3, 4, 5]);
    yield Uint8List.fromList([6, 7, 8, 9, 10]);
  }

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    return const Uuid().v4();
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async =>
      {'status': 'baseline'};

  @override
  Widget buildFeedbackUI(String invocationId) {
    throw UnimplementedError();
  }
}

// ============================================================================
// Mock Repositories
// ============================================================================

class MockTurnRepository extends Mock implements TurnRepository {
  final List<Turn> _turns = [];

  @override
  Future<int> save(Turn turn) async {
    _turns.add(turn);
    return 1;
  }

  @override
  Future<Turn?> findByUuid(String uuid) async {
    try {
      return _turns.firstWhere((t) => t.uuid == uuid);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Turn?> findByCorrelationId(String correlationId) async {
    try {
      return _turns.firstWhere((t) => t.correlationId == correlationId);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<Turn>> findSuccessful() async =>
      _turns.where((t) => t.result == 'success').toList();

  @override
  Future<List<Turn>> findFailed() async =>
      _turns.where((t) => t.result != 'success').toList();

  @override
  Future<List<Turn>> findFailedInComponent(String component) async =>
      _turns.where((t) => t.failureComponent == component).toList();

  @override
  Future<List<Turn>> findRecent({int limit = 10}) async =>
      _turns.take(limit).toList();

  @override
  Future<bool> delete(String uuid) async {
    _turns.removeWhere((t) => t.uuid == uuid);
    return true;
  }

  @override
  Future<int> count() async => _turns.length;

  @override
  Future<int> deleteAll() async {
    final count = _turns.length;
    _turns.clear();
    return count;
  }

  List<Turn> getAllTurns() => _turns;
}

class MockSTTInvocationRepository extends Mock implements STTInvocationRepository {
  final List<STTInvocation> _invocations = [];

  @override
  Future<int> save(STTInvocation invocation) async {
    _invocations.add(invocation);
    return 1;
  }

  List<STTInvocation> getAll() => _invocations;
}

class MockLLMInvocationRepository extends Mock implements LLMInvocationRepository {
  final List<LLMInvocation> _invocations = [];

  @override
  Future<int> save(LLMInvocation invocation) async {
    _invocations.add(invocation);
    return 1;
  }

  List<LLMInvocation> getAll() => _invocations;
}

class MockTTSInvocationRepository extends Mock implements TTSInvocationRepository {
  final List<TTSInvocation> _invocations = [];

  @override
  Future<int> save(TTSInvocation invocation) async {
    _invocations.add(invocation);
    return 1;
  }

  List<TTSInvocation> getAll() => _invocations;
}

// ============================================================================
// Mock ContextManager
// ============================================================================

class MockContextManager extends Mock implements ContextManager {
  @override
  Future<ContextManagerResult> handleEvent(Event event) async {
    return ContextManagerResult.success(
      selectedNamespace: 'task',
      toolCalls: [],
      confidence: 0.85,
      invocationId: const Uuid().v4(),
      assembledContext: {'event_id': event.correlationId},
    );
  }
}

// ============================================================================
// Mock MCPExecutor
// ============================================================================

class MockMCPExecutor extends Mock implements MCPExecutor {
  @override
  Future<MCPExecutionResult> execute({
    required dynamic personality,
    required String utterance,
    required List<dynamic> tools,
    required Map<String, dynamic> context,
    String? correlationId,
  }) async {
    return MCPExecutionResult(
      success: true,
      toolCalls: [],
      toolResults: [],
      finalResponse: 'Task created successfully',
      turns: 1,
    );
  }
}

// ============================================================================
// Main Test
// ============================================================================

void main() {
  group('VoiceAssistantOrchestrator Integration Tests', () {
    late MockSTTService sttService;
    late MockLLMService llmService;
    late MockTTSService ttsService;
    late MockContextManager contextManager;
    late MockMCPExecutor mcpExecutor;
    late MockTurnRepository turnRepo;
    late MockSTTInvocationRepository sttRepo;
    late MockLLMInvocationRepository llmRepo;
    late MockTTSInvocationRepository ttsRepo;
    late VoiceAssistantOrchestrator orchestrator;

    setUp(() {
      sttService = MockSTTService();
      llmService = MockLLMService();
      ttsService = MockTTSService();
      contextManager = MockContextManager();
      mcpExecutor = MockMCPExecutor();
      turnRepo = MockTurnRepository();
      sttRepo = MockSTTInvocationRepository();
      llmRepo = MockLLMInvocationRepository();
      ttsRepo = MockTTSInvocationRepository();

      orchestrator = VoiceAssistantOrchestrator(
        sttService: sttService,
        contextManager: contextManager,
        llmService: llmService,
        ttsService: ttsService,
        mcpExecutor: mcpExecutor,
        turnRepo: turnRepo,
        sttInvocationRepo: sttRepo,
        llmInvocationRepo: llmRepo,
        ttsInvocationRepo: ttsRepo,
      );
    });

    test(
      'processAudioStream: Full pipeline - audio → transcript → LLM → TTS → result',
      () async {
        // Arrange
        final correlationId = 'test_${const Uuid().v4()}';
        final audioStream = Stream.fromIterable([
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([4, 5, 6]),
        ]);

        // Act
        final result = await orchestrator.processAudioStream(
          audioStream: audioStream,
          correlationId: correlationId,
        );

        // Assert: Result is successful
        expect(result.success, true,
            reason: 'Pipeline should succeed with mocked services');
        expect(result.transcript, isNotEmpty,
            reason: 'Should have transcript from STT');
        expect(result.response, isNotEmpty,
            reason: 'Should have response from LLM');
        expect(result.audioBytes, isNotEmpty,
            reason: 'Should have audio bytes from TTS');
        expect(result.turnId, isNotEmpty, reason: 'Should have turnId');

        // Assert: Turn was created with correct correlationId
        final createdTurn = await turnRepo.findByCorrelationId(correlationId);
        expect(createdTurn, isNotNull,
            reason: 'Turn should be created with correlationId');
        expect(createdTurn!.uuid, result.turnId,
            reason: 'Turn UUID should match result');
        expect(createdTurn.result, 'success',
            reason: 'Turn should mark success');

        // Assert: Invocations were recorded
        expect(sttRepo.getAll().length, greaterThanOrEqualTo(1),
            reason: 'Should record STT invocation');
        expect(llmRepo.getAll().length, greaterThanOrEqualTo(1),
            reason: 'Should record LLM invocation');
        expect(ttsRepo.getAll().length, greaterThanOrEqualTo(1),
            reason: 'Should record TTS invocation');

        // Assert: Turn links invocations
        expect(createdTurn.sttInvocationId, isNotNull,
            reason: 'Turn should link STT invocation');
        expect(createdTurn.llmInvocationId, isNotNull,
            reason: 'Turn should link LLM invocation');
        expect(createdTurn.ttsInvocationId, isNotNull,
            reason: 'Turn should link TTS invocation');
        expect(createdTurn.contextManagerInvocationId, isNotNull,
            reason: 'Turn should link ContextManager invocation');
      },
    );
  });
}
