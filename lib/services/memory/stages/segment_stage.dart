import '../encoder_stage.dart';
import '../encoder_trace.dart';

class SegmentResult {
  final List<Sentence> sentences;
  final SegmentTrace trace;

  SegmentResult({required this.sentences, required this.trace});
}

/// Regex-based sentence splitting. Phase 1 implementation.
/// Phase 3: wtpsplit SLM replaces this.
class SegmentStage implements EncoderStage<String, SegmentResult> {
  static const int _minWordCount = 3;
  static final _fencedCodeBlock = RegExp(r'```[^\n]*\n[\s\S]*?```', multiLine: true);
  static final _indentedCodeBlock = RegExp(r'(^(    |\t).+\n?)+', multiLine: true);
  static final _markdownHeader = RegExp(r'^#{1,6}\s+.*$', multiLine: true);
  static final _markdownBold = RegExp(r'\*\*([^*]+)\*\*');
  static final _markdownBullet = RegExp(r'^[\s]*[-*+]\s+', multiLine: true);
  static final _markdownNumbered = RegExp(r'^[\s]*\d+\.\s+', multiLine: true);

  static final _abbreviations = {
    'dr', 'mr', 'mrs', 'ms', 'prof', 'sr', 'jr',
    'inc', 'corp', 'ltd', 'co', 'vs', 'etc', 'approx',
    'dept', 'est', 'vol', 'no', 'gen', 'govt',
    'e.g', 'i.e', 'fig', 'eq',
  };

  @override
  String get stageName => 'segment';

  @override
  Future<SegmentResult> process(String input) async {
    final stopwatch = Stopwatch()..start();

    if (input.trim().isEmpty) {
      stopwatch.stop();
      return SegmentResult(
        sentences: [],
        trace: SegmentTrace(
          input: input,
          output: [],
          model: 'regex',
          latencyMs: stopwatch.elapsedMilliseconds,
        ),
      );
    }

    final withoutCode = _stripCodeBlocks(input);
    final prose = _stripMarkdown(withoutCode);
    final allSentences = _splitSentences(prose);
    final sentences = _filterFragments(allSentences);
    stopwatch.stop();

    return SegmentResult(
      sentences: sentences,
      trace: SegmentTrace(
        input: input,
        output: sentences,
        model: 'regex',
        latencyMs: stopwatch.elapsedMilliseconds,
      ),
    );
  }

  List<Sentence> _splitSentences(String text) {
    final results = <Sentence>[];
    final buffer = StringBuffer();
    final chars = text.runes.toList();
    var index = 0;

    while (index < chars.length) {
      final char = String.fromCharCode(chars[index]);
      buffer.write(char);

      if (_isSentenceEnd(char) && !_isAbbreviation(buffer.toString())) {
        // Consume trailing whitespace
        while (index + 1 < chars.length &&
            String.fromCharCode(chars[index + 1]).trim().isEmpty) {
          index++;
        }
        final sentence = buffer.toString().trim();
        if (sentence.isNotEmpty) {
          results.add(Sentence(
            id: 'S${results.length + 1}',
            text: sentence,
          ));
        }
        buffer.clear();
      }
      index++;
    }

    // Remainder
    final remainder = buffer.toString().trim();
    if (remainder.isNotEmpty) {
      results.add(Sentence(
        id: 'S${results.length + 1}',
        text: remainder,
      ));
    }

    return results;
  }

  String _stripCodeBlocks(String text) {
    return text
        .replaceAll(_fencedCodeBlock, '')
        .replaceAll(_indentedCodeBlock, '');
  }

  String _stripMarkdown(String text) {
    return text
        .replaceAll(_markdownHeader, '')
        .replaceAllMapped(_markdownBold, (m) => m.group(1)!)
        .replaceAll(_markdownBullet, '')
        .replaceAll(_markdownNumbered, '');
  }

  List<Sentence> _filterFragments(List<Sentence> sentences) {
    final filtered = sentences
        .where((s) => s.text.split(RegExp(r'\s+')).length >= _minWordCount)
        .toList();
    for (var i = 0; i < filtered.length; i++) {
      filtered[i] = Sentence(id: 'S${i + 1}', text: filtered[i].text);
    }
    return filtered;
  }

  bool _isSentenceEnd(String char) =>
      char == '.' || char == '?' || char == '!';

  bool _isAbbreviation(String textSoFar) {
    final trimmed = textSoFar.trimRight();
    if (!trimmed.endsWith('.')) return false;

    // Extract last word before the period
    final withoutPeriod = trimmed.substring(0, trimmed.length - 1);
    final words = withoutPeriod.split(RegExp(r'\s+'));
    if (words.isEmpty) return false;

    final lastWord = words.last.toLowerCase();
    return _abbreviations.contains(lastWord);
  }
}
