/// End-to-end golden data extraction + evaluation pipeline.
///
/// Queries imported conversations from ObjectBox, selects diverse candidates,
/// runs AtomicInsightExtractor + ExtractionEvaluator, and writes results
/// to lib/training/extraction/golden/evaluations/ for human review.
///
/// Run:
///   flutter test test/services/extraction/run_golden_pipeline_test.dart --timeout=none
///
/// Requires .env with GROQ_API_KEY. Writes to production ObjectBox store.

import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:objectbox/objectbox.dart';

import 'package:everything_stack_template/objectbox.g.dart';
import 'package:everything_stack_template/persistence/objectbox/wrappers/invocation_ob.dart';
import 'package:everything_stack_template/persistence/objectbox/invocation_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/adaptation_state_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/feedback_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/atomic_insight_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/prompt_version_objectbox_adapter.dart';

import 'package:everything_stack_template/services/inference_service.dart';
import 'package:everything_stack_template/services/implementations/groq_implementer.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/extraction/atomic_insight_extractor.dart';
import 'package:everything_stack_template/training/extraction/extraction_evaluator.dart';
import 'package:everything_stack_template/training/extraction/extraction_eval_types.dart';
import 'package:everything_stack_template/services/prompt/prompt_registry.dart';

import 'package:everything_stack_template/domain/atomic_insight.dart';
import 'package:everything_stack_template/domain/atomic_insight_repository.dart';
import 'package:everything_stack_template/domain/prompt_version_repository.dart';
import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/tools/import/claude_import_tool.dart';
import 'package:get_it/get_it.dart';

// ============ Data Types ============

class _ConversationCandidate {
  final String uuid;
  final String name;
  final int turnCount;
  final int totalChars;
  final int technicalWordCount;
  final DateTime firstTurnDate;
  final List<Map<String, dynamic>> turns;

  _ConversationCandidate({
    required this.uuid,
    required this.name,
    required this.turnCount,
    required this.totalChars,
    required this.technicalWordCount,
    required this.firstTurnDate,
    required this.turns,
  });

  double get avgCharsPerTurn => totalChars / turnCount;
  double get technicalDensity => technicalWordCount / turnCount;

  /// Bucketed category for diversity selection
  String get lengthBucket {
    if (turnCount <= 3) return 'short';
    if (turnCount <= 8) return 'medium';
    return 'long';
  }

  String get densityBucket {
    if (technicalDensity < 0.3) return 'personal';
    if (technicalDensity < 0.7) return 'mixed';
    return 'technical';
  }
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

class _ConversationResult {
  final _ConversationCandidate conversation;
  final List<_EvaluatedInsight> insights;
  final ExtractionSetEvaluation setEvaluation;

  _ConversationResult({
    required this.conversation,
    required this.insights,
    required this.setEvaluation,
  });
}

void main() {
  late Store store;
  late InferenceService inferenceService;
  late AtomicInsightExtractor extractor;
  late ExtractionEvaluator evaluator;
  late PromptRegistry promptRegistry;
  late EvaluationWeights weights;

  setUpAll(() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Will skip in test body
    }
  });

  test('golden data extraction + evaluation pipeline', () async {
    // ============ Guard: require API key ============
    final groqKey = dotenv.env['GROQ_API_KEY'];
    if (groqKey == null || groqKey.isEmpty) {
      markTestSkipped('GROQ_API_KEY not found in .env');
      return;
    }

    // ============ Bootstrap services ============
    print('\n=== Initializing pipeline ===');
    print('WARNING: Writing insights to production ObjectBox store.\n');

    // Find the production ObjectBox store.
    // The Flutter app uses defaultStoreDirectory() which resolves via
    // path_provider. In unit tests, path_provider isn't available, so
    // we probe known locations.
    final storePath = await _findProductionStore();
    print('Opening store at: $storePath');
    store = await openStore(directory: storePath);

    final invocationAdapter = InvocationObjectBoxAdapter(store);
    final adaptationStateAdapter = AdaptationStateObjectBoxAdapter(store);

    inferenceService = InferenceService(
      implementers: {
        'groq': GroqImplementer(apiKey: groqKey, maxRetries: 6),
      },
      defaultImplementer: 'groq',
      invocationRepo: invocationAdapter,
      adaptationStateRepo: adaptationStateAdapter,
      feedbackRepo: FeedbackObjectBoxAdapter(store),
    );

    // Trainable mixin on InferenceService resolves these from GetIt
    // for invocation logging. Register them so evaluation calls don't fail.
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<EntityRepository<Invocation>>()) {
      final invocationRepo = EntityRepository<Invocation>(
        adapter: invocationAdapter,
        embeddingService: NullEmbeddingService(),
        handlers: [],
      );
      getIt.registerSingleton<EntityRepository<Invocation>>(invocationRepo);
    }
    if (!getIt.isRegistered<AdaptationStateRepository>()) {
      getIt.registerSingleton<AdaptationStateRepository>(adaptationStateAdapter);
    }

    // NullEmbeddingService disables semantic dedup intentionally.
    // Golden evaluation needs ALL extractions, not filtered against
    // production data.
    final insightRepo = AtomicInsightRepository(
      adapter: AtomicInsightObjectBoxAdapter(store),
      embeddingService: NullEmbeddingService(),
    );

    final promptVersionRepo = PromptVersionRepository(
      adapter: PromptVersionObjectBoxAdapter(store),
      embeddingService: NullEmbeddingService(),
    );

    promptRegistry = PromptRegistry(
      repo: promptVersionRepo,
      componentType: 'extraction_prompt',
      hardcodedDefault: AtomicInsightExtractor.defaultSystemPrompt,
    );

    const extractionModel = 'llama-3.1-8b-instant';

    extractor = AtomicInsightExtractor(
      insightRepo: insightRepo,
      inferenceService: inferenceService,
      promptRegistry: promptRegistry,
      model: extractionModel,
    );

    evaluator = ExtractionEvaluator(
      inferenceService: inferenceService,
      model: extractionModel,
    );

    weights = evaluator.weights;

    // ============ Step 0: Import conversations if store is empty ============
    final existingCount = _countImportedTurns(store);
    if (existingCount == 0) {
      print('=== No imported conversations found. Importing from Claude exports ===');
      await _importClaudeExports(invocationAdapter);
    } else {
      print('=== Found $existingCount imported turns in store ===');
    }

    // ============ Step 1: Query all conversations ============
    print('\n=== Querying imported conversations ===');
    final allCandidates = _queryConversations(store);
    print('Found ${allCandidates.length} conversations\n');

    if (allCandidates.length < 5) {
      print('Not enough conversations for golden data (need at least 5)');
      print('Place Claude exports in ~/Downloads/data-*/conversations.json');
      store.close();
      return;
    }

    // ============ Step 2: Select diverse subset ============
    print('=== Selecting diverse subset ===');
    final selected = _selectDiverseSubset(allCandidates, targetCount: 30);
    print('Selected ${selected.length} conversations for evaluation');
    _printSelectionSummary(selected);

    // ============ Step 3: Export selected conversations ============
    print('\n=== Exporting conversations ===');
    await _exportConversations(selected);

    // ============ Step 4: Extract + Evaluate ============
    print('\n=== Running extraction + evaluation ===');
    final results = <_ConversationResult>[];

    for (var i = 0; i < selected.length; i++) {
      final conv = selected[i];
      print('[${i + 1}/${selected.length}] ${conv.name} '
          '(${conv.turnCount} turns, ${conv.lengthBucket}/${conv.densityBucket})');

      try {
        final extracted = await extractor.extractFromConversation(
          turns: conv.turns,
          batchSize: 5,
        );

        final insightContents = extracted.map((i) => i.content).toList();

        // Groq free tier: 30 req/min. Evaluate in batches of 5 with
        // cooldown pauses to stay under the rate limit.
        final setEval = await _evaluateWithRateLimit(
          evaluator: evaluator,
          sourceTurns: conv.turns,
          insights: insightContents,
        );

        final evaluatedInsights = <_EvaluatedInsight>[];
        for (var j = 0; j < extracted.length; j++) {
          final insight = extracted[j];
          final evalScore = j < setEval.insightScores.length
              ? setEval.insightScores[j]
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

        results.add(_ConversationResult(
          conversation: conv,
          insights: evaluatedInsights,
          setEvaluation: setEval,
        ));

        print('  ${extracted.length} insights, '
            'fInsight=${setEval.fInsight.toStringAsFixed(2)}');
      } catch (e) {
        print('  ERROR: $e');
      }

      // Rate limit cooldown between conversations
      if (i < selected.length - 1) {
        await Future.delayed(const Duration(seconds: 8));
      }
    }

    // ============ Step 5: Write results ============
    print('\n=== Writing evaluation results ===');
    await _writeResults(results, promptRegistry, weights);

    // ============ Step 6: Print summary ============
    _printSummary(results, weights);
    _printWeakestInsights(results, weights);

    // ============ Cleanup ============
    await GetIt.instance.reset();
    store.close();

    // Assert something meaningful so the test isn't vacuous
    expect(results, isNotEmpty, reason: 'Should have evaluated at least one conversation');
  }, timeout: const Timeout(Duration(minutes: 30)));
}

// ============ Step 1: Query Conversations ============

List<_ConversationCandidate> _queryConversations(Store store) {
  final box = store.box<InvocationOB>();
  final query = box.query(InvocationOB_.implementer.equals('claude_import')).build();
  final allInvocations = query.find();
  query.close();

  final byConversation = <String, List<InvocationOB>>{};
  for (final inv in allInvocations) {
    final metadata = inv.metadataJson != null
        ? jsonDecode(inv.metadataJson!) as Map<String, dynamic>
        : <String, dynamic>{};
    final convUuid = metadata['sourceConversationUuid'] as String?;
    if (convUuid != null) {
      byConversation.putIfAbsent(convUuid, () => []).add(inv);
    }
  }

  final technicalPattern = RegExp(
    r'\b(function|class|api|database|service|component|implement|'
    r'algorithm|pattern|architecture|repository|entity|query|index|'
    r'semantic|embedding|flutter|dart|objectbox|supabase|groq|'
    r'python|docker|kubernetes|react|typescript|sql|http|websocket|'
    r'machine learning|neural|training|model|inference|prompt)\b',
    caseSensitive: false,
  );

  return byConversation.entries.map((entry) {
    final turns = entry.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    int totalChars = 0;
    int technicalWordCount = 0;
    final turnMaps = <Map<String, dynamic>>[];

    for (final turn in turns) {
      final input = turn.inputJson != null
          ? jsonDecode(turn.inputJson!) as Map<String, dynamic>
          : <String, dynamic>{};
      final output = turn.outputJson != null
          ? jsonDecode(turn.outputJson!) as Map<String, dynamic>
          : <String, dynamic>{};

      final prompt = input['prompt']?.toString() ?? '';
      final response = output['response']?.toString() ?? '';
      totalChars += prompt.length + response.length;

      final combinedText = '$prompt $response';
      technicalWordCount += technicalPattern.allMatches(combinedText).length;

      turnMaps.add({'prompt': prompt, 'response': response});
    }

    final metadata = turns.first.metadataJson != null
        ? jsonDecode(turns.first.metadataJson!) as Map<String, dynamic>
        : <String, dynamic>{};

    return _ConversationCandidate(
      uuid: entry.key,
      name: metadata['sourceConversationName'] as String? ?? 'Unnamed',
      turnCount: turns.length,
      totalChars: totalChars,
      technicalWordCount: technicalWordCount,
      firstTurnDate: turns.first.createdAt,
      turns: turnMaps,
    );
  }).where((c) => c.turnCount >= 2).toList();
}

// ============ Step 2: Select Diverse Subset ============

List<_ConversationCandidate> _selectDiverseSubset(
  List<_ConversationCandidate> candidates, {
  int targetCount = 30,
}) {
  if (candidates.length <= targetCount) return candidates;

  // Group by (lengthBucket, densityBucket) for diversity
  final buckets = <String, List<_ConversationCandidate>>{};
  for (final c in candidates) {
    final key = '${c.lengthBucket}/${c.densityBucket}';
    buckets.putIfAbsent(key, () => []).add(c);
  }

  // Sort each bucket by total chars descending (prefer substantive conversations)
  for (final bucket in buckets.values) {
    bucket.sort((a, b) => b.totalChars.compareTo(a.totalChars));
  }

  // Round-robin across buckets until we hit target
  final selected = <_ConversationCandidate>[];
  final bucketKeys = buckets.keys.toList();
  final indices = {for (final k in bucketKeys) k: 0};

  while (selected.length < targetCount) {
    var addedThisRound = false;
    for (final key in bucketKeys) {
      if (selected.length >= targetCount) break;
      final bucket = buckets[key]!;
      final idx = indices[key]!;
      if (idx < bucket.length) {
        selected.add(bucket[idx]);
        indices[key] = idx + 1;
        addedThisRound = true;
      }
    }
    if (!addedThisRound) break;
  }

  return selected;
}

void _printSelectionSummary(List<_ConversationCandidate> selected) {
  final bucketCounts = <String, int>{};
  for (final c in selected) {
    final key = '${c.lengthBucket}/${c.densityBucket}';
    bucketCounts[key] = (bucketCounts[key] ?? 0) + 1;
  }

  print('Diversity distribution:');
  for (final entry in bucketCounts.entries) {
    print('  ${entry.key}: ${entry.value} conversations');
  }
}

// ============ Step 3: Export ============

Future<void> _exportConversations(List<_ConversationCandidate> conversations) async {
  final exportDir = Directory('lib/training/extraction/golden');
  if (!await exportDir.exists()) {
    await exportDir.create(recursive: true);
  }

  for (final conv in conversations) {
    final testData = {
      'id': 'conv_${conv.uuid.substring(0, 8)}',
      'description': 'Auto-selected: ${conv.lengthBucket}/${conv.densityBucket}, '
          '${conv.turnCount} turns',
      'conversation': {
        'uuid': conv.uuid,
        'name': conv.name,
        'turn_count': conv.turnCount,
        'first_turn_date': conv.firstTurnDate.toIso8601String(),
        'turns': conv.turns.asMap().entries.map((entry) => {
          'turn_index': entry.key,
          'prompt': entry.value['prompt'],
          'response': entry.value['response'],
        }).toList(),
      },
    };

    final filename = 'conv_${conv.uuid.substring(0, 8)}.json';
    final file = File('lib/training/extraction/golden/$filename');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(testData));
  }
  print('Exported ${conversations.length} conversations to lib/training/extraction/golden/');
}

// ============ Step 5: Write Results ============

Future<void> _writeResults(
  List<_ConversationResult> results,
  PromptRegistry registry,
  EvaluationWeights weights,
) async {
  final outputDir = Directory('lib/training/extraction/golden/evaluations');
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }

  final now = DateTime.now().toIso8601String();
  final promptVersion = registry.activeVersion;

  // Per-conversation files
  for (final result in results) {
    final output = {
      'convUuid': result.conversation.uuid,
      'convName': result.conversation.name,
      'turnCount': result.conversation.turnCount,
      'evaluatedAt': now,
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

    final filename = 'conv_${result.conversation.uuid.substring(0, 8)}.json';
    final file = File('lib/training/extraction/golden/evaluations/$filename');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(output));
  }

  // Index file
  final totalInsights = results.fold<int>(0, (sum, r) => sum + r.insights.length);
  final avgFInsight = results.isEmpty
      ? 0.0
      : results.fold<double>(0, (s, r) => s + r.setEvaluation.fInsight) / results.length;
  final avgCoverage = results.isEmpty
      ? 0.0
      : results.fold<double>(0, (s, r) => s + r.setEvaluation.coverage) / results.length;
  final avgFocus = results.isEmpty
      ? 0.0
      : results.fold<double>(0, (s, r) => s + r.setEvaluation.focus) / results.length;

  final aggregatedRates = _aggregateDimensionRates(results);
  final weakestDimension = _findWeakestDimension(aggregatedRates);

  final sortedResults = results.toList()
    ..sort((a, b) => b.setEvaluation.fInsight.compareTo(a.setEvaluation.fInsight));

  final index = {
    'evaluatedAt': now,
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
    'conversations': sortedResults.map((r) => {
      'file': 'conv_${r.conversation.uuid.substring(0, 8)}.json',
      'convName': r.conversation.name,
      'fInsight': r.setEvaluation.fInsight,
      'insightCount': r.insights.length,
      'coverage': r.setEvaluation.coverage,
      'focus': r.setEvaluation.focus,
    }).toList(),
  };

  final indexFile = File('lib/training/extraction/golden/evaluations/index.json');
  await indexFile.writeAsString(const JsonEncoder.withIndent('  ').convert(index));

  print('Wrote ${results.length} result files + index.json to lib/training/extraction/golden/evaluations/');
}

// ============ Step 6: Print Summary ============

void _printSummary(List<_ConversationResult> results, EvaluationWeights weights) {
  final totalInsights = results.fold<int>(0, (sum, r) => sum + r.insights.length);
  final avgFInsight = results.isEmpty
      ? 0.0
      : results.fold<double>(0, (s, r) => s + r.setEvaluation.fInsight) / results.length;

  final aggregatedRates = _aggregateDimensionRates(results);
  final weakestDimension = _findWeakestDimension(aggregatedRates);

  print('\n${'=' * 60}');
  print('EVALUATION SUMMARY');
  print('${'=' * 60}');
  print('Conversations: ${results.length}');
  print('Total insights: $totalInsights');
  print('Avg fInsight: ${avgFInsight.toStringAsFixed(3)}');
  print('');
  print('Dimension pass rates:');

  for (final entry in aggregatedRates.entries) {
    final filled = (entry.value * 20).round();
    final empty = 20 - filled;
    final bar = '[${'+' * filled}${'-' * empty}]';
    print('  ${entry.key.padRight(18)} $bar ${(entry.value * 100).toStringAsFixed(0)}%');
  }

  print('');
  print('Weakest dimension: $weakestDimension');
}

void _printWeakestInsights(List<_ConversationResult> results, EvaluationWeights weights) {
  final allWeak = <({String convName, String content, double score, List<String> failed})>[];

  for (final result in results) {
    for (final insight in result.insights) {
      final score = insight.evaluation.compositeScore(weights);
      final failed = <String>[];
      for (final entry in insight.evaluation.dimensionScores.entries) {
        if (!entry.value) failed.add(entry.key);
      }
      allWeak.add((
        convName: result.conversation.name,
        content: insight.content,
        score: score,
        failed: failed,
      ));
    }
  }

  allWeak.sort((a, b) => a.score.compareTo(b.score));

  final showCount = allWeak.length < 3 ? allWeak.length : 3;
  if (showCount == 0) return;

  print('\n3 weakest insights:');
  print('-' * 60);

  for (var i = 0; i < showCount; i++) {
    final weak = allWeak[i];
    final preview = weak.content.length > 80
        ? '${weak.content.substring(0, 80)}...'
        : weak.content;
    print('  [${weak.score.toStringAsFixed(2)}] "$preview"');
    print('    Conv: ${weak.convName}');
    print('    Failed: ${weak.failed.join(", ")}');
    if (i < showCount - 1) print('');
  }
}

// ============ Rate-Limited Evaluation ============

/// Evaluate insights in batches to respect Groq free tier (30 req/min).
///
/// Splits insights into chunks of [batchSize], evaluates each batch via
/// the evaluator, then pauses [cooldownSeconds] between batches.
/// Reassembles the individual InsightEvaluation scores and recomputes
/// the aggregate coverage/focus across the full set.
Future<ExtractionSetEvaluation> _evaluateWithRateLimit({
  required ExtractionEvaluator evaluator,
  required List<Map<String, dynamic>> sourceTurns,
  required List<String> insights,
  int batchSize = 5,
  int cooldownSeconds = 10,
}) async {
  if (insights.isEmpty) {
    return ExtractionSetEvaluation(
      insightScores: [],
      coverage: 0,
      focus: 0,
    );
  }

  // Small enough to evaluate in one shot
  if (insights.length <= batchSize) {
    await Future.delayed(const Duration(seconds: 5));
    return evaluator.evaluate(
      sourceTurns: sourceTurns,
      insights: insights,
    );
  }

  // Batch evaluation with cooldown pauses
  final allScores = <InsightEvaluation>[];
  for (var start = 0; start < insights.length; start += batchSize) {
    final end = (start + batchSize).clamp(0, insights.length);
    final batch = insights.sublist(start, end);

    if (start > 0) {
      await Future.delayed(Duration(seconds: cooldownSeconds));
    }

    final batchResult = await evaluator.evaluate(
      sourceTurns: sourceTurns,
      insights: batch,
    );
    allScores.addAll(batchResult.insightScores);
  }

  // Recompute aggregate metrics across the full insight set
  final turnsPerExpectedInsight = 3.0;
  final expectedInsights =
      (sourceTurns.length / turnsPerExpectedInsight).ceil().clamp(1, 100);
  final coverage = (insights.length / expectedInsights).clamp(0.0, 1.0);

  // Match ExtractionEvaluator.passingScoreThreshold (0.5)
  final passingInsights = allScores
      .where((e) => e.compositeScore(evaluator.weights) >= 0.5)
      .length;
  final focus = passingInsights / insights.length;

  return ExtractionSetEvaluation(
    insightScores: allScores,
    coverage: coverage,
    focus: focus,
  );
}

// ============ Helpers ============

Map<String, double> _aggregateDimensionRates(List<_ConversationResult> results) {
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

// ============ Step 0: Import ============

int _countImportedTurns(Store store) {
  final box = store.box<InvocationOB>();
  final query = box.query(InvocationOB_.implementer.equals('claude_import')).build();
  final count = query.count();
  query.close();
  return count;
}

Future<void> _importClaudeExports(InvocationObjectBoxAdapter invocationAdapter) async {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';

  final exportDirs = <String>[
    '$home/Downloads',
    '$home\\Downloads',
  ];

  // Deduplicate: on Windows, forward-slash and backslash paths resolve
  // to the same directory. Use canonical paths to avoid importing twice.
  final seenCanonical = <String>{};
  final conversationFiles = <String>[];
  for (final dir in exportDirs) {
    final directory = Directory(dir);
    if (!await directory.exists()) continue;

    await for (final entity in directory.list()) {
      if (entity is Directory && entity.path.contains('data-')) {
        final convFile = File('${entity.path}/conversations.json');
        if (await convFile.exists()) {
          final canonical = await convFile.resolveSymbolicLinks();
          if (seenCanonical.add(canonical)) {
            conversationFiles.add(convFile.path);
          }
        }
      }
    }
  }

  if (conversationFiles.isEmpty) {
    print('No Claude export files found in Downloads.');
    return;
  }

  print('Found ${conversationFiles.length} Claude export file(s)');

  // ClaudeImportTool requires EntityRepository<Invocation>, not
  // InvocationObjectBoxAdapter. Wrap the adapter in an EntityRepository.
  final invocationRepo = EntityRepository<Invocation>(
    adapter: invocationAdapter,
    embeddingService: NullEmbeddingService(),
    handlers: [],
  );
  final importTool = ClaudeImportTool(invocationRepo: invocationRepo);

  for (final path in conversationFiles) {
    print('Importing: $path');
    final result = await importTool.importFromExport(
      conversationsPath: path,
      skipExisting: true,
    );
    print('  Result: $result');
  }
}

/// Probe known locations for the production ObjectBox store.
///
/// path_provider is unavailable in flutter test (no platform channel),
/// so we check the paths the app uses on Windows:
/// 1. Documents/objectbox (defaultStoreDirectory on Windows)
/// 2. objectbox/ in project root (fallback for scripts)
Future<String> _findProductionStore() async {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';

  final candidates = [
    '$home/Documents/objectbox',
    '$home\\Documents\\objectbox',
    'objectbox',
  ];

  for (final path in candidates) {
    final dataFile = File('$path/data.mdb');
    if (await dataFile.exists()) {
      final size = await dataFile.length();
      print('  Found store at $path (${(size / 1024).toStringAsFixed(0)} KB)');
      // Prefer stores with actual data (>100KB suggests imported conversations)
      if (size > 100 * 1024) {
        return path;
      }
    }
  }

  // Fall back to first existing store even if small
  for (final path in candidates) {
    final dataFile = File('$path/data.mdb');
    if (await dataFile.exists()) {
      return path;
    }
  }

  // Last resort: create a fresh store at project root
  print('  No existing store found, creating fresh at objectbox/');
  return 'objectbox';
}
