import '../tokenizer.dart';

/// Pure Dart WordPiece tokenizer (BERT-style).
/// Uses greedy longest-match-first on subword pieces.
///
/// Vocabulary loaded from a JSON export of vocab.txt:
/// {"tokens": ["[PAD]", "[UNK]", "[CLS]", "[SEP]", ...], "unkId": 100, ...}
class WordPieceTokenizer implements Tokenizer {
  final Map<String, int> _tokenToId;
  final List<String> _idToToken;
  final int _unkId;
  final int? _clsId;
  final int? _sepId;
  final int? _padId;
  final bool _doLowerCase;

  /// Max subword length to try during greedy matching.
  static const int _maxWordLen = 200;

  /// Continuation prefix for subword pieces.
  static const String _continuationPrefix = '##';

  WordPieceTokenizer._({
    required Map<String, int> tokenToId,
    required List<String> idToToken,
    required int unkId,
    int? clsId,
    int? sepId,
    int? padId,
    bool doLowerCase = true,
  })  : _tokenToId = tokenToId,
        _idToToken = idToToken,
        _unkId = unkId,
        _clsId = clsId,
        _sepId = sepId,
        _padId = padId,
        _doLowerCase = doLowerCase;

  /// Build from exported JSON vocabulary.
  ///
  /// Expected format:
  /// ```json
  /// {
  ///   "tokens": ["[PAD]", "[UNK]", "[CLS]", "[SEP]", "the", "##s", ...],
  ///   "unkId": 100,
  ///   "clsId": 101,
  ///   "sepId": 102,
  ///   "padId": 0,
  ///   "doLowerCase": true
  /// }
  /// ```
  factory WordPieceTokenizer.fromJson(Map<String, dynamic> json) {
    final rawTokens = json['tokens'] as List;
    final idToToken = <String>[];
    final tokenToId = <String, int>{};

    for (var i = 0; i < rawTokens.length; i++) {
      final token = rawTokens[i] as String;
      idToToken.add(token);
      tokenToId[token] = i;
    }

    return WordPieceTokenizer._(
      tokenToId: tokenToId,
      idToToken: idToToken,
      unkId: json['unkId'] as int? ?? 100,
      clsId: json['clsId'] as int?,
      sepId: json['sepId'] as int?,
      padId: json['padId'] as int?,
      doLowerCase: json['doLowerCase'] as bool? ?? true,
    );
  }

  @override
  int get vocabSize => _idToToken.length;

  @override
  int? get bosId => _clsId;

  @override
  int? get eosId => _sepId;

  @override
  int? get padId => _padId;

  @override
  int get unkId => _unkId;

  @override
  List<int> encode(String text) {
    if (text.isEmpty) return [];

    final normalized = _doLowerCase ? text.toLowerCase() : text;
    final words = _basicTokenize(normalized);
    final tokenIds = <int>[];

    for (final word in words) {
      tokenIds.addAll(_wordPieceTokenize(word));
    }

    return tokenIds;
  }

  @override
  String decode(List<int> tokenIds) {
    final specialIds = {_unkId, _clsId, _sepId, _padId};
    final buffer = StringBuffer();
    var needsSpace = false;

    for (final id in tokenIds) {
      if (specialIds.contains(id)) continue;
      if (id < 0 || id >= _idToToken.length) continue;

      final token = _idToToken[id];
      if (token.startsWith(_continuationPrefix)) {
        buffer.write(token.substring(_continuationPrefix.length));
      } else {
        if (needsSpace) buffer.write(' ');
        buffer.write(token);
      }
      needsSpace = true;
    }

    return buffer.toString();
  }

  /// Split text into words on whitespace and punctuation.
  /// BERT's BasicTokenizer: split on whitespace, isolate punctuation.
  List<String> _basicTokenize(String text) {
    final words = <String>[];
    final buffer = StringBuffer();

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (_isWhitespace(char)) {
        if (buffer.isNotEmpty) {
          words.add(buffer.toString());
          buffer.clear();
        }
      } else if (_isPunctuation(char)) {
        if (buffer.isNotEmpty) {
          words.add(buffer.toString());
          buffer.clear();
        }
        words.add(char);
      } else {
        buffer.write(char);
      }
    }

    if (buffer.isNotEmpty) words.add(buffer.toString());
    return words;
  }

  /// Greedy longest-match-first subword tokenization.
  List<int> _wordPieceTokenize(String word) {
    if (word.length > _maxWordLen) return [_unkId];

    final tokenIds = <int>[];
    var start = 0;

    while (start < word.length) {
      var end = word.length;
      int? foundId;

      while (start < end) {
        final substr = start > 0
            ? '$_continuationPrefix${word.substring(start, end)}'
            : word.substring(start, end);

        final id = _tokenToId[substr];
        if (id != null) {
          foundId = id;
          break;
        }
        end--;
      }

      if (foundId == null) {
        // Entire remaining word is unknown
        return [_unkId];
      }

      tokenIds.add(foundId);
      start = end;
    }

    return tokenIds;
  }

  bool _isWhitespace(String char) {
    final code = char.codeUnitAt(0);
    return char == ' ' || char == '\t' || char == '\n' || char == '\r' ||
        code == 0x00A0; // non-breaking space
  }

  bool _isPunctuation(String char) {
    final code = char.codeUnitAt(0);
    // ASCII punctuation ranges
    if ((code >= 33 && code <= 47) ||
        (code >= 58 && code <= 64) ||
        (code >= 91 && code <= 96) ||
        (code >= 123 && code <= 126)) {
      return true;
    }
    return false;
  }
}
