import 'dart:math' as math;

import '../tokenizer.dart';

/// Pure Dart SentencePiece unigram tokenizer.
/// Uses Viterbi algorithm for maximum-likelihood segmentation.
///
/// Vocabulary and scores are loaded from a JSON export of the .model file.
/// JSON format: {"pieces": [["piece", score], ...], "unkId": 0, "bosId": 1, "eosId": 2}
class SentencePieceTokenizer implements Tokenizer {
  final List<String> _idTopiece;
  final List<double> _scores;
  final Map<String, int> _pieceToId;
  final int _unkId;
  final int? _bosId;
  final int? _eosId;
  final int? _padId;

  SentencePieceTokenizer._({
    required List<String> pieces,
    required List<double> scores,
    required Map<String, int> pieceToId,
    required int unkId,
    int? bosId,
    int? eosId,
    int? padId,
  })  : _idTopiece = pieces,
        _scores = scores,
        _pieceToId = pieceToId,
        _unkId = unkId,
        _bosId = bosId,
        _eosId = eosId,
        _padId = padId;

  /// Build from exported JSON vocabulary.
  factory SentencePieceTokenizer.fromJson(Map<String, dynamic> json) {
    final rawPieces = json['pieces'] as List;
    final pieces = <String>[];
    final scores = <double>[];
    final pieceToId = <String, int>{};

    for (var i = 0; i < rawPieces.length; i++) {
      final entry = rawPieces[i] as List;
      final piece = entry[0] as String;
      final score = (entry[1] as num).toDouble();
      pieces.add(piece);
      scores.add(score);
      pieceToId[piece] = i;
    }

    return SentencePieceTokenizer._(
      pieces: pieces,
      scores: scores,
      pieceToId: pieceToId,
      unkId: json['unkId'] as int? ?? 0,
      bosId: json['bosId'] as int?,
      eosId: json['eosId'] as int?,
      padId: json['padId'] as int?,
    );
  }

  @override
  int get vocabSize => _idTopiece.length;

  @override
  int? get bosId => _bosId;

  @override
  int? get eosId => _eosId;

  @override
  int? get padId => _padId;

  @override
  int get unkId => _unkId;

  static const String _spaceMarker = '\u2581';

  @override
  List<int> encode(String text) {
    if (text.isEmpty) return [];

    // SentencePiece convention: prepend space marker, then tokenize
    final normalized = '$_spaceMarker${text.replaceAll(' ', _spaceMarker)}';
    return _viterbiEncode(normalized);
  }

  @override
  String decode(List<int> tokenIds) {
    final specialIds = {_unkId, _bosId, _eosId, _padId};
    final buffer = StringBuffer();

    for (final id in tokenIds) {
      if (specialIds.contains(id)) continue;
      if (id < 0 || id >= _idTopiece.length) continue;
      buffer.write(_idTopiece[id]);
    }

    var result = buffer.toString();
    result = result.replaceAll(_spaceMarker, ' ');

    // Strip leading space (artifact of SentencePiece encoding)
    if (result.startsWith(' ')) {
      result = result.substring(1);
    }

    return result;
  }

  /// Viterbi algorithm: find the segmentation with highest total score.
  ///
  /// bestScore[i] = best score for encoding normalized[0..i)
  /// bestPieceLen[i] = length of the piece ending at position i in the best path
  List<int> _viterbiEncode(String normalized) {
    final length = normalized.length;
    final bestScore = List<double>.filled(length + 1, double.negativeInfinity);
    final bestPieceLen = List<int>.filled(length + 1, 0);
    bestScore[0] = 0.0;

    for (var endPos = 1; endPos <= length; endPos++) {
      // Try all piece lengths that could end at endPos
      final maxPieceLen = math.min(endPos, _maxPieceLength);
      for (var pieceLen = 1; pieceLen <= maxPieceLen; pieceLen++) {
        final startPos = endPos - pieceLen;
        if (bestScore[startPos] == double.negativeInfinity) continue;

        final piece = normalized.substring(startPos, endPos);
        final id = _pieceToId[piece];
        if (id == null) continue;

        final score = bestScore[startPos] + _scores[id];
        if (score > bestScore[endPos]) {
          bestScore[endPos] = score;
          bestPieceLen[endPos] = pieceLen;
        }
      }

      // If no piece matched, try single character as unk
      if (bestScore[endPos] == double.negativeInfinity && bestScore[endPos - 1] != double.negativeInfinity) {
        bestScore[endPos] = bestScore[endPos - 1] + _scores[_unkId] - 10.0;
        bestPieceLen[endPos] = 1;
      }
    }

    return _backtrack(normalized, bestPieceLen);
  }

  /// Walk backward through Viterbi results to recover token IDs.
  List<int> _backtrack(String normalized, List<int> bestPieceLen) {
    final tokenIds = <int>[];
    var pos = normalized.length;

    while (pos > 0) {
      final pieceLen = bestPieceLen[pos];
      if (pieceLen == 0) break; // unreachable if Viterbi completed

      final piece = normalized.substring(pos - pieceLen, pos);
      final id = _pieceToId[piece] ?? _unkId;
      tokenIds.add(id);
      pos -= pieceLen;
    }

    return tokenIds.reversed.toList();
  }

  /// Precompute max piece length for Viterbi bounds.
  int get _maxPieceLength {
    var maxLen = 0;
    for (final piece in _idTopiece) {
      if (piece.length > maxLen) maxLen = piece.length;
    }
    return maxLen;
  }

}
