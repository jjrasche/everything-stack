import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/main.dart';
import 'package:everything_stack_template/services/coordinator.dart';
import 'package:everything_stack_template/services/context_selector.dart';
import 'package:everything_stack_template/services/inference_service.dart';
import 'package:everything_stack_template/services/tts_service.dart';
import 'package:everything_stack_template/services/implementations/llm_implementer.dart';
import 'package:everything_stack_template/services/types/llm_types.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/core/adaptation_state.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/domain/feedback.dart' as domain_feedback;
import 'package:everything_stack_template/tools/timer/repositories/timer_repository.dart';
import 'mocks/services_setup.dart';

/// Multi-turn timer conversation test.
///
/// ## Test Strategy
/// - Only mock external API calls (Groq, TTS)
/// - Test REAL internal logic: ContextSelector, Coordinator, ToolExecutor, TimerRepository
/// - Verify timers are actually persisted and scheduled
///
/// ## Scenario
/// Turn 1: "Set a timer for 5 minutes" → timer.set(300s)
/// Turn 2: "Make it 10 minutes instead" → timer.cancel + timer.set(600s)
/// Turn 3: "Cancel the timer" → timer.cancel
void main() {
  testWidgets('Multi-turn timer conversation with real system', (WidgetTester tester) async {
    print('\n🚀 [Multi-Turn Timer Test] Starting test...');

    // ========== PRE-SETUP: Register mock for external API only ==========
    print('🔧 Registering mocks for external APIs...');
    final getIt = GetIt.instance;

    // Mock Groq API (return canned tool calls for test scenario)
    if (!getIt.isRegistered<InferenceService>()) {
      final mockInferenceService = InferenceService(
        implementers: {
          'groq': CannedToolCallMockLLM(
            responses: {
              'Set a timer for 5 minutes': [
                LLMToolCall(
                  id: 'call_1',
                  toolName: 'timer.set',
                  params: {'duration_seconds': 300, 'label': 'Timer'},
                ),
              ],
              'Make it 10 minutes instead': [
                LLMToolCall(
                  id: 'call_2a',
                  toolName: 'timer.cancel',
                  params: {'label': 'Timer'},
                ),
                LLMToolCall(
                  id: 'call_2b',
                  toolName: 'timer.set',
                  params: {'duration_seconds': 600, 'label': 'Timer'},
                ),
              ],
              'Cancel the timer': [
                LLMToolCall(
                  id: 'call_3',
                  toolName: 'timer.cancel',
                  params: {'label': 'Timer'},
                ),
              ],
            },
          ),
        },
        defaultImplementer: 'groq',
        invocationRepo: _MockInvocationRepository(),
        adaptationStateRepo: _MockAdaptationStateRepository(),
        feedbackRepo: _MockFeedbackRepository(),
      );
      getIt.registerSingleton<InferenceService>(mockInferenceService);
      print('✅ Groq API mocked (returns canned tool calls)');
    }

    // Mock TTS API (don't actually speak)
    if (!getIt.isRegistered<TTSService>()) {
      getIt.registerSingleton<TTSService>(createMockTTSService());
      print('✅ TTS API mocked');
    }

    // ========== SETUP: Build app and initialize REAL system ==========
    print('🏗️ Building MyApp with real internal services...');
    await tester.pumpWidget(const MyApp());

    print('⏳ Waiting for bootstrap...');
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.byType(Scaffold), findsWidgets);

    // Get REAL services (not mocked - these are internal logic)
    final coordinator = getIt<Coordinator>();
    final contextSelector = getIt<ContextSelector>();
    final invocationRepo = getIt<EntityRepository<Invocation>>();
    final timerRepo = getIt<TimerRepository>();

    print('✅ Real services initialized (ContextSelector, Coordinator, TimerRepository)');

    // ========== TURN 1: "Set a timer for 5 minutes" ==========
    print('\n' + '=' * 60);
    print('📢 TURN 1: Set a timer for 5 minutes');
    print('=' * 60);

    final turn1Result = await coordinator.orchestrate(
      eventId: 'timer_turn1_${DateTime.now().millisecondsSinceEpoch}',
      utterance: 'Set a timer for 5 minutes',
      availableNamespaces: ['timer'],
      toolsByNamespace: {'timer': []},
    );

    print('✅ [Turn 1] Orchestration: ${turn1Result.success ? "SUCCESS" : "FAILED"}');
    expect(turn1Result.success, isTrue, reason: 'Turn 1 should succeed');

    // Verify timer was created and persisted
    final timersAfterTurn1 = await timerRepo.findActive();
    print('📋 [Turn 1] Active timers: ${timersAfterTurn1.length}');
    expect(timersAfterTurn1.length, equals(1), reason: 'Should have 1 active timer');

    final timer1 = timersAfterTurn1.first;
    print('   Duration: ${timer1.durationSeconds}s (expected ~300s)');
    expect(timer1.durationSeconds, equals(300), reason: 'Timer should be 5 minutes (300s)');
    expect(timer1.label, equals('Timer'));
    expect(timer1.fired, isFalse);

    // ========== TURN 2: "Make it 10 minutes instead" ==========
    print('\n' + '=' * 60);
    print('📢 TURN 2: Make it 10 minutes instead');
    print('=' * 60);

    // Verify ContextSelector has conversation history
    final contextBeforeTurn2 = await contextSelector.selectContext(
      transcription: 'Make it 10 minutes instead',
      userId: null,
    );
    print('🔍 Conversation history: ${contextBeforeTurn2.conversationThread.length} invocations');
    expect(
      contextBeforeTurn2.conversationThread.length,
      greaterThan(0),
      reason: 'Turn 2 should see Turn 1 conversation history',
    );

    final turn2Result = await coordinator.orchestrate(
      eventId: 'timer_turn2_${DateTime.now().millisecondsSinceEpoch}',
      utterance: 'Make it 10 minutes instead',
      availableNamespaces: ['timer'],
      toolsByNamespace: {'timer': []},
    );

    print('✅ [Turn 2] Orchestration: ${turn2Result.success ? "SUCCESS" : "FAILED"}');
    expect(turn2Result.success, isTrue, reason: 'Turn 2 should succeed');

    // Verify old timer was cancelled and new timer created
    final timersAfterTurn2 = await timerRepo.findActive();
    print('📋 [Turn 2] Active timers: ${timersAfterTurn2.length}');
    expect(timersAfterTurn2.length, equals(1), reason: 'Should have 1 active timer (old cancelled, new created)');

    final timer2 = timersAfterTurn2.first;
    print('   Duration: ${timer2.durationSeconds}s (expected ~600s)');
    expect(timer2.durationSeconds, equals(600), reason: 'Timer should be 10 minutes (600s)');

    // ========== TURN 3: "Cancel the timer" ==========
    print('\n' + '=' * 60);
    print('📢 TURN 3: Cancel the timer');
    print('=' * 60);

    final contextBeforeTurn3 = await contextSelector.selectContext(
      transcription: 'Cancel the timer',
      userId: null,
    );
    print('🔍 Conversation history: ${contextBeforeTurn3.conversationThread.length} invocations');
    expect(
      contextBeforeTurn3.conversationThread.length,
      greaterThan(0),
      reason: 'Turn 3 should see Turn 1 and Turn 2 history',
    );

    final turn3Result = await coordinator.orchestrate(
      eventId: 'timer_turn3_${DateTime.now().millisecondsSinceEpoch}',
      utterance: 'Cancel the timer',
      availableNamespaces: ['timer'],
      toolsByNamespace: {'timer': []},
    );

    print('✅ [Turn 3] Orchestration: ${turn3Result.success ? "SUCCESS" : "FAILED"}');
    expect(turn3Result.success, isTrue, reason: 'Turn 3 should succeed');

    // Verify all timers cancelled
    final timersAfterTurn3 = await timerRepo.findActive();
    print('📋 [Turn 3] Active timers: ${timersAfterTurn3.length}');
    expect(timersAfterTurn3.length, equals(0), reason: 'All timers should be cancelled');

    // ========== FINAL ASSERTIONS ==========
    print('\n' + '=' * 60);
    print('✅ FINAL VERIFICATION');
    print('=' * 60);

    // Verify invocations were recorded
    final allInvocations = await invocationRepo.findAll();
    final recentInvocations = allInvocations
        .where((inv) => inv.createdAt.isAfter(DateTime.now().subtract(const Duration(minutes: 1))))
        .toList();
    print('📋 Recent invocations: ${recentInvocations.length}');

    final componentTypes = recentInvocations.map((inv) => inv.componentType).toSet();
    print('   Components: ${componentTypes.join(", ")}');
    expect(componentTypes.contains('context_selector'), isTrue, reason: 'ContextSelector should be invoked');
    expect(componentTypes.contains('tool_executor'), isTrue, reason: 'ToolExecutor should be invoked');

    // Verify final state
    final finalActiveTimers = await timerRepo.findActive();
    final allTimers = await timerRepo.findAll();
    print('📊 Final state:');
    print('   Active timers: ${finalActiveTimers.length}');
    print('   Total timers: ${allTimers.length}');

    print('\n🎉 Multi-turn timer test PASSED');
    print('   - Real ContextSelector: ✅');
    print('   - Real Coordinator: ✅');
    print('   - Real ToolExecutor: ✅');
    print('   - Real TimerRepository: ✅');
    print('   - Timers persisted and scheduled: ✅');
  });
}

/// Canned tool call mock - returns predefined tool calls for specific utterances.
/// Only mocks the external Groq API, not internal timer logic.
class CannedToolCallMockLLM implements LLMImplementer {
  final Map<String, List<LLMToolCall>> responses;

  CannedToolCallMockLLM({required this.responses});

  @override
  String get implementerName => 'canned_mock';

  @override
  int get maxTokensLimit => 8192;

  @override
  Future<LLMInvocationOutput> chat({
    required List messages,
    required double temperature,
    String? systemPrompt,
  }) async {
    return LLMInvocationOutput(
      response: 'Mock response',
      tokensUsed: 10,
      latencyMs: 50,
    );
  }

  @override
  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    // Extract last user message
    final lastUserMsg = messages.lastWhere(
      (msg) => msg['role'] == 'user',
      orElse: () => {'content': ''},
    );
    final utterance = lastUserMsg['content'] as String? ?? '';

    // Return canned tool calls for known utterances
    final toolCalls = responses[utterance] ?? [];
    final responseText = toolCalls.isEmpty
        ? 'I can help with timers'
        : 'Executing timer commands';

    print('🤖 Canned Mock: "$utterance" → ${toolCalls.length} tool calls');

    return LLMResponse(
      id: 'mock_${DateTime.now().millisecondsSinceEpoch}',
      content: responseText,
      toolCalls: toolCalls,
      tokensUsed: 20,
    );
  }
}

// Copy mock repositories from services_setup.dart
class _MockInvocationRepository implements InvocationRepository<Invocation> {
  @override
  Future<Invocation> save(Invocation entity) async => entity;
  @override
  Future<Invocation?> findById(String id) async => null;
  @override
  Future<List<Invocation>> findAll() async => [];
  @override
  Future<bool> delete(String id) async => false;
  @override
  Future<int> deleteByTurn(String turnId) async => 0;
  @override
  Future<List<Invocation>> findByTurn(String turnId) async => [];
  @override
  Future<List<Invocation>> findByContextType(String contextType) async => [];
  @override
  Future<List<Invocation>> findByIds(List<String> ids) async => [];
}

class _MockAdaptationStateRepository implements AdaptationStateRepository {
  @override
  Future<AdaptationState?> getForComponent(String componentType, {required String? implementer, String? userId}) async => null;
  @override
  Future<List<AdaptationState>> findByComponentAndImplementer(String componentType, {required String? implementer}) async => [];
  @override
  Future<bool> updateWithVersion(AdaptationState state) async => true;
  @override
  Future<AdaptationState> save(AdaptationState state) async => state;
  @override
  Future<bool> delete(String id) async => false;
  @override
  AdaptationState createDefault(String componentType, {required String? implementer, String? userId}) =>
      AdaptationState(componentType: componentType, implementer: implementer, userId: userId, data: {});
}

class _MockFeedbackRepository implements FeedbackRepository {
  @override
  Future<List<domain_feedback.Feedback>> findByInvocationId(String invocationId) async => [];
  @override
  Future<List<domain_feedback.Feedback>> findByInvocationIds(List<String> invocationIds) async => [];
  @override
  Future<List<domain_feedback.Feedback>> findByTurn(String turnId) async => [];
  @override
  Future<List<domain_feedback.Feedback>> findByTurnAndComponent(String turnId, String componentType) async => [];
  @override
  Future<List<domain_feedback.Feedback>> findByContextType(String contextType) async => [];
  @override
  Future<List<domain_feedback.Feedback>> findAllConversational() async => [];
  @override
  Future<List<domain_feedback.Feedback>> findAllBackground() async => [];
  @override
  Future<domain_feedback.Feedback> save(domain_feedback.Feedback feedback) async => feedback;
  @override
  Future<bool> delete(String id) async => false;
  @override
  Future<int> deleteByTurn(String turnId) async => 0;
}
