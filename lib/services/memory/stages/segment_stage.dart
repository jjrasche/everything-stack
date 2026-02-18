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

  static final _tableRow = RegExp(r'^\|(.+)\|$', multiLine: true);
  static final _tableSeparator = RegExp(r'^[\s|:-]+$');

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
    final withLinearizedTables = _linearizeTables(withoutCode);
    final prose = _stripMarkdown(withLinearizedTables);
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

      if (_isSentenceEnd(char) &&
          !_isDecimalPeriod(chars, index) &&
          !_isAbbreviation(buffer.toString())) {
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

  /// Replace markdown tables with one linearized sentence per data row.
  /// Format: "header1: value1, header2: value2."
  /// Drops header and separator rows.
  String _linearizeTables(String text) {
    final lines = text.split('\n');
    final output = <String>[];
    var headers = <String>[];
    var inTable = false;

    for (final line in lines) {
      if (!_tableRow.hasMatch(line.trim())) {
        if (inTable) inTable = false;
        output.add(line);
        continue;
      }

      final cells = _extractCells(line);

      if (_tableSeparator.hasMatch(line.trim())) continue;

      if (!inTable) {
        // First pipe row = header
        headers = cells;
        inTable = true;
        continue;
      }

      output.add(_formatRow(headers, cells));
    }

    return output.join('\n');
  }

  List<String> _extractCells(String row) {
    return row
        .split('|')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
  }

  String _formatRow(List<String> headers, List<String> values) {
    final pairs = <String>[];
    for (var i = 0; i < values.length; i++) {
      final header = i < headers.length ? headers[i] : 'Column ${i + 1}';
      pairs.add('$header: ${values[i]}');
    }
    return '${pairs.join(', ')}.';
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

  /// Period between digits (e.g. "2.9") is not a sentence boundary.
  bool _isDecimalPeriod(List<int> chars, int index) {
    if (String.fromCharCode(chars[index]) != '.') return false;
    if (index == 0 || index + 1 >= chars.length) return false;
    final before = String.fromCharCode(chars[index - 1]);
    final after = String.fromCharCode(chars[index + 1]);
    return RegExp(r'\d').hasMatch(before) && RegExp(r'\d').hasMatch(after);
  }

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
