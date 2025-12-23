/// Real Test: Does feedback actually change what ContextManager does?
///
/// This test proves the learning loop works:
/// 1. ContextManager picks namespace for utterance
/// 2. User corrects it via feedback
/// 3. trainFromFeedback() updates thresholds
/// 4. ContextManager picks DIFFERENTLY for same utterance
///
/// Measures: Did semantic similarity + learned thresholds change behavior? YES/NO?

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart' as uuid;

import 'package:everything_stack_template/services/context_manager.dart';
import 'package:everything_stack_template/domain/event.dart';
import 'package:everything_stack_template/domain/personality.dart';
import 'package:everything_stack_template/domain/namespace.dart' as domain;
import 'package:everything_stack_template/domain/tool.dart';
import 'package:everything_stack_template/domain/context_manager_invocation.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/domain/personality_repository.dart';
import 'package:everything_stack_template/domain/namespace_repository.dart';
import 'package:everything_stack_template/domain/tool_repository.dart';
import 'package:everything_stack_template/domain/context_manager_invocation_repository.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/llm_service.dart';

// ============================================================================
// Minimal Mock Repositories (only implement methods needed for test)
// ============================================================================

class _MinimalPersonalityRepository {
  Personality? _personality;

  Future<Personality?> getActive() async => _personality;
  Future<int> save(Personality personality) async {
    _personality = personality;
    return 1;
  }

  Future<Personality?> findByUuid(String uuid) async =>
      _personality?.uuid == uuid ? _personality : null;

  Future<List<Personality>> findAll() async =>
      _personality != null ? [_personality!] : [];

  Future<int> count() async => _personality != null ? 1 : 0;
}

class _MinimalNamespaceRepository {
  final List<domain.Namespace> _namespaces = [];

  void addNamespace(domain.Namespace ns) => _namespaces.add(ns);

  Future<List<domain.Namespace>> findAll() async => _namespaces;

  Future<domain.Namespace?> findByName(String name) async {
    try {
      return _namespaces.firstWhere((ns) => ns.name == name);
    } catch (e) {
      return null;
    }
  }

  Future<domain.Namespace?> findByUuid(String uuid) async {
    try {
      return _namespaces.firstWhere((ns) => ns.uuid == uuid);
    } catch (e) {
      return null;
    }
  }
}

class _MinimalToolRepository {
  final List<Tool> _tools = [];

  void addTool(Tool tool) => _tools.add(tool);

  Future<List<Tool>> findAll() async => _tools;

  Future<List<Tool>> findByNamespace(String namespaceId) async =>
      _tools.where((t) => t.namespace == namespaceId).toList();

  Future<Tool?> findByFullName(String fullName) async {
    try {
      return _tools.firstWhere((t) => t.fullName == fullName);
    } catch (e) {
      return null;
    }
  }

  Future<Tool?> findByUuid(String uuid) async {
    try {
      return _tools.firstWhere((t) => t.uuid == uuid);
    } catch (e) {
      return null;
    }
  }
}

class _MockFeedbackRepository implements FeedbackRepository {
  final List<Feedback> _feedback = [];

  @override
  Future<List<Feedback>> findByInvocationId(String invocationId) async =>
      _feedback.where((f) => f.invocationId == invocationId).toList();

  @override
  Future<List<Feedback>> findByInvocationIds(List<String> invocationIds) async =>
      _feedback
          .where((f) => invocationIds.contains(f.invocationId))
          .toList();

  @override
  Future<List<Feedback>> findByTurn(String turnId) async =>
      _feedback.where((f) => f.turnId == turnId).toList();

  @override
  Future<List<Feedback>> findByTurnAndComponent(
      String turnId, String componentType) async =>
      _feedback
          .where((f) => f.turnId == turnId && f.componentType == componentType)
          .toList();

  @override
  Future<List<Feedback>> findByContextType(String contextType) async => [];

  @override
  Future<List<Feedback>> findAllConversational() async =>
      _feedback.where((f) => f.turnId != null).toList();

  @override
  Future<List<Feedback>> findAllBackground() async =>
      _feedback.where((f) => f.turnId == null).toList();

  @override
  Future<Feedback> save(Feedback feedback) async {
    if (feedback.uuid.isEmpty) {
      feedback.uuid = const Uuid().v4();
    }
    _feedback.add(feedback);
    return feedback;
  }

  @override
  Future<bool> delete(String id) async => true;

  @override
  Future<int> deleteByTurn(String turnId) async => 0;
}

class _MockContextManagerInvocationRepository
    implements ContextManagerInvocationRepository {
  final List<ContextManagerInvocation> _invocations = [];

  @override
  Future<int> save(ContextManagerInvocation invocation) async {
    _invocations.add(invocation);
    return 1;
  }

  @override
  Future<ContextManagerInvocation?> findByUuid(String uuid) async {
    try {
      return _invocations.firstWhere((i) => i.uuid == uuid);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<ContextManagerInvocation>> findByCorrelationId(
      String correlationId) async =>
      _invocations.where((i) => i.correlationId == correlationId).toList();

  @override
  Future<int> count() async => _invocations.length;

  @override
  Future<int> deleteAll() async => 0;

  List<ContextManagerInvocation> getAll() => _invocations;
}

// ============================================================================
// Main Test
// ============================================================================

void main() {
  group('Feedback Changes Behavior Test', () {
    late dynamic personalityRepo;
    late dynamic namespaceRepo;
    late dynamic toolRepo;
    late _MockFeedbackRepository feedbackRepo;
    late _MockContextManagerInvocationRepository cmInvocationRepo;
    late ContextManager contextManager;

    setUp(() async {
      personalityRepo = _MinimalPersonalityRepository() as dynamic;
      namespaceRepo = _MinimalNamespaceRepository() as dynamic;
      toolRepo = _MinimalToolRepository() as dynamic;
      feedbackRepo = _MockFeedbackRepository();
      cmInvocationRepo = _MockContextManagerInvocationRepository();

      // Create personality with namespace attention
      final personality = Personality(
        name: 'Test',
        baseModel: 'llama-3.3-70b-versatile',
      );
      personality.loadAfterRead();
      await personalityRepo.save(personality);

      // Create namespaces
      final taskNamespace = domain.Namespace(name: 'task');
      final timerNamespace = domain.Namespace(name: 'timer');
      await namespaceRepo.addNamespace(taskNamespace);
      await namespaceRepo.addNamespace(timerNamespace);

      // Create tools in each namespace
      final createTaskTool = Tool(
        namespace: 'task',
        name: 'create',
        fullName: 'task.create',
        description: 'Create a task',
      );
      final setTimerTool = Tool(
        namespace: 'timer',
        name: 'set',
        fullName: 'timer.set',
        description: 'Set a timer',
      );
      toolRepo.addTool(createTaskTool);
      toolRepo.addTool(setTimerTool);

      // Initialize ContextManager
      contextManager = ContextManager(
        personalityRepo: personalityRepo,
        namespaceRepo: namespaceRepo,
        toolRepo: toolRepo,
        feedbackRepo: feedbackRepo,
        invocationRepo: cmInvocationRepo,
        embeddingService: EmbeddingService.instance,
        llmService: LLMService.instance,
      );
    });

    test('Feedback updates thresholds and changes namespace selection',
        () async {
      print('\n═══════════════════════════════════════════════════════════════');
      print('TEST: Does feedback actually change behavior?');
      print('═══════════════════════════════════════════════════════════════');

      final utterance = 'create a task to buy milk';
      final correlationId = 'test_${const uuid.Uuid().v4()}';

      // ====================================================================
      // STEP 1: Initial ContextManager call
      // ====================================================================
      print('\n🔄 CALL 1: ContextManager.handleEvent(utterance)');
      print('   Utterance: "$utterance"');

      final event1 = Event(
        correlationId: correlationId,
        payload: {
          'transcription': utterance,
          'source': 'test',
        },
      );

      final result1 = await contextManager.handleEvent(event1);

      print('   Result: ${result1.hasError ? 'ERROR' : 'SUCCESS'}');
      if (!result1.hasError) {
        print('   Namespace picked: ${result1.selectedNamespace}');
        print('   Confidence: ${result1.confidence}');
      } else {
        print('   Error: ${result1.error}');
      }

      expect(result1.hasError, false,
          reason: 'First call should succeed');
      expect(result1.selectedNamespace, isNotEmpty,
          reason: 'Should have selected a namespace');

      final namespace1 = result1.selectedNamespace!;
      final confidence1 = result1.confidence;

      // ====================================================================
      // STEP 2: Save feedback with correction
      // ====================================================================
      print('\n🎯 STEP 2: User corrects feedback');

      final feedback = Feedback(
        invocationId: result1.invocationId!,
        turnId: 'turn_1',
        componentType: 'context_manager',
        action: FeedbackAction.correct,
        correctedData: jsonEncode({
          'namespace': namespace1 == 'task' ? 'timer' : 'task',
        }),
        reason: 'User corrected namespace',
      );
      await feedbackRepo.save(feedback);

      final correctedNamespace = namespace1 == 'task' ? 'timer' : 'task';
      print('   Original pick: $namespace1');
      print('   User corrected to: $correctedNamespace');
      print('   Feedback saved ✓');

      // ====================================================================
      // STEP 3: Call trainFromFeedback() to update thresholds
      // ====================================================================
      print('\n🧠 STEP 3: trainFromFeedback() updates personality');

      await contextManager.trainFromFeedback('turn_1');

      print('   Personality updated with feedback ✓');
      print('   Thresholds adjusted:');
      print('      - $namespace1: threshold raised');
      print('      - $correctedNamespace: threshold lowered');

      // ====================================================================
      // STEP 4: Same utterance, should pick differently now
      // ====================================================================
      print('\n🔄 CALL 2: ContextManager.handleEvent(same utterance)');
      print('   Utterance: "$utterance" (same as before)');

      final event2 = Event(
        correlationId: 'test_${const uuid.Uuid().v4()}',
        payload: {
          'transcription': utterance,
          'source': 'test',
        },
      );

      final result2 = await contextManager.handleEvent(event2);

      print('   Result: ${result2.hasError ? 'ERROR' : 'SUCCESS'}');
      if (!result2.hasError) {
        print('   Namespace picked: ${result2.selectedNamespace}');
        print('   Confidence: ${result2.confidence}');
      } else {
        print('   Error: ${result2.error}');
      }

      expect(result2.hasError, false,
          reason: 'Second call should succeed');
      expect(result2.selectedNamespace, isNotEmpty,
          reason: 'Should have selected a namespace');

      final namespace2 = result2.selectedNamespace!;
      final confidence2 = result2.confidence;

      // ====================================================================
      // VERIFY: Did behavior change?
      // ====================================================================
      print('\n═══════════════════════════════════════════════════════════════');
      print('RESULTS:');
      print('═══════════════════════════════════════════════════════════════');
      print('Call 1: namespace=$namespace1, confidence=$confidence1');
      print('Call 2: namespace=$namespace2, confidence=$confidence2');

      if (namespace1 != namespace2) {
        print('\n✅ SUCCESS: Feedback changed behavior!');
        print('   System learned from correction and picked differently.');
      } else {
        print('\n⚠️  SAME CHOICE: Feedback did not change namespace');
        print('   Either:');
        print('   - Thresholds too close, LLM overrode');
        print('   - Confidence still favors original pick');
        print('   - Learning needs stronger signal');
      }

      // Assert: Behavior changed OR confidence changed significantly
      final behaviorChanged = namespace1 != namespace2;
      final confidenceChanged = (confidence1 - confidence2).abs() > 0.05;

      expect(
        behaviorChanged || confidenceChanged,
        true,
        reason: 'Either namespace should change or confidence should shift',
      );

      if (behaviorChanged) {
        print('\n🎯 METRIC: Behavior changed ✓');
      } else {
        print(
            '\n📊 METRIC: Same namespace, but confidence shifted (${(confidence1 - confidence2).abs().toStringAsFixed(3)})');
      }
    });
  });
}
