import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/memory/stages/segment_stage.dart';

void main() {
  group('SegmentStage', () {
    late SegmentStage stage;

    setUp(() {
      stage = SegmentStage();
    });

    test('stageName is segment', () {
      expect(stage.stageName, 'segment');
    });

    test('splits text on sentence boundaries', () async {
      const input = 'I use ObjectBox. It supports all platforms. The queries are fast.';
      final result = await stage.process(input);

      expect(result.sentences, hasLength(3));
      expect(result.sentences[0].id, 'S1');
      expect(result.sentences[0].text, 'I use ObjectBox.');
      expect(result.sentences[1].id, 'S2');
      expect(result.sentences[2].id, 'S3');
    });

    test('handles question marks and exclamation points', () async {
      const input = 'Is this working? Yes it is! That looks great.';
      final result = await stage.process(input);

      expect(result.sentences, hasLength(3));
      expect(result.sentences[0].text, 'Is this working?');
      expect(result.sentences[1].text, 'Yes it is!');
      expect(result.sentences[2].text, 'That looks great.');
    });

    test('respects common abbreviations', () async {
      const input = 'Dr. Smith works at Inc. Corp. He is experienced.';
      final result = await stage.process(input);

      // Should not split on Dr. or Inc. or Corp.
      expect(result.sentences.length, lessThanOrEqualTo(2));
    });

    test('handles single sentence', () async {
      const input = 'Just one sentence.';
      final result = await stage.process(input);

      expect(result.sentences, hasLength(1));
      expect(result.sentences[0].text, 'Just one sentence.');
    });

    test('handles empty input', () async {
      final result = await stage.process('');

      expect(result.sentences, isEmpty);
    });

    test('excludes fenced code blocks from sentence splitting', () async {
      const input = 'Here is an example.\n\n```javascript\nconst x = {a: 1, b: 2};\nconsole.log(x.value);\n```\n\nThis pattern works well.';
      final result = await stage.process(input);

      expect(result.sentences, hasLength(2));
      expect(result.sentences[0].text, 'Here is an example.');
      expect(result.sentences[1].text, 'This pattern works well.');
    });

    test('excludes indented code blocks from sentence splitting', () async {
      const input = 'Consider this approach.\n\n    final store = await openStore();\n    store.close();\n\nThe store handles persistence.';
      final result = await stage.process(input);

      expect(result.sentences, hasLength(2));
      expect(result.sentences[0].text, 'Consider this approach.');
      expect(result.sentences[1].text, 'The store handles persistence.');
    });

    test('filters fragments shorter than 3 words', () async {
      const input = 'ObjectBox is fast. Ok. It handles millions of records per second.';
      final result = await stage.process(input);

      expect(result.sentences, hasLength(2));
      expect(result.sentences[0].text, 'ObjectBox is fast.');
      expect(result.sentences[1].text, 'It handles millions of records per second.');
    });

    test('strips markdown headers and bold markers', () async {
      const input = '## The Pattern\n\n**Inference Instance** handles all cases. This is the core abstraction.';
      final result = await stage.process(input);

      expect(result.sentences, hasLength(2));
      expect(result.sentences[0].text, 'Inference Instance handles all cases.');
      expect(result.sentences[1].text, 'This is the core abstraction.');
    });

    test('strips bullet and numbered list prefixes', () async {
      const input = '- First item is important. Second follows naturally.\n- Third item stands alone here.';
      final result = await stage.process(input);

      expect(result.sentences, hasLength(3));
      expect(result.sentences[0].text, 'First item is important.');
    });
  });
}
