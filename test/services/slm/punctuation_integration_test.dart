/// Non-ONNX integration checks: model download + tokenizer with real vocab.
/// ONNX inference tests live in integration_test/punctuation_slm_test.dart.
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
  late ModelLoader modelLoader;
  late SentencePieceTokenizer tokenizer;

  setUpAll(() async {
    final cacheDir = '${Directory.systemTemp.path}/slm_test_cache';
    modelLoader = ModelLoader(cacheDir: cacheDir);
    await modelLoader.ensure(_punctuationModel);

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
}
