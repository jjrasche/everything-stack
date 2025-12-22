/// # Training Flow Verification Test
///
/// Proves that the complete feedback loop works end-to-end:
/// 1. ContextManagerInvocation captures wrong selection
/// 2. Feedback entity captures correction
/// 3. trainFromFeedback() updates personality thresholds
/// 4. Thresholds actually change

import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:everything_stack_template/domain/personality.dart';
import 'package:everything_stack_template/domain/context_manager_invocation.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/services/context_manager.dart';
import 'package:everything_stack_template/repositories/personality_repository_impl.dart';
import 'package:everything_stack_template/repositories/context_manager_invocation_repository_impl.dart';
import 'package:everything_stack_template/repositories/feedback_repository_impl.dart';
import 'package:everything_stack_template/repositories/namespace_repository_impl.dart';
import 'package:everything_stack_template/repositories/tool_repository_impl.dart';
import 'package:everything_stack_template/tools/task/repositories/task_repository.dart';
import 'package:everything_stack_template/tools/timer/repositories/timer_repository.dart';
import 'package:everything_stack_template/services/llm_service.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/mcp_executor.dart';

void main() {
  group('Training Flow Verification', () {
    late PersonalityRepository personalityRepo;
    late ContextManagerInvocationRepository invocationRepo;
    late FeedbackRepository feedbackRepo;
    late NamespaceRepository namespaceRepo;
    late ToolRepository toolRepo;
    late TaskRepository taskRepo;
    late TimerRepository timerRepo;
    late ContextManager contextManager;

    setUp(() async {
      // Initialize repositories (in-memory for testing)
      personalityRepo = PersonalityRepositoryImpl();
      invocationRepo = ContextManagerInvocationRepositoryImpl();
      feedbackRepo = FeedbackRepositoryImpl();
      namespaceRepo = NamespaceRepositoryImpl();
      toolRepo = ToolRepositoryImpl();

      // Mock repositories
      taskRepo = MockTaskRepository();
      timerRepo = MockTimerRepository();

      // Create default personality
      final personality = Personality(
        name: 'Test Assistant',
        systemPrompt: 'Test prompt',
      );
      personality.baseModel = 'test-model';
      personality.temperature = 0.7;
      personality.isActive = true;
      await personalityRepo.save(personality);

      // Initialize ContextManager
      contextManager = ContextManager(
        personalityRepo: personalityRepo,
        namespaceRepo: namespaceRepo,
        toolRepo: toolRepo,
        invocationRepo: invocationRepo,
        feedbackRepo: feedbackRepo,
        taskRepo: taskRepo,
        timerRepo: timerRepo,
        llmService: NullLLMService(),
        embeddingService: NullEmbeddingService(),
        mcpExecutor: MockMCPExecutor(),
      );
    });

    test('Complete feedback loop: wrong selection → correction → threshold update',
        () async {
      // ============================================================
      // STEP 1: Create invocation with WRONG namespace selection
      // ============================================================
      final invocation = ContextManagerInvocation(
        correlationId: 'turn_1',
        eventPayloadJson: jsonEncode({
          'transcription': 'set a timer for 5 minutes',
        }),
      );
      invocation.selectedNamespace = 'task'; // WRONG - should be 'timer'
      invocation.toolsCalled = ['task.create']; // WRONG tool
      invocation.personalityId =
          (await personalityRepo.getActive())!.uuid;

      // Save invocation (this is what ContextManager does)
      final invocationId = await contextManager.recordInvocation(invocation);
      print('✓ Invocation created: $invocationId with namespace="task" (WRONG)');

      // ============================================================
      // STEP 2: User provides feedback with CORRECTION
      // ============================================================
      final feedback = Feedback(
        invocationId: invocationId,
        componentType: 'context_manager',
        action: FeedbackAction.correct,
        turnId: 'turn_1', // Part of conversational turn
        correctedData: jsonEncode({
          'namespace': 'timer', // Correct answer
          'tool': 'timer.set', // Correct tool
        }),
        reason: 'User corrected: should be timer, not task',
      );
      await feedbackRepo.save(feedback);
      print('✓ Feedback created: correctedData="{"namespace":"timer"}"');

      // ============================================================
      // STEP 3: Get baseline personality thresholds BEFORE training
      // ============================================================
      var personality = await personalityRepo.getActive();
      personality!.loadAfterRead();
      final taskThresholdBefore =
          personality.namespaceAttention.getThreshold('task');
      final timerThresholdBefore =
          personality.namespaceAttention.getThreshold('timer');

      print('\n📊 BEFORE training:');
      print('   task threshold:  $taskThresholdBefore (lower = more likely)');
      print('   timer threshold: $timerThresholdBefore');

      // ============================================================
      // STEP 4: Call trainFromFeedback - THE KEY METHOD
      // ============================================================
      await contextManager.trainFromFeedback('turn_1');
      print(
          '\n✓ trainFromFeedback("turn_1") called - should update thresholds');

      // ============================================================
      // STEP 5: VERIFY thresholds actually changed
      // ============================================================
      personality = await personalityRepo.getActive();
      personality!.loadAfterRead();
      final taskThresholdAfter =
          personality.namespaceAttention.getThreshold('task');
      final timerThresholdAfter =
          personality.namespaceAttention.getThreshold('timer');

      print('\n📊 AFTER training:');
      print('   task threshold:  $taskThresholdAfter (should be HIGHER)');
      print('   timer threshold: $timerThresholdAfter (should be LOWER)');

      // ============================================================
      // ASSERTIONS: Prove the loop works
      // ============================================================
      expect(
        taskThresholdAfter > taskThresholdBefore,
        true,
        reason:
            'Task threshold should INCREASE (wrong choice becomes harder to select)',
      );

      expect(
        timerThresholdAfter < timerThresholdBefore,
        true,
        reason:
            'Timer threshold should DECREASE (correct choice becomes easier)',
      );

      print('\n✅ TRAINING LOOP VERIFIED:');
      print('   Wrong choice (task) got HARDER:   $taskThresholdBefore → $taskThresholdAfter');
      print('   Correct choice (timer) got EASIER: $timerThresholdBefore → $timerThresholdAfter');
    });

    test('Multiple feedback records update thresholds cumulatively', () async {
      // This proves the loop can be applied multiple times
      final personality = (await personalityRepo.getActive())!;
      personality.loadAfterRead();
      final initialThreshold =
          personality.namespaceAttention.getThreshold('timer');

      // Create 3 feedback corrections for "timer"
      for (int i = 0; i < 3; i++) {
        final inv = ContextManagerInvocation(
          correlationId: 'turn_$i',
          eventPayloadJson: jsonEncode({
            'transcription': 'set a timer',
          }),
        );
        inv.selectedNamespace = 'task';
        inv.personalityId = personality.uuid;
        final invId = await contextManager.recordInvocation(inv);

        final feedback = Feedback(
          invocationId: invId,
          componentType: 'context_manager',
          action: FeedbackAction.correct,
          turnId: 'turn_$i',
          correctedData: jsonEncode({'namespace': 'timer'}),
        );
        await feedbackRepo.save(feedback);
        await contextManager.trainFromFeedback('turn_$i');
      }

      // Verify threshold lowered progressively
      final finalPersonality = (await personalityRepo.getActive())!;
      finalPersonality.loadAfterRead();
      final finalThreshold =
          finalPersonality.namespaceAttention.getThreshold('timer');

      expect(
        finalThreshold < initialThreshold,
        true,
        reason: 'Repeated feedback should lower threshold progressively',
      );
      print('✅ Cumulative training works: $initialThreshold → $finalThreshold');
    });
  });
}

// ============================================================================
// Mocks for testing
// ============================================================================

class MockTaskRepository implements TaskRepository {
  @override
  Future<void> save(task) async {}

  @override
  Future<bool> delete(String id) async => true;

  @override
  Future<List> findAll() async => [];

  @override
  Future findByUuid(String uuid) async => null;

  @override
  Future<int> count() async => 0;

  @override
  Future<List> findByTimestamp(DateTime start, DateTime end) async => [];

  @override
  Future<Map<String, int>> countByStatus() async => {};

  @override
  Future<List> findDueToday() async => [];

  @override
  Future<List> findOverdue() async => [];
}

class MockTimerRepository implements TimerRepository {
  @override
  Future<void> save(timer) async {}

  @override
  Future<bool> delete(String id) async => true;

  @override
  Future<List> findAll() async => [];

  @override
  Future findByUuid(String uuid) async => null;

  @override
  Future<int> count() async => 0;

  @override
  Future<List> findActive() async => [];

  @override
  Future<List> findExpired() async => [];

  @override
  Future<void> markExpired(String uuid) async {}
}

class MockMCPExecutor implements MCPExecutor {
  @override
  Future executeTools(tools, context) async => {};
}

class NullLLMService extends LLMService {
  @override
  Future<void> initialize() async {}

  @override
  Stream<String> chat({
    required List messages,
    required String userMessage,
    String? systemPrompt,
    int? maxTokens,
  }) async* {
    yield 'mock response';
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
      id: 'mock',
      content: 'mock',
      toolCalls: [],
      tokensUsed: 0,
    );
  }

  @override
  void dispose() {}

  @override
  bool get isReady => true;
}

class NullEmbeddingService extends EmbeddingService {
  @override
  Future<void> initialize() async {}

  @override
  Future<List<double>> generate(String text) async =>
      List.filled(384, 0.0); // Dummy embedding

  @override
  void dispose() {}

  @override
  bool get isReady => true;
}
