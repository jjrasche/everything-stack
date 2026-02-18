import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/slm/tokenizers/wordpiece_tokenizer.dart';

/// Minimal vocab for testing WordPiece logic.
Map<String, dynamic> _buildTestVocab() {
  final tokens = [
    '[PAD]',   // 0
    '[UNK]',   // 1
    '[CLS]',   // 2
    '[SEP]',   // 3
    'hello',   // 4
    'world',   // 5
    'the',     // 6
    'cat',     // 7
    'sat',     // 8
    'on',      // 9
    'mat',     // 10
    '.',        // 11
    ',',        // 12
    'un',      // 13
    '##known', // 14
    '##s',     // 15
    '##ing',   // 16
    'play',    // 17
    '##ed',    // 18
    'a',       // 19
  ];

  return {
    'tokens': tokens,
    'unkId': 1,
    'clsId': 2,
    'sepId': 3,
    'padId': 0,
    'doLowerCase': true,
  };
}

void main() {
  late WordPieceTokenizer tokenizer;

  setUp(() {
    tokenizer = WordPieceTokenizer.fromJson(_buildTestVocab());
  });

  group('WordPieceTokenizer', () {
    test('encode splits known words into token IDs', () {
      final ids = tokenizer.encode('hello world');
      expect(ids, [4, 5]);
    });

    test('encode lowercases input when doLowerCase is true', () {
      final ids = tokenizer.encode('Hello World');
      expect(ids, [4, 5]);
    });

    test('encode handles subword pieces with ## prefix', () {
      // "unknown" -> "un" + "##known"
      final ids = tokenizer.encode('unknown');
      expect(ids, [13, 14]);
    });

    test('encode isolates punctuation as separate tokens', () {
      final ids = tokenizer.encode('hello.');
      expect(ids, [4, 11]);
    });

    test('encode returns unkId for fully unknown words', () {
      final ids = tokenizer.encode('xyz');
      expect(ids, [tokenizer.unkId]);
    });

    test('encode handles empty string', () {
      expect(tokenizer.encode(''), isEmpty);
    });

    test('encode handles multiple subword suffixes', () {
      // "playing" -> "play" + "##ing"
      final ids = tokenizer.encode('playing');
      expect(ids, [17, 16]);
    });

    test('decode reconstructs text from token IDs', () {
      // "hello world" -> [4, 5]
      final text = tokenizer.decode([4, 5]);
      expect(text, 'hello world');
    });

    test('decode joins continuation pieces without spaces', () {
      // "un" + "##known" -> "unknown"
      final text = tokenizer.decode([13, 14]);
      expect(text, 'unknown');
    });

    test('decode skips special token IDs', () {
      // [CLS] hello [SEP] -> "hello"
      final text = tokenizer.decode([2, 4, 3]);
      expect(text, 'hello');
    });

    test('vocabSize matches token count', () {
      expect(tokenizer.vocabSize, 20);
    });

    test('special token IDs are correct', () {
      expect(tokenizer.bosId, 2); // [CLS]
      expect(tokenizer.eosId, 3); // [SEP]
      expect(tokenizer.padId, 0); // [PAD]
      expect(tokenizer.unkId, 1); // [UNK]
    });

    test('encode round-trips through decode for known words', () {
      const input = 'the cat sat on a mat';
      final ids = tokenizer.encode(input);
      final output = tokenizer.decode(ids);
      expect(output, input);
    });
  });
}
