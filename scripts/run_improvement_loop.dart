/// Run prompt improvement cycles on golden conversation data.
///
/// Loads golden conversations, runs ExtractionImprovementLoop to
/// mutate the extraction prompt, validates against baseline, and
/// saves improved versions to PromptVersionRepository.
///
/// Usage:
///   dart run scripts/run_improvement_loop.dart [--input=lib/training/extraction/golden] [--output=lib/training/extraction/golden/evaluations] [--max-attempts=3] [--cycles=1]
///
/// Prerequisites:
///   - .env with GROQ_API_KEY
///   - Golden conversations exported via: dart run scripts/query_imported_conversations.dart --export=uuid1,uuid2

import 'dart:io';
import 'dart:convert';

import 'script_bootstrap.dart';

import '../lib/services/prompt/prompt_improvement_loop.dart';

// ============ Orchestrator ============

Future<void> main(List<String> args) async {
  final inputDir = parseArg(args, 'input', 'lib/training/extraction/golden');
  final outputDir = parseArg(args, 'output', 'lib/training/extraction/golden/evaluations');
  final maxAttempts = int.tryParse(parseArg(args, 'max-attempts', '3')) ?? 3;
  final cycleCount = int.tryParse(parseArg(args, 'cycles', '1')) ?? 1;

  final pipeline = await initializeExtractionPipeline();

  try {
    final conversations = await loadGoldenConversations(inputDir);
    print('Loaded ${conversations.length} golden conversations');
    print('Running $cycleCount cycle(s) with up to $maxAttempts mutation attempts each\n');

    final goldenTurnSets = conversations.map((c) => c.turns).toList();

    for (var cycle = 0; cycle < cycleCount; cycle++) {
      print('=' * 60);
      print('Improvement cycle ${cycle + 1}/$cycleCount');
      print('=' * 60);

      final result = await runCycle(pipeline, goldenTurnSets, maxAttempts);
      printCycleResult(result, cycle);
      await saveCycleResult(outputDir, result, cycle);

      if (!result.improved) {
        print('No improvement found. Stopping.\n');
        break;
      }
    }

    await printPromptHistory(pipeline);
  } finally {
    pipeline.dispose();
  }
}

// ============ Concept Functions ============

Future<ImprovementCycleResult> runCycle(
  ExtractionPipeline pipeline,
  List<List<Map<String, dynamic>>> goldenTurnSets,
  int maxAttempts,
) {
  return pipeline.improvementLoop.runCycle(
    goldenConversations: goldenTurnSets,
    maxMutationAttempts: maxAttempts,
  );
}

void printCycleResult(ImprovementCycleResult result, int cycleIndex) {
  print('');
  if (result.improved) {
    print('IMPROVED: version ${result.newVersion}');
    print('Reason: ${result.reasoning}');
  } else {
    print('NOT IMPROVED: ${result.reasoning}');
  }

  print('Duration: ${result.duration.inSeconds}s');

  if (result.baselineMetrics.isNotEmpty) {
    print('Baseline fInsight: ${result.baselineMetrics['fInsight']}');
  }
  if (result.candidateMetrics.isNotEmpty) {
    print('Candidate fInsight: ${result.candidateMetrics['fInsight']}');
  }

  if (result.validation != null) {
    final v = result.validation!;
    if (v.regressions.isNotEmpty) {
      print('Regressions: ${v.regressions.join("; ")}');
    }
  }

  print('');
}

Future<void> saveCycleResult(
  String outputDir,
  ImprovementCycleResult result,
  int cycleIndex,
) async {
  final directory = Directory(outputDir);
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

  final output = {
    'cycleIndex': cycleIndex,
    'timestamp': DateTime.now().toIso8601String(),
    ...result.toJson(),
  };

  final file = File('$outputDir/improvement_cycle_$cycleIndex.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(output));
  print('Saved: ${file.path}');
}

Future<void> printPromptHistory(ExtractionPipeline pipeline) async {
  final versions = await pipeline.promptRegistry.getAllVersions();

  print('=' * 60);
  print('Prompt Version History');
  print('=' * 60);

  if (versions.isEmpty) {
    print('No saved versions. Using hardcoded default (version 0).');
    return;
  }

  for (final v in versions) {
    final active = v.isActive ? ' [ACTIVE]' : '';
    print('Version ${v.version}$active');
    print('  Reason: ${v.reason}');
    print('  Created: ${v.createdAt.toIso8601String()}');
    print('  Prompt length: ${v.promptText.length} chars');
    if (v.metrics.isNotEmpty) {
      print('  Metrics: ${const JsonEncoder().convert(v.metrics)}');
    }
    print('');
  }
}
