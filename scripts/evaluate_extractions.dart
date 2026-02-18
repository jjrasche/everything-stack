/// Extract insights from golden conversations and evaluate with 6-dimension rubric.
///
/// Reads exported conversations from lib/training/extraction/golden/turns/*.json,
/// runs AtomicInsightExtractor + ExtractionEvaluator, and writes
/// per-conversation results + summary index to lib/training/extraction/golden/evaluations/.
///
/// Usage:
///   dart run scripts/evaluate_extractions.dart [--input=lib/training/extraction/golden] [--output=lib/training/extraction/golden/evaluations]
///
/// Prerequisites:
///   - .env with GROQ_API_KEY
///   - Golden conversations exported via: dart run scripts/query_imported_conversations.dart --export=uuid1,uuid2

import 'dart:io';
import 'dart:convert';

import 'script_bootstrap.dart';

import '../lib/training/extraction/extraction_eval_types.dart';
import '../lib/services/math/evaluation_math.dart';

// ============ Data Types ============

class ConversationEvaluation {
  final GoldenConversation conversation;
  final List<_EvaluatedInsight> insights;
  final ExtractionSetEvaluation setEvaluation;

  ConversationEvaluation({
    required this.conversation,
    required this.insights,
    required this.setEvaluation,
  });
}

class _EvaluatedInsight {
  final String content;
  final String scope;
  final String? type;
  final InsightEvaluation evaluation;

  _EvaluatedInsight({
    required this.content,
    required this.scope,
    required this.type,
    required this.evaluation,
  });
}

class _WeakInsight {
  final String convName;
  final String content;
  final double compositeScore;
  final List<String> failedDimensions;

  _WeakInsight({
    required this.convName,
    required this.content,
    required this.compositeScore,
    required this.failedDimensions,
  });
}

// ============ Orchestrator ============

Future<void> main(List<String> args) async {
  final inputDir = parseArg(args, 'input', 'lib/training/extraction/golden');
  final outputDir = parseArg(args, 'output', 'lib/training/extraction/golden/evaluations');

  final pipeline = await initializeExtractionPipeline();

  try {
    final conversations = await loadGoldenConversations(inputDir);
    print('Loaded ${conversations.length} golden conversations\n');

    final results = await evaluateAllConversations(pipeline, conversations);
    await writeEvaluationResults(outputDir, results, pipeline);
    printEvaluationSummary(results, pipeline);
    printWeakestInsights(results, pipeline);
  } finally {
    pipeline.dispose();
  }
}

// ============ Concept Functions ============

Future<List<ConversationEvaluation>> evaluateAllConversations(
  ExtractionPipeline pipeline,
  List<GoldenConversation> conversations,
) async {
  final results = <ConversationEvaluation>[];

  for (var i = 0; i < conversations.length; i++) {
    final conv = conversations[i];
    print('[${i + 1}/${conversations.length}] ${conv.convName} (${conv.turnCount} turns)');

    final result = await evaluateConversation(pipeline, conv);
    results.add(result);

    final fInsight = result.setEvaluation.fInsight;
    print('  ${result.insights.length} insights, fInsight=${fInsight.toStringAsFixed(2)}\n');
  }

  return results;
}

Future<ConversationEvaluation> evaluateConversation(
  ExtractionPipeline pipeline,
  GoldenConversation conversation,
) async {
  final extracted = await pipeline.extractor.extractFromConversation(
    turns: conversation.turns,
    batchSize: 5,
  );

  final insightContents = extracted.map((i) => i.content).toList();

  final setEvaluation = await pipeline.evaluator.evaluate(
    sourceTurns: conversation.turns,
    insights: insightContents,
  );

  final evaluatedInsights = <_EvaluatedInsight>[];
  for (var j = 0; j < extracted.length; j++) {
    final insight = extracted[j];
    // Match evaluation scores to insights by index
    final evalScore = j < setEvaluation.insightScores.length
        ? setEvaluation.insightScores[j]
        : InsightEvaluation(
            insightContent: insight.content,
            groundedness: false,
            atomicity: false,
            selfContainment: false,
            salience: false,
            entityClarity: false,
            formatCompliance: false,
            reasoning: 'No evaluation available',
          );

    evaluatedInsights.add(_EvaluatedInsight(
      content: insight.content,
      scope: insight.scope,
      type: insight.type,
      evaluation: evalScore,
    ));
  }

  return ConversationEvaluation(
    conversation: conversation,
    insights: evaluatedInsights,
    setEvaluation: setEvaluation,
  );
}

Future<void> writeEvaluationResults(
  String outputDir,
  List<ConversationEvaluation> results,
  ExtractionPipeline pipeline,
) async {
  final directory = Directory(outputDir);
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

  final now = DateTime.now().toIso8601String();
  final promptVersion = pipeline.promptRegistry.activeVersion;
  final weights = pipeline.evaluator.weights;

  // Write per-conversation files
  for (final result in results) {
    final convOutput = _buildConversationOutput(result, now, promptVersion, weights);
    final filename = 'conv_${result.conversation.convUuid.substring(0, 8)}.json';
    final file = File('$outputDir/$filename');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(convOutput));
  }

  // Write index
  final index = _buildIndex(results, now, promptVersion, weights);
  final indexFile = File('$outputDir/index.json');
  await indexFile.writeAsString(const JsonEncoder.withIndent('  ').convert(index));

  print('Results written to $outputDir/');
  print('  ${results.length} conversation files + index.json\n');
}

void printEvaluationSummary(
  List<ConversationEvaluation> results,
  ExtractionPipeline pipeline,
) {
  final weights = pipeline.evaluator.weights;
  final totalInsights = results.fold<int>(0, (sum, r) => sum + r.insights.length);
  final avgFInsight = results.isEmpty
      ? 0.0
      : results.fold<double>(0, (sum, r) => sum + r.setEvaluation.fInsight) / results.length;

  final aggregatedRates = _aggregateDimensionRates(results);
  final weakestDimension = _findWeakestDimension(aggregatedRates);

  print('=' * 60);
  print('Evaluation Summary');
  print('=' * 60);
  print('Conversations: ${results.length}');
  print('Total insights: $totalInsights');
  print('Avg fInsight: ${avgFInsight.toStringAsFixed(3)}');
  print('Prompt version: ${pipeline.promptRegistry.activeVersion}');
  print('');
  print('Dimension pass rates:');

  for (final entry in aggregatedRates.entries) {
    final bar = _progressBar(entry.value, 20);
    print('  ${entry.key.padRight(18)} $bar ${(entry.value * 100).toStringAsFixed(0)}%');
  }

  print('');
  print('Weakest dimension: $weakestDimension');
}

void printWeakestInsights(
  List<ConversationEvaluation> results,
  ExtractionPipeline pipeline,
) {
  final weights = pipeline.evaluator.weights;
  final allWeak = <_WeakInsight>[];

  for (final result in results) {
    for (final insight in result.insights) {
      final score = insight.evaluation.compositeScore(weights);
      final failed = <String>[];
      final dims = insight.evaluation.dimensionScores;
      for (final entry in dims.entries) {
        if (!entry.value) failed.add(entry.key);
      }

      allWeak.add(_WeakInsight(
        convName: result.conversation.convName,
        content: insight.content,
        compositeScore: score,
        failedDimensions: failed,
      ));
    }
  }

  allWeak.sort((a, b) => a.compositeScore.compareTo(b.compositeScore));

  final showCount = allWeak.length < 3 ? allWeak.length : 3;
  if (showCount == 0) return;

  print('');
  print('3 weakest insights:');
  print('-' * 60);

  for (var i = 0; i < showCount; i++) {
    final weak = allWeak[i];
    final preview = weak.content.length > 80
        ? '${weak.content.substring(0, 80)}...'
        : weak.content;
    print('  [${weak.compositeScore.toStringAsFixed(2)}] "$preview"');
    print('    Conv: ${weak.convName}');
    print('    Failed: ${weak.failedDimensions.join(", ")}');
    if (i < showCount - 1) print('');
  }
}

// ============ Leaf Functions ============

Map<String, dynamic> _buildConversationOutput(
  ConversationEvaluation result,
  String evaluatedAt,
  int promptVersion,
  EvaluationWeights weights,
) {
  return {
    'convUuid': result.conversation.convUuid,
    'convName': result.conversation.convName,
    'turnCount': result.conversation.turnCount,
    'evaluatedAt': evaluatedAt,
    'promptVersion': promptVersion,
    'extraction': {
      'insightCount': result.insights.length,
      'insights': result.insights.map((i) => {
        'content': i.content,
        'scope': i.scope,
        'type': i.type,
        'verified': null,
        'evaluation': {
          ...i.evaluation.toJson(),
          'compositeScore': i.evaluation.compositeScore(weights),
        },
      }).toList(),
    },
    'aggregate': {
      'coverage': result.setEvaluation.coverage,
      'focus': result.setEvaluation.focus,
      'fInsight': result.setEvaluation.fInsight,
      'dimensionPassRates': result.setEvaluation.dimensionPassRates(),
    },
  };
}

Map<String, dynamic> _buildIndex(
  List<ConversationEvaluation> results,
  String evaluatedAt,
  int promptVersion,
  EvaluationWeights weights,
) {
  final totalInsights = results.fold<int>(0, (sum, r) => sum + r.insights.length);
  final avgFInsight = results.isEmpty
      ? 0.0
      : results.fold<double>(0, (sum, r) => sum + r.setEvaluation.fInsight) / results.length;
  final avgCoverage = results.isEmpty
      ? 0.0
      : results.fold<double>(0, (sum, r) => sum + r.setEvaluation.coverage) / results.length;
  final avgFocus = results.isEmpty
      ? 0.0
      : results.fold<double>(0, (sum, r) => sum + r.setEvaluation.focus) / results.length;

  final aggregatedRates = _aggregateDimensionRates(results);
  final weakestDimension = _findWeakestDimension(aggregatedRates);

  // Sort conversations by fInsight descending
  final sortedConvs = results.toList()
    ..sort((a, b) => b.setEvaluation.fInsight.compareTo(a.setEvaluation.fInsight));

  return {
    'evaluatedAt': evaluatedAt,
    'promptVersion': promptVersion,
    'conversationCount': results.length,
    'totalInsights': totalInsights,
    'aggregate': {
      'avgFInsight': avgFInsight,
      'avgCoverage': avgCoverage,
      'avgFocus': avgFocus,
      'dimensionPassRates': aggregatedRates,
      'weakestDimension': weakestDimension,
    },
    'conversations': sortedConvs.map((r) => {
      'file': 'conv_${r.conversation.convUuid.substring(0, 8)}.json',
      'convName': r.conversation.convName,
      'fInsight': r.setEvaluation.fInsight,
      'insightCount': r.insights.length,
      'coverage': r.setEvaluation.coverage,
      'focus': r.setEvaluation.focus,
    }).toList(),
  };
}

Map<String, double> _aggregateDimensionRates(List<ConversationEvaluation> results) {
  if (results.isEmpty) return {};

  final allRates = <String, List<double>>{};
  for (final result in results) {
    final rates = result.setEvaluation.dimensionPassRates();
    for (final entry in rates.entries) {
      allRates.putIfAbsent(entry.key, () => []).add(entry.value);
    }
  }

  return allRates.map((dim, values) =>
      MapEntry(dim, values.fold<double>(0, (a, b) => a + b) / values.length));
}

String _findWeakestDimension(Map<String, double> rates) {
  if (rates.isEmpty) return 'none';
  return rates.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
}

String _progressBar(double fraction, int width) {
  final filled = (fraction * width).round();
  final empty = width - filled;
  return '[${'+' * filled}${'-' * empty}]';
}
