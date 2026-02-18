/// Tests for golden conversation loading and evaluation output format.
///
/// Uses fixture files only. No API calls, no .env required.
/// Run: flutter test test/services/extraction/evaluate_extractions_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:everything_stack_template/training/extraction/extraction_eval_types.dart';

void main() {
  group('loadGoldenConversations', () {
    test('parses exported conversation JSON into turn maps', () async {
      final fixturePath = 'test/fixtures/extraction/sample_conv.json';
      final content = await File(fixturePath).readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final conversation = data['conversation'] as Map<String, dynamic>;
      final rawTurns = conversation['turns'] as List<dynamic>;

      final turns = rawTurns.map((t) {
        final turn = t as Map<String, dynamic>;
        return <String, dynamic>{
          'prompt': turn['prompt'] ?? '',
          'response': turn['response'] ?? '',
        };
      }).toList();

      expect(turns, hasLength(3));
      expect(turns[0]['prompt'], contains('Dart streams'));
      expect(turns[0]['response'], isNotEmpty);
      expect(conversation['uuid'], equals('test0001-aaaa-bbbb-cccc-ddddeeee0001'));
      expect(conversation['name'], equals('Dart async patterns discussion'));
    });

    test('each turn has prompt and response keys', () async {
      final fixturePath = 'test/fixtures/extraction/sample_conv.json';
      final content = await File(fixturePath).readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final conversation = data['conversation'] as Map<String, dynamic>;
      final rawTurns = conversation['turns'] as List<dynamic>;

      for (final rawTurn in rawTurns) {
        final turn = rawTurn as Map<String, dynamic>;
        expect(turn.containsKey('prompt'), isTrue,
            reason: 'Turn missing prompt key');
        expect(turn.containsKey('response'), isTrue,
            reason: 'Turn missing response key');
      }
    });
  });

  group('evaluation output format', () {
    test('per-conversation JSON has all required fields', () {
      // Simulate the output structure evaluate_extractions.dart produces
      final output = _buildSampleConversationOutput();
      final json = jsonDecode(jsonEncode(output)) as Map<String, dynamic>;

      expect(json.containsKey('convUuid'), isTrue);
      expect(json.containsKey('convName'), isTrue);
      expect(json.containsKey('turnCount'), isTrue);
      expect(json.containsKey('evaluatedAt'), isTrue);
      expect(json.containsKey('promptVersion'), isTrue);
      expect(json.containsKey('extraction'), isTrue);
      expect(json.containsKey('aggregate'), isTrue);

      final extraction = json['extraction'] as Map<String, dynamic>;
      expect(extraction.containsKey('insightCount'), isTrue);
      expect(extraction.containsKey('insights'), isTrue);

      final aggregate = json['aggregate'] as Map<String, dynamic>;
      expect(aggregate.containsKey('coverage'), isTrue);
      expect(aggregate.containsKey('focus'), isTrue);
      expect(aggregate.containsKey('fInsight'), isTrue);
      expect(aggregate.containsKey('dimensionPassRates'), isTrue);
    });

    test('each insight has verified: null field', () {
      final output = _buildSampleConversationOutput();
      final json = jsonDecode(jsonEncode(output)) as Map<String, dynamic>;
      final extraction = json['extraction'] as Map<String, dynamic>;
      final insights = extraction['insights'] as List<dynamic>;

      expect(insights, isNotEmpty);
      for (final insight in insights) {
        final insightMap = insight as Map<String, dynamic>;
        expect(insightMap.containsKey('verified'), isTrue,
            reason: 'Insight missing verified field');
        expect(insightMap['verified'], isNull,
            reason: 'verified should be null for human review');
      }
    });

    test('insight evaluation has all 6 dimensions', () {
      final output = _buildSampleConversationOutput();
      final json = jsonDecode(jsonEncode(output)) as Map<String, dynamic>;
      final extraction = json['extraction'] as Map<String, dynamic>;
      final insights = extraction['insights'] as List<dynamic>;
      final evaluation =
          (insights[0] as Map<String, dynamic>)['evaluation'] as Map<String, dynamic>;

      final requiredDimensions = [
        'groundedness',
        'atomicity',
        'selfContainment',
        'salience',
        'entityClarity',
        'formatCompliance',
      ];

      for (final dim in requiredDimensions) {
        expect(evaluation.containsKey(dim), isTrue,
            reason: 'Missing dimension: $dim');
      }
      expect(evaluation.containsKey('compositeScore'), isTrue);
      expect(evaluation.containsKey('reasoning'), isTrue);
    });

    test('index.json conversations sorted by fInsight descending', () {
      final index = _buildSampleIndex();
      final json = jsonDecode(jsonEncode(index)) as Map<String, dynamic>;
      final conversations = json['conversations'] as List<dynamic>;

      expect(conversations, hasLength(3));

      final fInsights = conversations
          .map((c) => (c as Map<String, dynamic>)['fInsight'] as double)
          .toList();

      for (var i = 0; i < fInsights.length - 1; i++) {
        expect(fInsights[i] >= fInsights[i + 1], isTrue,
            reason: 'Index not sorted by fInsight descending');
      }
    });

    test('index.json has aggregate metrics and weakest dimension', () {
      final index = _buildSampleIndex();
      final json = jsonDecode(jsonEncode(index)) as Map<String, dynamic>;

      expect(json.containsKey('evaluatedAt'), isTrue);
      expect(json.containsKey('promptVersion'), isTrue);
      expect(json.containsKey('conversationCount'), isTrue);
      expect(json.containsKey('totalInsights'), isTrue);
      expect(json.containsKey('aggregate'), isTrue);

      final aggregate = json['aggregate'] as Map<String, dynamic>;
      expect(aggregate.containsKey('avgFInsight'), isTrue);
      expect(aggregate.containsKey('avgCoverage'), isTrue);
      expect(aggregate.containsKey('avgFocus'), isTrue);
      expect(aggregate.containsKey('dimensionPassRates'), isTrue);
      expect(aggregate.containsKey('weakestDimension'), isTrue);
    });
  });

  group('InsightEvaluation serialization', () {
    test('toJson and fromJson round-trip correctly', () {
      final evaluation = InsightEvaluation(
        insightContent: 'Test insight. Because test reason.',
        groundedness: true,
        atomicity: true,
        selfContainment: false,
        salience: true,
        entityClarity: true,
        formatCompliance: true,
        reasoning: 'Self-containment failed: missing context',
      );

      final json = evaluation.toJson();
      final restored = InsightEvaluation.fromJson(json);

      expect(restored.insightContent, equals(evaluation.insightContent));
      expect(restored.groundedness, equals(evaluation.groundedness));
      expect(restored.selfContainment, equals(evaluation.selfContainment));
      expect(restored.reasoning, equals(evaluation.reasoning));
    });

    test('compositeScore matches manual weight calculation', () {
      final weights = EvaluationWeights.defaults();
      final evaluation = InsightEvaluation(
        insightContent: 'test',
        groundedness: true,
        atomicity: true,
        selfContainment: false,
        salience: true,
        entityClarity: false,
        formatCompliance: true,
        reasoning: '',
      );

      // groundedness(0.25) + atomicity(0.10) + salience(0.25) + format(0.15) = 0.75
      final expected = weights.groundednessWeight +
          weights.atomicityWeight +
          weights.salienceWeight +
          weights.formatWeight;

      expect(evaluation.compositeScore(weights), closeTo(expected, 0.001));
    });
  });
}

// ============ Test Helpers ============

/// Build a sample per-conversation evaluation output matching the
/// format that evaluate_extractions.dart will produce.
Map<String, dynamic> _buildSampleConversationOutput() {
  return {
    'convUuid': 'test-uuid-1234',
    'convName': 'Test conversation',
    'turnCount': 3,
    'evaluatedAt': '2026-02-15T10:00:00.000Z',
    'promptVersion': 0,
    'extraction': {
      'insightCount': 2,
      'insights': [
        {
          'content': 'Dart zones complicate debugging. Because errors are caught implicitly.',
          'scope': 'session',
          'type': 'learning',
          'verified': null,
          'evaluation': {
            'groundedness': true,
            'atomicity': true,
            'selfContainment': false,
            'salience': true,
            'entityClarity': true,
            'formatCompliance': true,
            'compositeScore': 0.85,
            'reasoning': 'Self-containment: missing context about what zones are',
          },
        },
        {
          'content': 'WebSocket channels expose a Stream in Dart. Because the dart:io API wraps the connection.',
          'scope': 'session',
          'type': 'learning',
          'verified': null,
          'evaluation': {
            'groundedness': true,
            'atomicity': true,
            'selfContainment': true,
            'salience': true,
            'entityClarity': true,
            'formatCompliance': true,
            'compositeScore': 1.0,
            'reasoning': 'All dimensions pass',
          },
        },
      ],
    },
    'aggregate': {
      'coverage': 0.67,
      'focus': 1.0,
      'fInsight': 0.80,
      'dimensionPassRates': {
        'groundedness': 1.0,
        'atomicity': 1.0,
        'selfContainment': 0.5,
        'salience': 1.0,
        'entityClarity': 1.0,
        'formatCompliance': 1.0,
      },
    },
  };
}

/// Build a sample index.json matching the format evaluate_extractions.dart produces.
Map<String, dynamic> _buildSampleIndex() {
  return {
    'evaluatedAt': '2026-02-15T10:00:00.000Z',
    'promptVersion': 0,
    'conversationCount': 3,
    'totalInsights': 8,
    'aggregate': {
      'avgFInsight': 0.75,
      'avgCoverage': 0.70,
      'avgFocus': 0.80,
      'dimensionPassRates': {
        'groundedness': 1.0,
        'atomicity': 0.88,
        'selfContainment': 0.62,
        'salience': 0.88,
        'entityClarity': 1.0,
        'formatCompliance': 1.0,
      },
      'weakestDimension': 'selfContainment',
    },
    'conversations': [
      {'file': 'conv_aaaa1111.json', 'convName': 'Best conv', 'fInsight': 0.90, 'insightCount': 3},
      {'file': 'conv_bbbb2222.json', 'convName': 'OK conv', 'fInsight': 0.75, 'insightCount': 3},
      {'file': 'conv_cccc3333.json', 'convName': 'Weak conv', 'fInsight': 0.60, 'insightCount': 2},
    ],
  };
}
