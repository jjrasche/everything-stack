import '../../slm/runners/filter_runner.dart';
import '../encoder_stage.dart';
import '../encoder_trace.dart';

class FilterInput {
  final List<ConceptSpan> spans;

  FilterInput({required this.spans});
}

class FilterResult {
  final List<FilterDecision> decisions;
  final FilterTrace trace;

  FilterResult({required this.decisions, required this.trace});

  List<ConceptSpan> extractSpans(List<ConceptSpan> allSpans) {
    final extractIds =
        decisions.where((d) => d.isExtract).map((d) => d.spanId).toSet();
    return allSpans.where((s) => extractIds.contains(s.spanId)).toList();
  }
}

/// Stateless noise filter: extract or skip per span.
/// Uses on-device FilterRunner (SetFit DeBERTa-v3-small).
class FilterStage implements EncoderStage<FilterInput, FilterResult> {
  final FilterRunner _filterRunner;

  FilterStage({required FilterRunner filterRunner})
      : _filterRunner = filterRunner;

  @override
  String get stageName => 'filter';

  @override
  Future<FilterResult> process(FilterInput input) async {
    final stopwatch = Stopwatch()..start();

    if (input.spans.isEmpty) {
      stopwatch.stop();
      return FilterResult(
        decisions: [],
        trace: FilterTrace(decisions: [], totalLatencyMs: 0),
      );
    }

    final decisions = <FilterDecision>[];
    for (final span in input.spans) {
      final decision = await _filterSpan(span);
      decisions.add(decision);
    }

    stopwatch.stop();
    return FilterResult(
      decisions: decisions,
      trace: FilterTrace(
        decisions: decisions,
        totalLatencyMs: stopwatch.elapsedMilliseconds,
      ),
    );
  }

  Future<FilterDecision> _filterSpan(ConceptSpan span) async {
    final spanWatch = Stopwatch()..start();

    final prediction = await _filterRunner.predict(span.text);

    spanWatch.stop();
    return FilterDecision(
      spanId: span.spanId,
      label: prediction.isExtract ? 'extract' : 'skip',
      extractScore: prediction.extractScore,
      skipScore: prediction.skipScore,
      model: 'deberta-v3-small-setfit',
      latencyMs: spanWatch.elapsedMilliseconds,
    );
  }
}
