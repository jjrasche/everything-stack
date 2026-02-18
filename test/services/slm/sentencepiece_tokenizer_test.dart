import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/slm/tokenizers/sentencepiece_tokenizer.dart';

/// Minimal vocabulary for testing Viterbi segmentation.
/// Scores are negative log probabilities (more negative = less likely).
/// The tokenizer picks the segmentation with highest total score.
Map<String, dynamic> _buildTestVocab() => {
      'pieces': [
        // Index 0: unknown token
        ['<unk>', 0.0],
        // Index 1: BOS
        ['<s>', 0.0],
        // Index 2: EOS
        ['</s>', 0.0],
        // Whitespace-prefixed pieces (SentencePiece convention: \u2581 = word boundary)
        ['\u2581', -1.0], // bare space (index 3)
        ['\u2581the', -2.0], // index 4
        ['\u2581cat', -2.5], // index 5
        ['\u2581sat', -2.5], // index 6
        ['\u2581on', -2.0], // index 7
        ['\u2581mat', -2.5], // index 8
        ['\u2581a', -1.5], // index 9
        // Subword pieces
        ['th', -3.0], // index 10
        ['e', -3.0], // index 11
        ['c', -4.0], // index 12
        ['a', -3.5], // index 13
        ['t', -3.5], // index 14
        ['s', -4.0], // index 15
        ['at', -3.0], // index 16
        ['on', -3.0], // index 17
        ['m', -4.0], // index 18
        ['ma', -3.5], // index 19
        ['\u2581th', -2.5], // index 20
        ['\u2581ca', -3.0], // index 21
        ['\u2581hello', -2.0], // index 22
        ['\u2581world', -2.0], // index 23
      ],
      'unkId': 0,
      'bosId': 1,
      'eosId': 2,
    };

void main() {
  late SentencePieceTokenizer tokenizer;

  setUp(() {
    tokenizer = SentencePieceTokenizer.fromJson(_buildTestVocab());
  });

  group('SentencePieceTokenizer', () {
    test('vocabSize matches piece count', () {
      expect(tokenizer.vocabSize, 24);
    });

    test('special token IDs match config', () {
      expect(tokenizer.unkId, 0);
      expect(tokenizer.bosId, 1);
      expect(tokenizer.eosId, 2);
    });

    test('encode empty string returns empty list', () {
      expect(tokenizer.encode(''), isEmpty);
    });

    test('encode single known word produces fewest tokens', () {
      final ids = tokenizer.encode('the');
      // "\u2581the" (score -2.0) is better than "\u2581th" + "e" (-2.5 + -3.0 = -5.5)
      expect(ids, contains(4)); // \u2581the
    });

    test('encode prefers longer pieces with better scores', () {
      final ids = tokenizer.encode('cat');
      // "\u2581cat" (-2.5) vs "\u2581ca" + "t" (-3.0 + -3.5 = -6.5)
      expect(ids, contains(5)); // \u2581cat
    });

    test('encode multi-word text uses word-boundary pieces', () {
      final ids = tokenizer.encode('the cat');
      // Should produce [\u2581the, \u2581cat] or similar segmentation
      expect(ids.length, greaterThanOrEqualTo(2));
    });

    test('encode unknown characters fall back to unk token', () {
      final ids = tokenizer.encode('\u00e9'); // e-acute, not in vocab
      expect(ids, contains(0)); // unk
    });

    test('decode reverses encode for known text', () {
      final text = 'hello world';
      final ids = tokenizer.encode(text);
      final decoded = tokenizer.decode(ids);
      expect(decoded, text);
    });

    test('decode replaces SentencePiece space marker with space', () {
      // Decoding [\u2581the] should produce "the" (leading space stripped)
      final decoded = tokenizer.decode([4]);
      expect(decoded, 'the');
    });

    test('decode joins subword pieces without extra spaces', () {
      // Decoding [20, 11] = ["\u2581th", "e"] should produce "the"
      final decoded = tokenizer.decode([20, 11]);
      expect(decoded, 'the');
    });

    test('decode handles empty token list', () {
      expect(tokenizer.decode([]), '');
    });

    test('decode skips special tokens', () {
      final decoded = tokenizer.decode([1, 4, 5, 2]); // BOS, \u2581the, \u2581cat, EOS
      expect(decoded, 'the cat');
    });

    test('encode handles repeated words', () {
      final ids = tokenizer.encode('the the');
      // Should get two instances of \u2581the
      final theCount = ids.where((id) => id == 4).length;
      expect(theCount, 2);
    });
  });
}
