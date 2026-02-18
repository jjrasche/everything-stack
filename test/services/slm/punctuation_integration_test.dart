/// Integration test: downloads the real punctuation model via ModelLoader
/// and runs end-to-end inference through PunctuationRunner.
///
/// Run with:
///   flutter test test/services/slm/punctuation_integration_test.dart --tags=integration
@Tags(['integration'])
@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/slm/model_loader.dart';
import 'package:everything_stack_template/services/slm/onnx_session_pool.dart';
import 'package:everything_stack_template/services/slm/runners/punctuation_runner.dart';
import 'package:everything_stack_template/services/slm/tokenizers/sentencepiece_tokenizer.dart';

/// HuggingFace raw file URLs for the English punctuation model.
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

    // SentencePiece .model is a protobuf binary — for now load from
    // the pre-exported JSON if available, otherwise skip tokenizer tests.
    // TODO: either export vocab JSON in ModelLoader or parse .model directly
    final vocabJsonPath = vocabPath.replaceAll('.model', '_vocab.json');
    if (!File(vocabJsonPath).existsSync()) {
      // Fall back: check assets/models/ for pre-exported vocab
      const fallbackVocab = 'assets/models/punctuation_sp_vocab.json';
      if (!File(fallbackVocab).existsSync()) {
        fail(
          'Vocabulary JSON not found. Run: python scripts/export_punctuation_model.py\n'
          'Or ensure $vocabJsonPath exists.',
        );
      }
      final vocabJson =
          jsonDecode(File(fallbackVocab).readAsStringSync()) as Map<String, dynamic>;
      tokenizer = SentencePieceTokenizer.fromJson(vocabJson);
    } else {
      final vocabJson =
          jsonDecode(File(vocabJsonPath).readAsStringSync()) as Map<String, dynamic>;
      tokenizer = SentencePieceTokenizer.fromJson(vocabJson);
    }

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

  test('model loader caches model files', () async {
    expect(await modelLoader.isCached(_punctuationModel), isTrue);
  });

  test('tokenizer loads real 32k vocabulary', () {
    expect(tokenizer.vocabSize, 32000);
    expect(tokenizer.bosId, isNotNull);
    expect(tokenizer.eosId, isNotNull);
  });

  test('tokenizer round-trips text', () {
    const input = 'hello world this is a test';
    final ids = tokenizer.encode(input);
    expect(ids, isNotEmpty);
    expect(tokenizer.decode(ids), input);
  });

  test('session pool loads model and reports input/output names', () async {
    final modelPath = await modelLoader.modelPath(_punctuationModel);
    final session =
        await sessionPool.acquire(_punctuationModel.modelId, modelPath);
    expect(session.inputNames, contains('input_ids'));
    expect(session.outputNames, isNotEmpty);
  });

  test('runner restores punctuation on unpunctuated text', () async {
    const input = 'i went to the store and bought some milk';
    final result = await runner.restore(input);

    final hasPunctuation =
        result.contains('.') || result.contains(',') || result.contains('?');
    expect(hasPunctuation, isTrue,
        reason: 'Expected punctuation in: $result');
    expect(result[0], result[0].toUpperCase(),
        reason: 'Expected capitalized first letter in: $result');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('runner handles multi-sentence input', () async {
    const input =
        'i like programming it is fun sometimes it is frustrating but i keep going';
    final result = await runner.restore(input);
    expect(result, isNotEmpty);
    // ignore: avoid_print
    print('Multi-sentence result: $result');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
