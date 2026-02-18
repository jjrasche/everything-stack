/// End-to-end punctuation SLM: downloads real model, runs ONNX inference.
///
/// Run with:
///   flutter test integration_test/punctuation_slm_test.dart -d windows
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:everything_stack_template/services/slm/model_loader.dart';
import 'package:everything_stack_template/services/slm/onnx_session_pool.dart';
import 'package:everything_stack_template/services/slm/runners/punctuation_runner.dart';
import 'package:everything_stack_template/services/slm/tokenizers/sentencepiece_tokenizer.dart';

const _punctuationModel = ModelSpec(
  modelId: 'punctuation-en',
  fileName: 'punct_cap_seg_en.onnx',
  downloadUrl:
      'https://huggingface.co/1-800-BAD-CODE/punctuation_fullstop_truecase_english/resolve/main/punct_cap_seg_en.onnx',
  companions: [
    CompanionFile(
      fileName: 'spe_32k_lc_en.model',
      downloadUrl:
          'https://huggingface.co/1-800-BAD-CODE/punctuation_fullstop_truecase_english/resolve/main/spe_32k_lc_en.model',
    ),
  ],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ModelLoader modelLoader;
  late OnnxSessionPool sessionPool;
  late SentencePieceTokenizer tokenizer;
  late PunctuationRunner runner;

  setUpAll(() async {
    final cacheDir = '${Directory.systemTemp.path}/slm_test_cache';
    modelLoader = ModelLoader(cacheDir: cacheDir);
    await modelLoader.ensure(_punctuationModel);

    final modelPath = await modelLoader.modelPath(_punctuationModel);
    final vocabPath =
        await modelLoader.companionPath(_punctuationModel, 'spe_32k_lc_en.model');

    final vocabJsonPath = vocabPath.replaceAll('.model', '_vocab.json');
    final vocabFile = File(vocabJsonPath).existsSync()
        ? File(vocabJsonPath)
        : File('assets/models/punctuation_sp_vocab.json');

    if (!vocabFile.existsSync()) {
      fail(
        'Vocabulary JSON not found. Run: python scripts/export_punctuation_model.py\n'
        'Or ensure $vocabJsonPath exists.',
      );
    }

    final vocabJson =
        jsonDecode(vocabFile.readAsStringSync()) as Map<String, dynamic>;
    tokenizer = SentencePieceTokenizer.fromJson(vocabJson);

    sessionPool = OnnxSessionPool();
    runner = PunctuationRunner(
      sessionPool: sessionPool,
      tokenizer: tokenizer,
      modelId: _punctuationModel.modelId,
      assetPath: modelPath,
    );
  });

  tearDownAll(() async {
    await sessionPool.disposeAll();
  });

  testWidgets('session pool loads model and reports input/output names',
      (tester) async {
    final modelPath = await modelLoader.modelPath(_punctuationModel);
    final session =
        await sessionPool.acquire(_punctuationModel.modelId, modelPath);
    expect(session.inputNames, contains('input_ids'));
    expect(session.outputNames, isNotEmpty);
  });

  testWidgets('runner restores punctuation on unpunctuated text',
      (tester) async {
    const input = 'i went to the store and bought some milk';
    final result = await runner.restore(input);

    final hasPunctuation =
        result.contains('.') || result.contains(',') || result.contains('?');
    expect(hasPunctuation, isTrue,
        reason: 'Expected punctuation in: $result');
    expect(result[0], result[0].toUpperCase(),
        reason: 'Expected capitalized first letter in: $result');
  });

  testWidgets('runner handles multi-sentence input', (tester) async {
    const input =
        'i like programming it is fun sometimes it is frustrating but i keep going';
    final result = await runner.restore(input);
    expect(result, isNotEmpty);
    debugPrint('Multi-sentence result: $result');
  });
}
