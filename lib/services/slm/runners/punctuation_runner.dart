import '../session_pool.dart';
import '../tokenizer.dart';

/// Post-punctuation label indices from the model's config.yaml.
/// 0=NULL, 1=ACRONYM, 2=period, 3=comma, 4=question
String _resolvePostLabel(int index) {
  switch (index) {
    case 2: return '.';
    case 3: return ',';
    case 4: return '?';
    default: return '';
  }
}

/// Restores punctuation and true-casing to unpunctuated text
/// using a token classification ONNX model.
///
/// Model: 1-800-BAD-CODE/punctuation_fullstop_truecase_english
/// Outputs 4 tensors: pre_preds, post_preds, cap_preds, seg_preds.
class PunctuationRunner {
  final SessionPool _sessionPool;
  final Tokenizer _tokenizer;
  final String _modelId;
  final String _assetPath;

  /// Max subtokens per chunk (model trained on 256, minus 2 for BOS/EOS).
  static const int _maxContentTokens = 254;

  PunctuationRunner({
    required SessionPool sessionPool,
    required Tokenizer tokenizer,
    required String modelId,
    required String assetPath,
  })  : _sessionPool = sessionPool,
        _tokenizer = tokenizer,
        _modelId = modelId,
        _assetPath = assetPath;

  Future<String> restore(String unpunctuatedText) async {
    if (unpunctuatedText.isEmpty) return '';

    final tokenIds = _tokenizer.encode(unpunctuatedText);
    if (tokenIds.isEmpty) return unpunctuatedText;

    final session = await _sessionPool.acquire(_modelId, _assetPath);
    final chunks = _chunk(tokenIds);
    final buffer = StringBuffer();

    for (final chunk in chunks) {
      final restored = await _processChunk(session, chunk);
      if (buffer.isNotEmpty && restored.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write(restored);
    }

    return buffer.toString();
  }

  /// Split token IDs into chunks of at most _maxContentTokens.
  List<List<int>> _chunk(List<int> tokenIds) {
    if (tokenIds.length <= _maxContentTokens) return [tokenIds];

    final chunks = <List<int>>[];
    for (var i = 0; i < tokenIds.length; i += _maxContentTokens) {
      final end = i + _maxContentTokens;
      chunks.add(tokenIds.sublist(i, end > tokenIds.length ? tokenIds.length : end));
    }
    return chunks;
  }

  /// Run inference on one chunk and reconstruct punctuated text.
  Future<String> _processChunk(InferenceSession session, List<int> chunk) async {
    final bosId = _tokenizer.bosId ?? 0;
    final eosId = _tokenizer.eosId ?? 1;

    // Wrap with BOS/EOS
    final inputIds = [bosId, ...chunk, eosId];

    final outputs = await session.run({'input_ids': inputIds});

    final postPreds = _castToIntList(outputs['post_preds']!);
    final capPreds = _castToIntList(outputs['cap_preds']!);

    // Strip BOS and EOS positions (first and last)
    final seqLen = inputIds.length;
    final contentPostPreds = postPreds.sublist(1, seqLen - 1);

    // Decode each token piece and apply labels
    final words = <String>[];
    for (var i = 0; i < chunk.length; i++) {
      final piece = _tokenizer.decode([chunk[i]]);
      final capitalized = _applyCasing(piece, capPreds, i + 1, seqLen);
      final postPunct = _resolvePostLabel(contentPostPreds[i]);
      words.add('$capitalized$postPunct');
    }

    return words.join(' ');
  }

  /// Apply per-character casing from cap_preds.
  /// capPreds is flat; each token position has variable-length char predictions.
  /// For simplicity, we apply the first cap prediction to the first character.
  String _applyCasing(String piece, List<int> capPreds, int tokenPosition, int seqLen) {
    if (piece.isEmpty) return piece;

    // cap_preds may be flat or per-token. Use tokenPosition to index.
    // If capPreds has exactly seqLen entries, one per token position.
    if (tokenPosition < capPreds.length && capPreds[tokenPosition] == 1) {
      return piece[0].toUpperCase() + piece.substring(1);
    }
    return piece;
  }

  List<int> _castToIntList(List<dynamic> raw) =>
      raw.map((e) => e is int ? e : (e as num).toInt()).toList();
}
