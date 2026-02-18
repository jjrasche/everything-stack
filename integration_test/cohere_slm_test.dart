/// End-to-end cohere SLM: runs bert-wiki-paragraphs on all 33 golden conversations.
/// Reads segment_output/, runs pairwise coherence scoring, writes cohere_output/.
///
/// Prerequisites:
///   python scripts/export_coherence_model.py  (downloads model + vocab)
///
/// Run with:
///   flutter test integration_test/cohere_slm_test.dart -d windows
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:everything_stack_template/services/memory/encoder_trace.dart';
import 'package:everything_stack_template/services/memory/stages/cohere_stage.dart';
import 'package:everything_stack_template/services/slm/onnx_session_pool.dart';
import 'package:everything_stack_template/services/slm/runners/cohere_runner.dart';
import 'package:everything_stack_template/services/slm/tokenizers/wordpiece_tokenizer.dart';

const _modelId = 'bert-wiki-paragraphs';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final segmentDir = 'lib/training/extraction/golden/segment_output';
  final outputDir = 'lib/training/extraction/golden/cohere_output';
  final vocabPath = 'assets/models/bert_wiki_paragraphs_vocab.json';
  final modelPath = 'assets/models/bert_wiki_paragraphs.onnx';

  late OnnxSessionPool sessionPool;
  late CohereRunner cohereRunner;
  late CohereStage cohereStage;

  setUpAll(() async {
    final vocabFile = File(vocabPath);
    final modelFile = File(modelPath);
    if (!vocabFile.existsSync()) {
      fail('Vocab not found at $vocabPath. Run: python scripts/export_coherence_model.py');
    }
    if (!modelFile.existsSync()) {
      fail('Model not found at $modelPath. Run: python scripts/export_coherence_model.py');
    }

    final vocabJson = jsonDecode(await vocabFile.readAsString());
    final tokenizer = WordPieceTokenizer.fromJson(vocabJson);

    sessionPool = OnnxSessionPool();
    cohereRunner = CohereRunner(
      sessionPool: sessionPool,
      tokenizer: tokenizer,
      modelId: _modelId,
      assetPath: modelFile.absolute.path,
    );

    cohereStage = CohereStage(cohereRunner: cohereRunner);
  });

  tearDownAll(() async {
    await sessionPool.disposeAll();
  });

  testWidgets('cohere all golden conversations', (tester) async {
    await Directory(outputDir).create(recursive: true);

    final segmentFiles = await Directory(segmentDir)
        .list()
        .where((e) => e.path.endsWith('.json'))
        .toList();
    segmentFiles.sort((a, b) => a.path.compareTo(b.path));

    debugPrint('Processing ${segmentFiles.length} conversations...\n');

    var totalTurns = 0;
    var totalPairs = 0;
    var totalBoundaries = 0;
    var totalSpans = 0;

    for (final file in segmentFiles) {
      final content = await File(file.path).readAsString();
      final segmentData = jsonDecode(content) as Map<String, dynamic>;
      final uuid = segmentData['conversationUuid'] as String;
      final name = segmentData['conversationName'] as String;
      final turns = segmentData['turns'] as List<dynamic>;

      // Resume: skip if output already exists
      final outputFile = File('$outputDir/$uuid.json');
      if (outputFile.existsSync()) {
        debugPrint('  SKIP $name (output exists)');
        continue;
      }

      final turnOutputs = <Map<String, dynamic>>[];

      for (final turn in turns) {
        final turnMap = turn as Map<String, dynamic>;
        final sentencesRaw = turnMap['sentences'] as List<dynamic>;

        final sentences = sentencesRaw
            .map((s) => Sentence(
                  id: (s as Map<String, dynamic>)['id'] as String,
                  text: s['text'] as String,
                ))
            .toList();

        final result = await cohereStage.process(
          CohereInput(sentences: sentences),
        );

        totalTurns++;
        totalPairs += result.trace.pairScores.length;
        totalBoundaries +=
            result.trace.pairScores.where((p) => p.boundary).length;
        totalSpans += result.spans.length;

        turnOutputs.add({
          'turnIndex': turnMap['turnIndex'],
          'speaker': turnMap['speaker'],
          'sentenceCount': sentences.length,
          'spanCount': result.spans.length,
          'boundaryCount':
              result.trace.pairScores.where((p) => p.boundary).length,
          'latencyMs': result.trace.latencyMs,
          'pairScores': result.trace.pairScores
              .map((p) => p.toJson())
              .toList(),
          'spans': result.spans.map((s) => s.toJson()).toList(),
        });
      }

      final output = {
        'conversationUuid': uuid,
        'conversationName': name,
        'turnCount': turns.length,
        'stage': 'cohere',
        'model': _modelId,
        'threshold': 0.5,
        'turns': turnOutputs,
      };

      await outputFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(output),
      );

      final spanCount = turnOutputs.fold<int>(
          0, (sum, t) => sum + (t['spanCount'] as int));
      final boundaryCount = turnOutputs.fold<int>(
          0, (sum, t) => sum + (t['boundaryCount'] as int));

      debugPrint(
          '  $name: ${turns.length} turns, $spanCount spans, $boundaryCount boundaries');
    }

    debugPrint('\n--- Summary ---');
    debugPrint('Total turns: $totalTurns');
    debugPrint('Total pairs scored: $totalPairs');
    debugPrint('Total boundaries: $totalBoundaries');
    debugPrint('Total spans: $totalSpans');
    if (totalPairs > 0) {
      debugPrint(
          'Boundary rate: ${(totalBoundaries / totalPairs * 100).toStringAsFixed(1)}%');
    }
    debugPrint(
        'Avg spans/turn: ${totalTurns > 0 ? (totalSpans / totalTurns).toStringAsFixed(1) : 'N/A'}');
  });
}
