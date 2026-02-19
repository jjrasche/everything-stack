import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/memory/encoder_trace.dart';
import 'package:everything_stack_template/services/memory/stages/cohere_stage.dart';
import 'package:everything_stack_template/services/slm/runners/cohere_runner.dart';
import 'package:everything_stack_template/services/slm/session_pool.dart';
import 'package:everything_stack_template/services/slm/tokenizer.dart';

/// Returns predetermined scores for sequential sentence pairs.
class StubCohereRunner extends CohereRunner {
  final List<double> _scores;
  int _callIndex = 0;

  StubCohereRunner(this._scores)
      : super(
          sessionPool: _NullSessionPool(),
          tokenizer: _NullTokenizer(),
          modelId: 'stub',
          assetPath: 'stub',
        );

  @override
  Future<CoherencePair> score(String sentenceA, String sentenceB) async {
    final coherence = _scores[_callIndex++];
    return CoherencePair(
      sameTopicScore: coherence,
      differentTopicScore: 1.0 - coherence,
    );
  }
}

class _NullSessionPool implements SessionPool {
  @override
  Future<InferenceSession> acquire(String modelId, String assetPath) =>
      throw UnimplementedError();
  @override
  Future<void> release(String modelId) => throw UnimplementedError();
  @override
  Future<void> disposeAll() => throw UnimplementedError();
}

class _NullTokenizer implements Tokenizer {
  @override
  List<int> encode(String text) => throw UnimplementedError();
  @override
  String decode(List<int> tokenIds) => throw UnimplementedError();
  @override
  int get vocabSize => 0;
  @override
  int? get bosId => 101;
  @override
  int? get eosId => 102;
  @override
  int? get padId => 0;
  @override
  int get unkId => 100;
}

List<Sentence> _makeSentences(int count) => List.generate(
      count,
      (i) => Sentence(id: 'S${i + 1}', text: 'Sentence ${i + 1}.'),
    );

void main() {
  group('CohereStage two-loop resplit', () {
    test('resplits large span at stricter threshold', () async {
      // 12 sentences, all same topic at 0.5 threshold
      // but pair 5-6 has score 0.6 (below resplit threshold of 0.65)
      final scores = [
        0.95, // S1-S2
        0.90, // S2-S3
        0.85, // S3-S4
        0.92, // S4-S5
        0.60, // S5-S6 <-- resplit boundary
        0.88, // S6-S7
        0.91, // S7-S8
        0.87, // S8-S9
        0.93, // S9-S10
        0.89, // S10-S11
        0.94, // S11-S12
      ];

      final stage = CohereStage(
        cohereRunner: StubCohereRunner(scores),
        resplitThreshold: 0.65,
        maxSpanSentences: 10,
      );

      final result = await stage.process(
        CohereInput(sentences: _makeSentences(12)),
      );

      expect(result.spans, hasLength(2));
      expect(result.spans[0].sentenceIds, ['S1', 'S2', 'S3', 'S4', 'S5']);
      expect(result.spans[1].sentenceIds,
          ['S6', 'S7', 'S8', 'S9', 'S10', 'S11', 'S12']);
    });

    test('splits at weakest score when all scores above resplit threshold',
        () async {
      // 12 sentences, all high coherence — nothing below 0.65
      // weakest pair is S6-S7 at 0.80
      final scores = [
        0.95, // S1-S2
        0.90, // S2-S3
        0.92, // S3-S4
        0.88, // S4-S5
        0.85, // S5-S6
        0.80, // S6-S7 <-- weakest, forced split here
        0.91, // S7-S8
        0.93, // S8-S9
        0.89, // S9-S10
        0.94, // S10-S11
        0.96, // S11-S12
      ];

      final stage = CohereStage(
        cohereRunner: StubCohereRunner(scores),
        resplitThreshold: 0.65,
        maxSpanSentences: 10,
      );

      final result = await stage.process(
        CohereInput(sentences: _makeSentences(12)),
      );

      expect(result.spans, hasLength(2));
      expect(result.spans[0].sentenceIds,
          ['S1', 'S2', 'S3', 'S4', 'S5', 'S6']);
      expect(result.spans[1].sentenceIds,
          ['S7', 'S8', 'S9', 'S10', 'S11', 'S12']);
    });

    test('does not resplit spans under maxSpanSentences', () async {
      // 8 sentences, all same topic — under threshold of 10
      final scores = List.filled(7, 0.90);

      final stage = CohereStage(
        cohereRunner: StubCohereRunner(scores),
        resplitThreshold: 0.65,
        maxSpanSentences: 10,
      );

      final result = await stage.process(
        CohereInput(sentences: _makeSentences(8)),
      );

      expect(result.spans, hasLength(1));
      expect(result.spans.first.sentenceIds.length, 8);
    });

    test('preserves first-pass boundaries and only resplits large spans',
        () async {
      // 16 sentences: first-pass boundary at S5-S6 (score=0.3)
      // First span: S1-S5 (5 sentences, under cap)
      // Second span: S6-S16 (11 sentences, over cap, resplit at S10-S11 score=0.60)
      final scores = [
        0.90, // S1-S2
        0.85, // S2-S3
        0.92, // S3-S4
        0.88, // S4-S5
        0.30, // S5-S6 <-- first-pass boundary
        0.95, // S6-S7
        0.91, // S7-S8
        0.87, // S8-S9
        0.93, // S9-S10
        0.60, // S10-S11 <-- resplit boundary
        0.89, // S11-S12
        0.94, // S12-S13
        0.96, // S13-S14
        0.91, // S14-S15
        0.88, // S15-S16
      ];

      final stage = CohereStage(
        cohereRunner: StubCohereRunner(scores),
        resplitThreshold: 0.65,
        maxSpanSentences: 10,
      );

      final result = await stage.process(
        CohereInput(sentences: _makeSentences(16)),
      );

      expect(result.spans, hasLength(3));
      expect(result.spans[0].sentenceIds, ['S1', 'S2', 'S3', 'S4', 'S5']);
      expect(result.spans[1].sentenceIds,
          ['S6', 'S7', 'S8', 'S9', 'S10']);
      expect(result.spans[2].sentenceIds,
          ['S11', 'S12', 'S13', 'S14', 'S15', 'S16']);
    });

    test('recursively resplits until all spans under cap', () async {
      // 20 sentences, all high coherence with two weak points
      // After first resplit at weakest (S10-S11 = 0.80), both sub-spans are 10
      // Each still at cap, so resplit again at their weakest internal scores
      final scores = [
        0.95, // S1-S2
        0.90, // S2-S3
        0.85, // S3-S4 <-- weakest in first sub-span
        0.92, // S4-S5
        0.88, // S5-S6
        0.91, // S6-S7
        0.93, // S7-S8
        0.89, // S8-S9
        0.94, // S9-S10
        0.80, // S10-S11 <-- weakest overall, first forced split
        0.96, // S11-S12
        0.92, // S12-S13
        0.87, // S13-S14 <-- weakest in second sub-span
        0.91, // S14-S15
        0.93, // S15-S16
        0.90, // S16-S17
        0.88, // S17-S18
        0.95, // S18-S19
        0.92, // S19-S20
      ];

      final stage = CohereStage(
        cohereRunner: StubCohereRunner(scores),
        resplitThreshold: 0.65,
        maxSpanSentences: 10,
      );

      final result = await stage.process(
        CohereInput(sentences: _makeSentences(20)),
      );

      // All spans should be under 10 sentences
      for (final span in result.spans) {
        expect(span.sentenceIds.length, lessThanOrEqualTo(10));
      }
      // Total sentence coverage preserved
      final allIds = result.spans.expand((s) => s.sentenceIds).toList();
      expect(allIds.length, 20);
    });

    test('default stage has no resplit behavior', () async {
      // Default CohereStage (no resplitThreshold/maxSpanSentences)
      final scores = List.filled(14, 0.90);

      final stage = CohereStage(
        cohereRunner: StubCohereRunner(scores),
      );

      final result = await stage.process(
        CohereInput(sentences: _makeSentences(15)),
      );

      // No resplit — all in one span
      expect(result.spans, hasLength(1));
      expect(result.spans.first.sentenceIds.length, 15);
    });
  });
}
