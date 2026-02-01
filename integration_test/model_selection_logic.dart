/// # Model Selection Integration Test
///
/// Tests that ModelSelector uses Thompson Sampling to select LLM models
/// and learns from feedback over time.
///
/// Verifies:
/// - ModelSelector invocations are logged during orchestration
/// - Thompson Sampling selects from available models
/// - trainFromFeedback updates model stats correctly
/// - Model selection confidence increases with positive feedback

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/llm_types.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/feedback.dart' as core;
import 'package:everything_stack_template/services/trainables/model_selector.dart';
import 'package:get_it/get_it.dart';
import 'shared/test_harness.dart';
import 'shared/response_map_implementer.dart';

// Simple utterances for testing model selection
final _utterances = {
  'greeting': 'Hello, how are you today?',
  'question': 'What is the weather like?',
  'command': 'Set a timer for 5 minutes',
};

final _responses = {
  _utterances['greeting']!: LLMResponse(
    id: 'greeting_resp',
    content: 'Hello! I am doing well, thank you for asking.',
    toolCalls: [],
    tokensUsed: 15,
  ),
  _utterances['question']!: LLMResponse(
    id: 'question_resp',
    content: 'It looks sunny with a high of 72 degrees.',
    toolCalls: [],
    tokensUsed: 14,
  ),
  _utterances['command']!: LLMResponse(
    id: 'command_resp',
    content: 'I have set a timer for 5 minutes.',
    toolCalls: [],
    tokensUsed: 10,
  ),
};

final modelSelectionTest = IntegrationTestConfig(
  name: 'Model Selection (Thompson Sampling)',

  repos: [
    InvocationRepository<Invocation>,
  ],

  utterances: _utterances,

  mockImplementers: {
    'groq': ResponseMapLLMImplementer(_responses),
  },

  testLogic: (t) async {
    print('\n=== TEST: Model Selection with Thompson Sampling ===');

    // ===== CLEANUP: Remove old invocations to start fresh =====
    print('\n[Cleanup] Removing old invocations to start fresh...');
    final cleanupRepo = GetIt.instance<InvocationRepository<Invocation>>();
    final oldInvocations = await cleanupRepo.findAll();
    for (final inv in oldInvocations) {
      await cleanupRepo.delete(inv.uuid);
    }
    print('   Deleted ${oldInvocations.length} old invocations');

    // ===== VERIFY: ModelSelector is registered =====
    print('\n[Verify] Checking ModelSelector registration...');
    expect(
      GetIt.instance.isRegistered<ModelSelector>(),
      isTrue,
      reason: 'ModelSelector should be registered in GetIt',
    );

    final modelSelector = GetIt.instance<ModelSelector>();
    final availableModelKeys = modelSelector.getAvailableModelKeys();
    print('   ModelSelector registered: ✓');
    print('   Available models: $availableModelKeys');

    expect(
      availableModelKeys.length,
      greaterThanOrEqualTo(2),
      reason: 'Should have at least 2 models for meaningful selection',
    );

    // ===== TEST: Send utterance to trigger model selection =====
    print('\n[Test] Sending greeting to trigger model selection...');
    final greetingUtterance = _utterances['greeting']!;
    await t.stt('greeting');
    await Future.delayed(const Duration(seconds: 3));

    // ===== VERIFY: Check model_selector Invocation was logged =====
    print('\n[Verify] Checking model_selector invocation...');

    final invocationRepo = GetIt.instance<InvocationRepository<Invocation>>();
    final allInvocations = await invocationRepo.findAll();

    // Find model_selector invocations
    final modelInvocations = allInvocations
        .where((inv) => inv.componentType == 'model_selector')
        .toList();

    print('   Found ${modelInvocations.length} model_selector invocations');

    expect(
      modelInvocations.length,
      greaterThanOrEqualTo(1),
      reason: 'Should have at least one model_selector invocation',
    );

    // Verify the invocation has expected structure
    final lastModelInv = modelInvocations.last;
    print('   Last model selection:');
    print('     Input: ${lastModelInv.input}');
    print('     Output: ${lastModelInv.output}');

    // Verify input contains the exact utterance sent
    final inputUtterance = lastModelInv.input?['utterance'] as String?;
    expect(
      inputUtterance,
      equals(greetingUtterance),
      reason: 'model_selector input.utterance should match sent utterance',
    );

    // Verify output contains selected model
    final selectedModel = lastModelInv.output?['selectedModel'] as String?;
    expect(
      selectedModel,
      isNotNull,
      reason: 'model_selector output should include selectedModel',
    );
    expect(
      availableModelKeys,
      contains(selectedModel),
      reason: 'Selected model "$selectedModel" must be in available models',
    );
    print('   Selected model: $selectedModel');

    // Verify confidence is present and valid
    final confidence = lastModelInv.output?['confidence'] as double?;
    expect(
      confidence,
      isNotNull,
      reason: 'model_selector output should include confidence',
    );
    expect(
      confidence,
      inInclusiveRange(0.0, 1.0),
      reason: 'confidence should be between 0 and 1',
    );
    print('   Confidence: ${(confidence! * 100).toStringAsFixed(1)}%');

    // Verify sampledScores contains all active models
    final sampledScores = lastModelInv.output?['sampledScores'] as Map<String, dynamic>?;
    expect(
      sampledScores,
      isNotNull,
      reason: 'model_selector output should include sampledScores',
    );
    expect(
      sampledScores!.length,
      equals(availableModelKeys.length),
      reason: 'sampledScores should have entry for each available model',
    );
    for (final key in availableModelKeys) {
      expect(
        sampledScores.containsKey(key),
        isTrue,
        reason: 'sampledScores should include $key',
      );
      final score = sampledScores[key] as double;
      expect(
        score,
        inInclusiveRange(0.0, 1.0),
        reason: 'sampled score for $key should be in [0, 1]',
      );
    }
    print('   Sampled scores validated: ${sampledScores.length} models');

    // ===== VERIFY: Model was used in LLM call =====
    print('\n[Verify] Checking model was used in LLM invocation...');

    final llmInvocations = allInvocations
        .where((inv) => inv.componentType == 'llm')
        .toList();

    print('   Found ${llmInvocations.length} LLM invocations');

    expect(
      llmInvocations.isNotEmpty,
      isTrue,
      reason: 'Should have at least one LLM invocation',
    );

    // ===== TEST: Simulate feedback and verify stats update =====
    print('\n[Test] Simulating positive feedback...');

    // Read initial stats via ModelSelector API
    final initialStats = await modelSelector.getModelStats();
    final initialSuccesses = initialStats[selectedModel]?.successes ?? 0;
    print('   Initial successes for $selectedModel: $initialSuccesses');

    // Simulate positive feedback for the model selection
    await modelSelector.trainFromFeedback(
      lastModelInv,
      core.Feedback(
        invocationId: lastModelInv.uuid,
        componentType: 'model_selector',
        action: core.FeedbackAction.confirm,
      ),
    );

    // Read updated stats via ModelSelector API
    final updatedStats = await modelSelector.getModelStats();
    final updatedSuccesses = updatedStats[selectedModel]?.successes ?? 0;
    print('   Updated successes for $selectedModel: $updatedSuccesses');

    expect(
      updatedSuccesses,
      equals(initialSuccesses + 1),
      reason: 'Positive feedback should increment successes by exactly 1',
    );
    print('   ✓ Successes increased: $initialSuccesses → $updatedSuccesses');

    // Verify expected rate increased (or stayed same if already high)
    final initialRate = initialStats[selectedModel]?.expectedRate ?? 0.5;
    final updatedRate = updatedStats[selectedModel]?.expectedRate ?? 0.5;
    expect(
      updatedRate,
      greaterThanOrEqualTo(initialRate),
      reason: 'Expected rate should increase after positive feedback',
    );
    print('   ✓ Expected rate: ${(initialRate * 100).toStringAsFixed(1)}% → ${(updatedRate * 100).toStringAsFixed(1)}%');

    // ===== TEST: Negative feedback decreases expected rate =====
    print('\n[Test] Simulating negative feedback...');

    final beforeNegativeStats = await modelSelector.getModelStats();
    final beforeFailures = beforeNegativeStats[selectedModel]?.failures ?? 0;
    final beforeRate = beforeNegativeStats[selectedModel]?.expectedRate ?? 0.5;

    await modelSelector.trainFromFeedback(
      lastModelInv,
      core.Feedback(
        invocationId: lastModelInv.uuid,
        componentType: 'model_selector',
        action: core.FeedbackAction.deny,
      ),
    );

    final afterNegativeStats = await modelSelector.getModelStats();
    final afterFailures = afterNegativeStats[selectedModel]?.failures ?? 0;
    final afterRate = afterNegativeStats[selectedModel]?.expectedRate ?? 0.5;

    expect(
      afterFailures,
      equals(beforeFailures + 1),
      reason: 'Negative feedback should increment failures by exactly 1',
    );
    expect(
      afterRate,
      lessThan(beforeRate),
      reason: 'Expected rate should decrease after negative feedback',
    );
    print('   ✓ Failures increased: $beforeFailures → $afterFailures');
    print('   ✓ Expected rate decreased: ${(beforeRate * 100).toStringAsFixed(1)}% → ${(afterRate * 100).toStringAsFixed(1)}%');

    // ===== TEST: Multiple turns to verify consistent selection =====
    print('\n[Test] Sending more utterances to verify selection...');

    await t.stt('question');
    await Future.delayed(const Duration(seconds: 2));

    await t.stt('command');
    await Future.delayed(const Duration(seconds: 2));

    // Get all model_selector invocations
    final finalInvocations = await invocationRepo.findAll();
    final finalModelInvs = finalInvocations
        .where((inv) => inv.componentType == 'model_selector')
        .toList();

    print('\n[Verify] Total model_selector invocations: ${finalModelInvs.length}');

    expect(
      finalModelInvs.length,
      greaterThanOrEqualTo(3),
      reason: 'Should have at least 3 model_selector invocations (one per utterance)',
    );

    // Verify all selections were valid
    for (final inv in finalModelInvs) {
      final model = inv.output?['selectedModel'] as String?;
      expect(
        model,
        isNotNull,
        reason: 'Each model_selector invocation should have selectedModel',
      );
      print('   - Selected: $model');
    }

    print('\n=== Model Selection Test PASSED ===');
  },
);
