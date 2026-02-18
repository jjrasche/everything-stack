/// Diagnostic: score curated sentence pairs with bert-wiki-paragraphs.
/// Run with: flutter test integration_test/cohere_diagnostic_test.dart -d windows
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:everything_stack_template/services/slm/onnx_session_pool.dart';
import 'package:everything_stack_template/services/slm/runners/cohere_runner.dart';
import 'package:everything_stack_template/services/slm/tokenizers/wordpiece_tokenizer.dart';

const _modelId = 'bert-wiki-paragraphs';

/// Labeled sentence pairs for diagnostic analysis.
const _diagnosticPairs = <Map<String, String>>[
  // SAME TOPIC: continuation within one subject
  {'a': 'ObjectBox is a high-performance database.', 'b': 'It uses LMDB internally for storage.', 'label': 'same'},
  {'a': 'Flutter supports six platforms.', 'b': 'The rendering engine was recently switched to Impeller.', 'label': 'same'},
  {'a': 'I went to the store yesterday.', 'b': 'They were out of milk so I bought almond milk instead.', 'label': 'same'},
  {'a': 'The SentencePiece tokenizer uses Viterbi decoding.', 'b': 'It finds the maximum likelihood segmentation of the input.', 'label': 'same'},
  {'a': 'We need to handle echo cancellation for the voice pipeline.', 'b': 'Using headphones is a temporary workaround for this.', 'label': 'same'},
  {'a': 'The encoder has six stages.', 'b': 'Normalize and segment are rules-based while the rest use models.', 'label': 'same'},

  // TOPIC BOUNDARY: clear shift to unrelated subject
  {'a': 'ObjectBox is a high-performance database.', 'b': 'I need to pick up groceries after work.', 'label': 'boundary'},
  {'a': 'The authentication system uses JWT tokens.', 'b': 'My daughter has a wrestling meet on Saturday.', 'label': 'boundary'},
  {'a': 'We should deploy to production after the tests pass.', 'b': 'The weather forecast says rain tomorrow.', 'label': 'boundary'},
  {'a': 'The NLI model outputs three logits for classification.', 'b': 'I think we should order pizza for dinner tonight.', 'label': 'boundary'},
  {'a': 'SetFit can train with only 8 to 16 examples per class.', 'b': 'The kids need new shoes before school starts.', 'label': 'boundary'},
  {'a': 'DeBERTa uses disentangled attention with relative position.', 'b': 'Traffic was really bad on the highway this morning.', 'label': 'boundary'},

  // SUBTLE BOUNDARY: same domain but different sub-topic
  {'a': 'The encoder normalize stage restores punctuation.', 'b': 'The dedup stage uses NLI for semantic comparison.', 'label': 'subtle'},
  {'a': 'Flutter uses Skia for rendering on older devices.', 'b': 'Dart compiles to native ARM code for mobile platforms.', 'label': 'subtle'},
  {'a': 'I have a meeting with the team at 3pm.', 'b': 'The quarterly report is due next Friday.', 'label': 'subtle'},
  {'a': 'The voice pipeline captures audio from the microphone.', 'b': 'The context panel shows search results ranked by relevance.', 'label': 'subtle'},

  // CONTRADICTION: opposing claims (same topic but conflicting)
  {'a': 'Flutter uses Skia for rendering.', 'b': 'Flutter uses Impeller, not Skia.', 'label': 'contradiction'},
  {'a': 'The database is very fast.', 'b': 'The database is extremely slow and unreliable.', 'label': 'contradiction'},
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late OnnxSessionPool sessionPool;
  late CohereRunner cohereRunner;

  setUpAll(() async {
    final vocabFile = File('assets/models/bert_wiki_paragraphs_vocab.json');
    final modelFile = File('assets/models/bert_wiki_paragraphs.onnx');
    if (!vocabFile.existsSync() || !modelFile.existsSync()) {
      fail('Run: python scripts/export_coherence_model.py');
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
  });

  tearDownAll(() async {
    await sessionPool.disposeAll();
  });

  testWidgets('diagnostic: score curated pairs', (tester) async {
    debugPrint('\n${'=' * 80}');
    debugPrint('BERT-WIKI-PARAGRAPHS COHERENCE DIAGNOSTIC');
    debugPrint('${'=' * 80}\n');

    final resultsByLabel = <String, List<Map<String, dynamic>>>{};

    for (final pair in _diagnosticPairs) {
      final result = await cohereRunner.score(pair['a']!, pair['b']!);
      final label = pair['label']!;

      resultsByLabel.putIfAbsent(label, () => []);
      resultsByLabel[label]!.add({
        'a': pair['a'],
        'b': pair['b'],
        'sameTopic': result.sameTopicScore,
        'diffTopic': result.differentTopicScore,
      });

      debugPrint('[$label] same=${result.sameTopicScore.toStringAsFixed(3)} '
          'diff=${result.differentTopicScore.toStringAsFixed(3)}');
      debugPrint('  A: ${pair['a']}');
      debugPrint('  B: ${pair['b']}\n');
    }

    debugPrint('${'=' * 80}');
    debugPrint('AVERAGES BY LABEL');
    debugPrint('${'=' * 80}');

    for (final label in ['same', 'subtle', 'boundary', 'contradiction']) {
      final items = resultsByLabel[label] ?? [];
      if (items.isEmpty) continue;

      final avgSame = items.map((i) => i['sameTopic'] as double).reduce((a, b) => a + b) / items.length;
      final avgDiff = items.map((i) => i['diffTopic'] as double).reduce((a, b) => a + b) / items.length;

      debugPrint('$label (${items.length} pairs): '
          'sameTopic=${avgSame.toStringAsFixed(3)} '
          'diffTopic=${avgDiff.toStringAsFixed(3)}');
    }
  });
}
