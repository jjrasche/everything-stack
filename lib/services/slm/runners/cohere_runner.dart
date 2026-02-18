import 'dart:math' as math;

import '../session_pool.dart';
import '../tokenizer.dart';

/// Pairwise topic coherence score between two adjacent text segments.
class CoherencePair {
  final double sameTopicScore;
  final double differentTopicScore;

  CoherencePair({
    required this.sameTopicScore,
    required this.differentTopicScore,
  });

  /// Higher = more likely same topic continues.
  double get coherence => sameTopicScore;
}

/// Scores pairwise topic coherence between adjacent sentences using
/// a BERT binary classifier (bert-wiki-paragraphs).
///
/// Input: `[CLS] segment_A [SEP] segment_B [SEP]`
///        token_type_ids: 0 for segment A, 1 for segment B
/// Output: softmax over [different_topic, same_topic]
class CohereRunner {
  final SessionPool _sessionPool;
  final Tokenizer _tokenizer;
  final String _modelId;
  final String _assetPath;

  final int _clsId;
  final int _sepId;

  /// Max tokens per sentence pair (model limit 512, minus 3 special tokens).
  static const int _maxContentTokens = 509;

  CohereRunner({
    required SessionPool sessionPool,
    required Tokenizer tokenizer,
    required String modelId,
    required String assetPath,
  })  : _sessionPool = sessionPool,
        _tokenizer = tokenizer,
        _modelId = modelId,
        _assetPath = assetPath,
        _clsId = tokenizer.bosId ?? 101,
        _sepId = tokenizer.eosId ?? 102;

  /// Score topic coherence for one sentence pair.
  Future<CoherencePair> score(String sentenceA, String sentenceB) async {
    final encoded = _encode(sentenceA, sentenceB);

    final session = await _sessionPool.acquire(_modelId, _assetPath);
    final outputs = await session.run({
      'input_ids': encoded.inputIds,
      'attention_mask': encoded.attentionMask,
      'token_type_ids': encoded.tokenTypeIds,
    });

    final logits = _castToDoubleList(outputs['logits']!);
    final probs = _softmax(logits);

    return CoherencePair(
      differentTopicScore: probs[0],
      sameTopicScore: probs[1],
    );
  }

  _EncodedPair _encode(String sentenceA, String sentenceB) {
    var tokensA = _tokenizer.encode(sentenceA);
    var tokensB = _tokenizer.encode(sentenceB);

    final totalContent = tokensA.length + tokensB.length;
    if (totalContent > _maxContentTokens) {
      final halfMax = _maxContentTokens ~/ 2;
      tokensA = tokensA.sublist(0, math.min(tokensA.length, halfMax));
      tokensB = tokensB.sublist(0, math.min(tokensB.length, halfMax));
    }

    // [CLS] tokensA [SEP] tokensB [SEP]
    final inputIds = [_clsId, ...tokensA, _sepId, ...tokensB, _sepId];
    final attentionMask = List<int>.filled(inputIds.length, 1);

    // Segment A = 0 (CLS + tokensA + SEP), Segment B = 1 (tokensB + SEP)
    final segmentALen = 1 + tokensA.length + 1;
    final segmentBLen = tokensB.length + 1;
    final tokenTypeIds = [
      ...List<int>.filled(segmentALen, 0),
      ...List<int>.filled(segmentBLen, 1),
    ];

    return _EncodedPair(
      inputIds: inputIds,
      attentionMask: attentionMask,
      tokenTypeIds: tokenTypeIds,
    );
  }

  List<double> _castToDoubleList(List<dynamic> raw) =>
      raw.map((e) => (e as num).toDouble()).toList();

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((l) => math.exp(l - maxLogit)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }
}

class _EncodedPair {
  final List<int> inputIds;
  final List<int> attentionMask;
  final List<int> tokenTypeIds;

  _EncodedPair({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
  });
}
