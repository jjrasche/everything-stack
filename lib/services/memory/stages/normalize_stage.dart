import '../../slm/runners/punctuation_runner.dart';
import '../encoder_stage.dart';
import '../encoder_trace.dart';

class NormalizeResult {
  final String output;
  final NormalizeTrace trace;

  NormalizeResult({required this.output, required this.trace});
}

/// Detect punctuation quality + split overlong sentences.
/// When a PunctuationRunner is provided, restores punctuation on STT text.
/// Without a runner, passes text through unchanged (no-op stub).
class NormalizeStage implements EncoderStage<String, NormalizeResult> {
  static const int _overlongThreshold = 40;
  static final _fencedCodeBlock = RegExp(r'```[^\n]*\n[\s\S]*?```', multiLine: true);
  final PunctuationRunner? _punctuationRunner;

  NormalizeStage({PunctuationRunner? punctuationRunner})
      : _punctuationRunner = punctuationRunner;

  @override
  String get stageName => 'normalize';

  @override
  Future<NormalizeResult> process(String input) async {
    final stopwatch = Stopwatch()..start();

    if (input.isEmpty) {
      return NormalizeResult(
        output: '',
        trace: NormalizeTrace(
          input: '',
          punctuationRatio: 0,
          punctuationNeeded: false,
          splitCount: 0,
          output: '',
          totalLatencyMs: 0,
        ),
      );
    }

    final ratio = _detectPunctuationQuality(input);
    final needsPunctuation = _needsPunctuation(ratio);

    String? punctuateModel;
    int? punctuateLatencyMs;
    final String punctuated;

    if (needsPunctuation && _punctuationRunner != null) {
      final punctStopwatch = Stopwatch()..start();
      punctuated = await _punctuationRunner.restore(input);
      punctStopwatch.stop();
      punctuateModel = 'punctuation-slm';
      punctuateLatencyMs = punctStopwatch.elapsedMilliseconds;
    } else {
      punctuated = input;
    }

    final splitResult = _splitOverlong(punctuated);

    stopwatch.stop();

    return NormalizeResult(
      output: splitResult.text,
      trace: NormalizeTrace(
        input: input,
        punctuationRatio: ratio,
        punctuationNeeded: needsPunctuation,
        punctuateModel: punctuateModel,
        punctuateLatencyMs: punctuateLatencyMs,
        splitCount: splitResult.splitCount,
        splitDetails: splitResult.details,
        output: splitResult.text,
        totalLatencyMs: stopwatch.elapsedMilliseconds,
      ),
    );
  }

  /// Ratio of punctuation marks to word count.
  /// Well-punctuated English: ~1 period per 15-20 words.
  double _detectPunctuationQuality(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (words == 0) return 0;
    final punctuation = RegExp(r'[.?!]').allMatches(text).length;
    return punctuation / words;
  }

  /// Below ~1 punctuation per 20 words signals poor punctuation.
  bool _needsPunctuation(double ratio) => ratio < 0.04;

  /// Split sentences over threshold at conjunction boundaries.
  _SplitResult _splitOverlong(String text) {
    final sentences = text.split(RegExp(r'(?<=[.?!])\s+'));
    final output = <String>[];
    var splitCount = 0;
    final details = <Map<String, dynamic>>[];

    for (final sentence in sentences) {
      final proseOnly = sentence.replaceAll(_fencedCodeBlock, '');
      final wordCount = proseOnly.split(RegExp(r'\s+')).length;
      if (wordCount > _overlongThreshold) {
        final splits = _splitAtConjunctions(sentence);
        if (splits.length > 1) {
          splitCount += splits.length - 1;
          details.add({
            'original': sentence,
            'splitInto': splits.length,
          });
          output.addAll(splits);
          continue;
        }
      }
      output.add(sentence);
    }

    return _SplitResult(
      text: output.join(' '),
      splitCount: splitCount,
      details: details,
    );
  }

  /// Split at coordinating conjunctions preceded by comma.
  List<String> _splitAtConjunctions(String sentence) {
    final pattern = RegExp(r',\s+(and|but|so|or)\s+');
    final parts = <String>[];
    var remaining = sentence;

    while (true) {
      final match = pattern.firstMatch(remaining);
      if (match == null) break;

      final before = remaining.substring(0, match.start).trim();
      if (before.split(RegExp(r'\s+')).length >= 5) {
        parts.add('$before,');
        remaining = remaining.substring(match.end).trim();
        continue;
      }
      break;
    }

    if (remaining.isNotEmpty) {
      parts.add(remaining);
    }

    return parts.isEmpty ? [sentence] : parts;
  }
}

class _SplitResult {
  final String text;
  final int splitCount;
  final List<Map<String, dynamic>> details;

  _SplitResult({
    required this.text,
    required this.splitCount,
    required this.details,
  });
}
