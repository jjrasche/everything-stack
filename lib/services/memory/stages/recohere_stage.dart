import '../../slm/runners/cohere_runner.dart';
import '../encoder_stage.dart';
import '../encoder_trace.dart';

class RecoherInput {
  final List<ConceptSpan> spans;

  RecoherInput({required this.spans});
}

class RecoherResult {
  final List<ConceptSpan> spans;
  final RecoherTrace trace;

  RecoherResult({required this.spans, required this.trace});
}

/// Merge non-adjacent spans that share topic coherence.
/// Handles divergent thinking: speaker leaves topic, returns later.
/// Uses CohereRunner pairwise scoring on all non-adjacent span pairs.
class RecoherStage implements EncoderStage<RecoherInput, RecoherResult> {
  final CohereRunner? _cohereRunner;
  final double _mergeThreshold;

  static const double _defaultMergeThreshold = 0.75;

  RecoherStage({
    CohereRunner? cohereRunner,
    double? mergeThreshold,
  })  : _cohereRunner = cohereRunner,
        _mergeThreshold = mergeThreshold ?? _defaultMergeThreshold;

  @override
  String get stageName => 'recohere';

  @override
  Future<RecoherResult> process(RecoherInput input) async {
    final stopwatch = Stopwatch()..start();

    if (input.spans.length < 3 || _cohereRunner == null) {
      stopwatch.stop();
      return RecoherResult(
        spans: input.spans,
        trace: RecoherTrace(
          input: input.spans,
          output: input.spans,
          merges: [],
          model: _cohereRunner != null ? 'bert-wiki-paragraphs' : 'none',
          threshold: _mergeThreshold,
          latencyMs: stopwatch.elapsedMilliseconds,
        ),
      );
    }

    final mergePairs = await _findMergePairs(input.spans);
    final mergedSpans = _applyMerges(input.spans, mergePairs);

    stopwatch.stop();
    return RecoherResult(
      spans: mergedSpans,
      trace: RecoherTrace(
        input: input.spans,
        output: mergedSpans,
        merges: mergePairs,
        model: 'bert-wiki-paragraphs',
        threshold: _mergeThreshold,
        latencyMs: stopwatch.elapsedMilliseconds,
      ),
    );
  }

  /// Score all non-adjacent span pairs, return those above threshold.
  Future<List<RecoherMerge>> _findMergePairs(
    List<ConceptSpan> spans,
  ) async {
    final candidates = <RecoherMerge>[];

    for (var i = 0; i < spans.length; i++) {
      // Skip adjacent pairs (i+1) — cohere already handled those
      for (var j = i + 2; j < spans.length; j++) {
        final pair = await _cohereRunner!.score(spans[i].text, spans[j].text);

        if (pair.coherence >= _mergeThreshold) {
          candidates.add(RecoherMerge(
            mergedSpanIds: [spans[i].spanId, spans[j].spanId],
            similarity: pair.coherence,
          ));
        }
      }
    }

    // Sort by highest similarity first for greedy merge
    candidates.sort((a, b) => b.similarity.compareTo(a.similarity));
    return candidates;
  }

  /// Greedy merge: each span can only participate in one merge.
  List<ConceptSpan> _applyMerges(
    List<ConceptSpan> spans,
    List<RecoherMerge> mergePairs,
  ) {
    if (mergePairs.isEmpty) return spans;

    final spanMap = {for (final s in spans) s.spanId: s};
    final consumed = <String>{};
    final mergedSpans = <String, ConceptSpan>{};

    for (final merge in mergePairs) {
      final idA = merge.mergedSpanIds[0];
      final idB = merge.mergedSpanIds[1];
      if (consumed.contains(idA) || consumed.contains(idB)) continue;

      consumed.add(idB);
      final spanA = mergedSpans[idA] ?? spanMap[idA]!;
      final spanB = spanMap[idB]!;
      mergedSpans[idA] = ConceptSpan(
        spanId: idA,
        sentenceIds: [...spanA.sentenceIds, ...spanB.sentenceIds],
        text: '${spanA.text} ${spanB.text}',
      );
    }

    final result = <ConceptSpan>[];
    var spanIndex = 0;

    for (final span in spans) {
      if (consumed.contains(span.spanId)) continue;

      final merged = mergedSpans[span.spanId] ?? span;
      result.add(ConceptSpan(
        spanId: 'span_$spanIndex',
        sentenceIds: merged.sentenceIds,
        text: merged.text,
      ));
      spanIndex++;
    }

    return result;
  }
}
