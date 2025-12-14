/// Utility for splitting text into sentences or sliding windows.
///
/// Handles both structured text (with punctuation) and unstructured text
/// (voice transcriptions without clear sentence boundaries).
class SentenceSplitter {
  /// Regex for detecting sentence boundaries in English text
  ///
  /// Pattern:
  /// - (?<=[.!?]) - lookbehind for sentence-ending punctuation
  /// - (?<![A-Z]\.) - negative lookbehind to skip abbreviations like "Dr."
  /// - (?<!\d\.) - negative lookbehind to skip decimals like "3.14"
  /// - \s+ - one or more whitespace characters
  static final _sentencePattern = RegExp(
    r'(?<=[.!?])(?<![A-Z]\.)(?<!\d\.)\s+',
    caseSensitive: false,
  );

  /// Split text into sentences.
  ///
  /// Uses regex-based sentence detection for English text.
  /// Returns list of sentences with whitespace trimmed.
  ///
  /// Returns empty list if text is empty.
  static List<String> splitSentences(String text) {
    if (text.trim().isEmpty) return [];

    final sentences = text
        .split(_sentencePattern)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return sentences;
  }

  /// Create overlapping windows of text for unpunctuated content.
  ///
  /// Used when text lacks clear sentence boundaries (e.g., voice transcriptions).
  /// Parameters:
  /// - [text]: input text to segment
  /// - [windowSize]: size of each window in tokens
  /// - [overlap]: number of tokens to overlap between consecutive windows
  ///
  /// Returns list of text segments with specified overlap.
  static List<String> slidingWindows(
    String text, {
    required int windowSize,
    required int overlap,
  }) {
    final tokens = text.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return [];

    final windows = <String>[];
    final stride = windowSize - overlap;

    for (int i = 0; i < tokens.length; i += stride) {
      final end = (i + windowSize).clamp(0, tokens.length);
      if (i >= tokens.length) break;

      final window = tokens.sublist(i, end).join(' ');
      if (window.isNotEmpty) {
        windows.add(window);
      }

      // Avoid infinite loop for very small stride
      if (stride <= 0) break;
    }

    return windows;
  }

  /// Count tokens in text (simple whitespace-based tokenization)
  static int countTokens(String text) {
    return text.split(' ').where((t) => t.isNotEmpty).length;
  }

  /// Auto-detect whether text is structured (punctuated) or unstructured
  ///
  /// Heuristic: if < 5% of segments end with punctuation, treat as unstructured.
  /// Returns true if text appears to be unpunctuated/unstructured.
  static bool isUnstructured(String text) {
    final sentences = splitSentences(text);
    if (sentences.length < 2) return false;

    int punctuatedCount = 0;
    for (final sent in sentences) {
      if (sent.endsWith('.') || sent.endsWith('!') || sent.endsWith('?')) {
        punctuatedCount++;
      }
    }

    final punctuationRate = punctuatedCount / sentences.length;
    return punctuationRate < 0.05;
  }
}
