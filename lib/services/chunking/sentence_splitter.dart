/// Utility for splitting text into sentences or sliding windows
///
/// Handles both structured (punctuated) and unstructured (unpunctuated) text:
///
/// **Structured text**: Uses regex to detect sentence boundaries based on
/// punctuation (.!?). This preserves natural semantic units.
///
/// **Unstructured text**: Falls back to sliding window approach when no
/// punctuation is detected. This handles voice transcriptions and stream-of-
/// consciousness notes without clear sentence boundaries.
class SentenceSplitter {
  /// Sentence boundary regex: Matches period/question/exclamation followed by space and capital
  ///
  /// Pattern explanation:
  /// - `[.!?]` - Sentence-ending punctuation
  /// - `\s+` - One or more whitespace characters
  /// - `(?=[A-Z])` - Positive lookahead: next character must be uppercase
  ///
  /// This catches most sentence boundaries while avoiding some false positives.
  /// Note: This won't catch all cases (e.g., sentences ending mid-text without
  /// capital letter following), but works well for most structured content.
  static final _sentencePattern = RegExp(
    r'[.!?]\s+(?=[A-Z])',
  );

  /// Minimum punctuation ratio to use sentence splitting vs sliding window
  ///
  /// If less than 5% of chunks end with punctuation, assume unpunctuated text
  /// and fall back to sliding window approach.
  static const _minPunctuationRatio = 0.05;

  /// Split text into sentences or windows based on structure
  ///
  /// Strategy:
  /// 1. Try sentence splitting with punctuation regex
  /// 2. If insufficient punctuation detected, fall back to sliding windows
  /// 3. Track token positions for each segment
  ///
  /// Parameters:
  /// - [text]: Text to split
  /// - [windowSize]: Window size for unpunctuated text (default: 200 tokens)
  /// - [overlap]: Window overlap for unpunctuated text (default: 50 tokens)
  ///
  /// Returns list of text segments with their token positions (start, end).
  static List<TextSegment> split(
    String text, {
    int windowSize = 200,
    int overlap = 50,
  }) {
    if (text.trim().isEmpty) {
      return [];
    }

    // Try sentence splitting first
    final sentences = text.trim().split(_sentencePattern);

    // Check if text has sufficient punctuation to use sentence splitting
    if (_hasSufficientPunctuation(sentences)) {
      return _createSegmentsFromSentences(sentences);
    }

    // Fall back to sliding window for unpunctuated text
    return _createSlidingWindows(text, windowSize: windowSize, overlap: overlap);
  }

  /// Check if sentences have sufficient punctuation to use sentence-based splitting
  static bool _hasSufficientPunctuation(List<String> sentences) {
    if (sentences.length < 3) {
      // Too few sentences - check if they end with punctuation
      return sentences.any((s) => RegExp(r'[.!?]\s*$').hasMatch(s));
    }

    // Count how many sentences end with punctuation
    final punctuatedCount = sentences
        .where((s) => RegExp(r'[.!?]\s*$').hasMatch(s))
        .length;

    return (punctuatedCount / sentences.length) >= _minPunctuationRatio;
  }

  /// Create text segments from sentences with token tracking
  static List<TextSegment> _createSegmentsFromSentences(List<String> sentences) {
    final segments = <TextSegment>[];
    int currentToken = 0;

    for (final sentence in sentences) {
      final trimmed = sentence.trim();
      if (trimmed.isEmpty) continue;

      final tokenCount = _countTokens(trimmed);
      segments.add(TextSegment(
        text: trimmed,
        startToken: currentToken,
        endToken: currentToken + tokenCount,
      ));
      currentToken += tokenCount;
    }

    return segments;
  }

  /// Create sliding windows for unpunctuated text
  ///
  /// Uses configurable window size and overlap to detect topic boundaries.
  /// This allows semantic chunker to identify where topics shift even in
  /// continuous text without grammatical structure.
  ///
  /// Parameters:
  /// - [windowSize]: Size of each window in tokens (default: 200)
  /// - [overlap]: Overlap between consecutive windows in tokens (default: 50)
  static List<TextSegment> _createSlidingWindows(
    String text, {
    int windowSize = 200,
    int overlap = 50,
  }) {
    final tokens = _tokenize(text);
    if (tokens.isEmpty) return [];

    final segments = <TextSegment>[];
    int start = 0;

    while (start < tokens.length) {
      final end = (start + windowSize).clamp(0, tokens.length);
      final windowTokens = tokens.sublist(start, end);
      final windowText = windowTokens.join(' ');

      segments.add(TextSegment(
        text: windowText,
        startToken: start,
        endToken: end,
      ));

      // If this is the last window, break
      if (end >= tokens.length) break;

      // Move forward by (windowSize - overlap)
      start += (windowSize - overlap);
    }

    return segments;
  }

  /// Tokenize text into words (simple whitespace splitting)
  ///
  /// This is not subword tokenization (like BPE), just word-level splitting.
  /// Sufficient for chunk size estimation and boundary tracking.
  ///
  /// Public to allow other chunking components to use consistent tokenization.
  static List<String> tokenize(String text) {
    return text
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  /// Count tokens in text
  ///
  /// Public to allow other chunking components to use consistent token counting.
  static int countTokens(String text) {
    return tokenize(text).length;
  }

  // Private alias for internal use
  static List<String> _tokenize(String text) => tokenize(text);
  static int _countTokens(String text) => countTokens(text);
}

/// Represents a text segment with token position tracking
class TextSegment {
  final String text;
  final int startToken;
  final int endToken;

  TextSegment({
    required this.text,
    required this.startToken,
    required this.endToken,
  });

  int get tokenCount => endToken - startToken;

  @override
  String toString() {
    return 'TextSegment(tokens: $tokenCount, start: $startToken, end: $endToken)';
  }
}
