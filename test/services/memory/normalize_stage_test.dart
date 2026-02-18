import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/memory/stages/normalize_stage.dart';
import 'package:everything_stack_template/services/slm/runners/punctuation_runner.dart';

class _MockPunctuationRunner implements PunctuationRunner {
  int callCount = 0;
  String lastInput = '';

  @override
  Future<String> restore(String unpunctuatedText) async {
    callCount++;
    lastInput = unpunctuatedText;
    // Simulate adding a period at end and capitalizing first letter
    if (unpunctuatedText.isEmpty) return '';
    final capitalized = unpunctuatedText[0].toUpperCase() + unpunctuatedText.substring(1);
    return '$capitalized.';
  }
}

void main() {
  group('NormalizeStage', () {
    late NormalizeStage stage;

    setUp(() {
      stage = NormalizeStage();
    });

    test('stageName is normalize', () {
      expect(stage.stageName, 'normalize');
    });

    test('passes through well-punctuated text unchanged', () async {
      const input = 'I decided to use ObjectBox. It supports all six platforms.';
      final result = await stage.process(input);

      expect(result.output, input);
      expect(result.trace.punctuationNeeded, isFalse);
    });

    test('detects low punctuation ratio', () async {
      const input = 'i went to the store and picked up some groceries and came home';
      final result = await stage.process(input);

      expect(result.trace.punctuationNeeded, isTrue);
      // Phase 1: punctuate is a no-op stub, so output equals input
      expect(result.output, input);
    });

    test('splits overlong sentences at conjunction boundaries', () async {
      const input = 'I went to the store this morning to pick up some groceries '
          'that we needed for the week ahead, and then I drove all the way home '
          'through heavy traffic on the highway, and then I started to unpack '
          'everything and organize the pantry shelves carefully, and after that I '
          'began cooking an elaborate dinner for the whole extended family.';
      final result = await stage.process(input);

      expect(result.trace.splitCount, greaterThan(0));
    });

    test('does not split short sentences', () async {
      const input = 'Short sentence. Another short one.';
      final result = await stage.process(input);

      expect(result.trace.splitCount, 0);
    });

    test('handles empty input', () async {
      final result = await stage.process('');

      expect(result.output, '');
      expect(result.trace.punctuationNeeded, isFalse);
    });
  });

  group('NormalizeStage with PunctuationRunner', () {
    late _MockPunctuationRunner mockRunner;
    late NormalizeStage stage;

    setUp(() {
      mockRunner = _MockPunctuationRunner();
      stage = NormalizeStage(punctuationRunner: mockRunner);
    });

    test('calls runner when punctuation is needed', () async {
      const input = 'i went to the store and picked up some groceries and came home';
      final result = await stage.process(input);

      expect(mockRunner.callCount, 1);
      expect(result.output, isNot(input));
      expect(result.trace.punctuationNeeded, isTrue);
      expect(result.trace.punctuateModel, isNotNull);
    });

    test('skips runner when text is well-punctuated', () async {
      const input = 'I decided to use ObjectBox. It supports all six platforms.';
      final result = await stage.process(input);

      expect(mockRunner.callCount, 0);
      expect(result.output, input);
      expect(result.trace.punctuationNeeded, isFalse);
    });

    test('skips runner on empty input', () async {
      final result = await stage.process('');

      expect(mockRunner.callCount, 0);
      expect(result.output, '');
    });
  });
}
