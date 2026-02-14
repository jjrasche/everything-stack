import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../core/debug/debug_introspectable.dart';
import '../inference_service.dart';
import 'extraction_eval_types.dart';

class ExtractionEvaluator with DebugIntrospectable {
  static const String _judgeModel = 'llama-3.3-70b-versatile';

  /// Heuristic: ~1 insight per 3 conversational turns
  static const int _turnsPerExpectedInsight = 3;

  /// Insights scoring below this weighted threshold count as failures
  static const double passingScoreThreshold = 0.5;

  static const int _responsePreviewLength = 300;

  final InferenceService _inferenceService;
  EvaluationWeights _weights;

  int _evaluationCount = 0;
  DateTime? _lastEvaluationAt;

  ExtractionEvaluator({
    required InferenceService inferenceService,
    EvaluationWeights? weights,
  })  : _inferenceService = inferenceService,
        _weights = weights ?? EvaluationWeights.defaults();

  EvaluationWeights get weights => _weights;

  set weights(EvaluationWeights w) => _weights = w;

  Future<ExtractionSetEvaluation> evaluate({
    required List<Map<String, dynamic>> sourceTurns,
    required List<String> insights,
  }) async {
    final sourceText = _formatSourceTurns(sourceTurns);
    final insightScores = <InsightEvaluation>[];

    for (final insight in insights) {
      try {
        final evaluation = await _evaluateInsight(insight, sourceText);
        insightScores.add(evaluation);
      } catch (e, st) {
        debugPrint('ExtractionEvaluator: Failed to evaluate insight: $e\n$st');
        insightScores.add(InsightEvaluation(
          insightContent: insight,
          groundedness: false,
          atomicity: false,
          selfContainment: false,
          salience: false,
          entityClarity: false,
          formatCompliance: false,
          reasoning: 'Evaluation failed: $e',
        ));
      }
    }

    final expectedInsights =
        (sourceTurns.length / _turnsPerExpectedInsight).ceil().clamp(1, 100);
    final coverage = (insights.length / expectedInsights).clamp(0.0, 1.0);

    final passingInsights = insightScores
        .where((e) => e.compositeScore(_weights) >= passingScoreThreshold)
        .length;
    final focus =
        insights.isEmpty ? 0.0 : passingInsights / insights.length;

    _evaluationCount++;
    _lastEvaluationAt = DateTime.now();

    return ExtractionSetEvaluation(
      insightScores: insightScores,
      coverage: coverage,
      focus: focus,
    );
  }

  String _formatSourceTurns(List<Map<String, dynamic>> turns) {
    final buffer = StringBuffer();
    for (var i = 0; i < turns.length; i++) {
      final prompt = turns[i]['prompt'] as String? ?? '';
      final response = turns[i]['response'] as String? ?? '';
      buffer.writeln('Turn ${i + 1}:');
      buffer.writeln('Human: $prompt');
      final responsePreview = response.length > _responsePreviewLength
          ? '${response.substring(0, _responsePreviewLength)}...'
          : response;
      buffer.writeln('Assistant: $responsePreview');
      buffer.writeln();
    }
    return buffer.toString();
  }

  Future<InsightEvaluation> _evaluateInsight(
    String insight,
    String sourceText,
  ) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _judgeSystemPrompt()},
      {
        'role': 'user',
        'content': '''## Source conversation:
$sourceText

## Extracted insight to evaluate:
"$insight"

Score each dimension (0 or 1) and explain briefly.
Respond in JSON only.''',
      },
    ];

    final response = await _inferenceService.chatWithTools(
      model: _judgeModel,
      messages: messages,
      temperature: 0.1,
      maxTokens: 500,
    );

    return _parseJudgeResponse(insight, response.content ?? '');
  }

  String _judgeSystemPrompt() => '''You are an extraction quality judge. Score an atomic insight extracted from a conversation on 6 binary dimensions.

Dimensions:
1. groundedness (0 or 1): Is this factually supported by the source conversation? Not hallucinated or assumed?
2. atomicity (0 or 1): Does this contain exactly ONE idea? Not a compound statement joining multiple facts?
3. selfContainment (0 or 1): Is this understandable WITHOUT reading the source conversation? No unresolved pronouns or missing context?
4. salience (0 or 1): Would knowing this fact materially change how an AI assistant responds to this user in future conversations? Score 0 if generic, ephemeral, or unactionable.
5. entityClarity (0 or 1): Does this contain at least one identifiable entity (person, tool, project, concept) that could be resolved and linked?
6. formatCompliance (0 or 1): Does it follow "[Fact]. Because [reason]." format with both parts present?

Respond with ONLY a JSON object:
{
  "groundedness": 0 or 1,
  "atomicity": 0 or 1,
  "selfContainment": 0 or 1,
  "salience": 0 or 1,
  "entityClarity": 0 or 1,
  "formatCompliance": 0 or 1,
  "reasoning": "Brief explanation of scores"
}''';

  InsightEvaluation _parseJudgeResponse(String insight, String response) {
    try {
      final jsonMatch =
          RegExp(r'\{[^{}]*\}', dotAll: true).firstMatch(response);
      if (jsonMatch == null) {
        debugPrint('ExtractionEvaluator: No JSON in judge response');
        return _failedEvaluation(insight, 'No JSON in judge response');
      }

      final json = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;

      return InsightEvaluation(
        insightContent: insight,
        groundedness: _toBool(json['groundedness']),
        atomicity: _toBool(json['atomicity']),
        selfContainment: _toBool(json['selfContainment']),
        salience: _toBool(json['salience']),
        entityClarity: _toBool(json['entityClarity']),
        formatCompliance: _toBool(json['formatCompliance']),
        reasoning: json['reasoning'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('ExtractionEvaluator: Parse error: $e');
      return _failedEvaluation(insight, 'Parse error: $e');
    }
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  InsightEvaluation _failedEvaluation(String insight, String reason) {
    return InsightEvaluation(
      insightContent: insight,
      groundedness: false,
      atomicity: false,
      selfContainment: false,
      salience: false,
      entityClarity: false,
      formatCompliance: false,
      reasoning: reason,
    );
  }

  // ============ DebugIntrospectable ============

  @override
  String get debugName => 'evaluator';

  @override
  Map<String, dynamic> getDebugState() => {
        'evaluationCount': _evaluationCount,
        'lastEvaluationAt': _lastEvaluationAt?.toIso8601String(),
        'weights': {
          'groundedness': _weights.groundednessWeight,
          'salience': _weights.salienceWeight,
          'selfContainment': _weights.selfContainmentWeight,
          'atomicity': _weights.atomicityWeight,
          'entityClarity': _weights.entityClarityWeight,
          'format': _weights.formatWeight,
        },
      };

  @override
  Map<String, DebugAction> getDebugActions() => {
        'getWeights': DebugAction(
          description: 'Get current rubric dimension weights',
          handler: (params) async => {
                'groundednessWeight': _weights.groundednessWeight,
                'salienceWeight': _weights.salienceWeight,
                'selfContainmentWeight': _weights.selfContainmentWeight,
                'atomicityWeight': _weights.atomicityWeight,
                'entityClarityWeight': _weights.entityClarityWeight,
                'formatWeight': _weights.formatWeight,
              },
        ),
        'setWeights': DebugAction(
          description: 'Update rubric dimension weights',
          mutates: true,
          parameters: {
            'groundedness': 'Weight for groundedness (0-1)',
            'salience': 'Weight for salience (0-1)',
          },
          handler: (params) async {
            _weights = _weights.copyWith(
              groundednessWeight: params['groundedness'] != null
                  ? double.tryParse(params['groundedness']!)
                  : null,
              salienceWeight: params['salience'] != null
                  ? double.tryParse(params['salience']!)
                  : null,
              selfContainmentWeight: params['selfContainment'] != null
                  ? double.tryParse(params['selfContainment']!)
                  : null,
              atomicityWeight: params['atomicity'] != null
                  ? double.tryParse(params['atomicity']!)
                  : null,
              entityClarityWeight: params['entityClarity'] != null
                  ? double.tryParse(params['entityClarity']!)
                  : null,
              formatWeight: params['format'] != null
                  ? double.tryParse(params['format']!)
                  : null,
            );
            return {
              'success': true,
              'weights': {
                'groundedness': _weights.groundednessWeight,
                'salience': _weights.salienceWeight,
                'selfContainment': _weights.selfContainmentWeight,
                'atomicity': _weights.atomicityWeight,
                'entityClarity': _weights.entityClarityWeight,
                'format': _weights.formatWeight,
              },
            };
          },
        ),
      };
}
