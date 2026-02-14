import 'package:flutter/foundation.dart';

import '../../core/debug/debug_introspectable.dart';
import '../prompt/prompt_improvement_loop.dart';
import '../prompt/prompt_registry.dart';
import '../prompt/prompt_mutator.dart';
import '../prompt/prompt_validator.dart';
import 'atomic_insight_extractor.dart';
import 'extraction_evaluator.dart';
import 'extraction_eval_types.dart';

/// Bridges extraction-specific types to the generic [PromptImprovementLoop].
class ExtractionImprovementLoop with DebugIntrospectable {
  final PromptImprovementLoop<List<Map<String, dynamic>>> _loop;
  final ExtractionEvaluator _evaluator;
  final PromptRegistry _promptRegistry;

  ExtractionImprovementLoop({
    required AtomicInsightExtractor extractor,
    required ExtractionEvaluator evaluator,
    required PromptRegistry promptRegistry,
    required PromptMutator mutator,
    required PromptValidator validator,
  })  : _evaluator = evaluator,
        _promptRegistry = promptRegistry,
        _loop = PromptImprovementLoop<List<Map<String, dynamic>>>(
          registry: promptRegistry,
          mutator: mutator,
          validator: validator,
          dimensions: evaluator.weights.toDimensionSpecs(),
          extractFn: (turns, prompt) async {
            final insights = await extractor.extractFromConversation(
              turns: turns,
              batchSize: 5,
              overridePrompt: prompt,
            );
            return insights.map((i) => i.content).toList();
          },
          evaluateFn: (turns, outputs) async {
            final evaluation = await evaluator.evaluate(
              sourceTurns: turns,
              insights: outputs,
            );

            final failures = evaluation.insightScores
                .where((e) =>
                    e.compositeScore(evaluator.weights) <
                    ExtractionEvaluator.passingScoreThreshold)
                .toList();

            return EvaluationResult(
              failures: failures,
              dimensionRates: evaluation.dimensionPassRates(),
              coverage: evaluation.coverage,
              focus: evaluation.focus,
            );
          },
        );

  bool get isRunning => _loop.isRunning;

  Future<ImprovementCycleResult> runCycle({
    required List<List<Map<String, dynamic>>> goldenConversations,
    int maxMutationAttempts = 3,
  }) {
    return _loop.runCycle(
      goldenInputs: goldenConversations,
      maxMutationAttempts: maxMutationAttempts,
    );
  }

  // ============ DebugIntrospectable ============

  @override
  String get debugName => 'improvement';

  @override
  Map<String, dynamic> getDebugState() => _loop.getDebugState();

  @override
  Map<String, DebugAction> getDebugActions() => {
        'runCycle': DebugAction(
          description:
              'Run one improvement cycle on golden data (requires golden conversations in DB)',
          mutates: true,
          handler: (params) async {
            if (isRunning) {
              return {'error': 'Cycle already running'};
            }

            return {
              'status': 'ready',
              'hint':
                  'Call runCycle() programmatically with golden conversations. '
                      'Use analyzeConversationsForTests to select candidates, '
                      'then exportConversationForTest to prepare them.',
              'promptVersion': _promptRegistry.activeVersion,
            };
          },
        ),
        ..._loop.getDebugActions(),
      };
}
