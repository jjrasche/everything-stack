import 'dart:math' as math;

import '../session_pool.dart';
import '../tokenizer.dart';

/// Binary filter prediction for a single text span.
class FilterPrediction {
  final double extractScore;
  final double skipScore;

  FilterPrediction({
    required this.extractScore,
    required this.skipScore,
  });

  bool get isExtract => extractScore >= skipScore;
  double get confidence => math.max(extractScore, skipScore);
}

/// Classifies text spans as extract or skip using a SetFit-trained
/// DeBERTa-v3-small encoder + logistic regression head.
///
/// Pipeline: tokenize → encode → mean-pool → classify via head weights.
/// The ONNX model outputs last_hidden_state; pooling and classification
/// happen in Dart using exported head weights.
class FilterRunner {
  final SessionPool _sessionPool;
  final Tokenizer _tokenizer;
  final String _modelId;
  final String _assetPath;
  final List<double> _headCoefficients;
  final List<double> _headIntercept;

  /// Max tokens (DeBERTa-v3-small supports 512, minus 2 for BOS/EOS).
  static const int _maxContentTokens = 510;

  FilterRunner({
    required SessionPool sessionPool,
    required Tokenizer tokenizer,
    required String modelId,
    required String assetPath,
    required List<double> headCoefficients,
    required List<double> headIntercept,
  })  : _sessionPool = sessionPool,
        _tokenizer = tokenizer,
        _modelId = modelId,
        _assetPath = assetPath,
        _headCoefficients = headCoefficients,
        _headIntercept = headIntercept;

  /// Predict extract/skip for a single span.
  Future<FilterPrediction> predict(String spanText) async {
    final encoded = _encode(spanText);
    final embedding = await _embed(encoded);
    return _classify(embedding);
  }

  _EncodedSpan _encode(String text) {
    var tokens = _tokenizer.encode(text);
    if (tokens.length > _maxContentTokens) {
      tokens = tokens.sublist(0, _maxContentTokens);
    }

    final bosId = _tokenizer.bosId ?? 1;
    final eosId = _tokenizer.eosId ?? 2;

    final inputIds = [bosId, ...tokens, eosId];
    final attentionMask = List<int>.filled(inputIds.length, 1);

    return _EncodedSpan(inputIds: inputIds, attentionMask: attentionMask);
  }

  Future<List<double>> _embed(_EncodedSpan encoded) async {
    final session = await _sessionPool.acquire(_modelId, _assetPath);
    final outputs = await session.run({
      'input_ids': encoded.inputIds,
      'attention_mask': encoded.attentionMask,
    });

    final hiddenState = outputs['last_hidden_state']!;
    return _meanPool(hiddenState, encoded.attentionMask);
  }

  FilterPrediction _classify(List<double> embedding) {
    // Logistic regression: sigmoid(W·x + b)
    // For binary: single coefficient row, single intercept
    var logit = _headIntercept[0];
    for (var i = 0; i < embedding.length && i < _headCoefficients.length; i++) {
      logit += _headCoefficients[i] * embedding[i];
    }

    // sigmoid → probability of class 1 (extract)
    final extractProb = 1.0 / (1.0 + math.exp(-logit));
    final skipProb = 1.0 - extractProb;

    return FilterPrediction(
      extractScore: extractProb,
      skipScore: skipProb,
    );
  }

  /// Mean pooling over non-padding token embeddings.
  /// hiddenState is flattened [1, seq_len, hidden_dim].
  List<double> _meanPool(List<dynamic> hiddenState, List<int> attentionMask) {
    final seqLen = attentionMask.length;
    final totalElements = hiddenState.length;
    final hiddenDim = totalElements ~/ seqLen;

    final pooled = List<double>.filled(hiddenDim, 0.0);
    var tokenCount = 0;

    for (var t = 0; t < seqLen; t++) {
      if (attentionMask[t] == 0) continue;
      tokenCount++;
      for (var d = 0; d < hiddenDim; d++) {
        pooled[d] += (hiddenState[t * hiddenDim + d] as num).toDouble();
      }
    }

    if (tokenCount > 0) {
      for (var d = 0; d < hiddenDim; d++) {
        pooled[d] /= tokenCount;
      }
    }

    return pooled;
  }
}

class _EncodedSpan {
  final List<int> inputIds;
  final List<int> attentionMask;

  _EncodedSpan({required this.inputIds, required this.attentionMask});
}
