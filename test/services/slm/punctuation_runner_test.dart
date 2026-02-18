import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/slm/runners/punctuation_runner.dart';
import 'package:everything_stack_template/services/slm/session_pool.dart';
import 'package:everything_stack_template/services/slm/tokenizer.dart';

/// Mock tokenizer that maps each word to a unique ID.
/// Simulates SentencePiece behavior for testing runner logic.
class _MockTokenizer implements Tokenizer {
  final Map<String, int> _wordToId = {};
  final Map<int, String> _idToWord = {};
  int _nextId = 3;

  @override
  int get vocabSize => _nextId;
  @override
  int get bosId => 0;
  @override
  int get eosId => 1;
  @override
  int? get padId => 2;
  @override
  int get unkId => -1;

  @override
  List<int> encode(String text) {
    final words = text.split(' ').where((w) => w.isNotEmpty);
    return words.map((w) {
      if (!_wordToId.containsKey(w)) {
        _wordToId[w] = _nextId;
        _idToWord[_nextId] = w;
        _nextId++;
      }
      return _wordToId[w]!;
    }).toList();
  }

  @override
  String decode(List<int> tokenIds) {
    return tokenIds
        .where((id) => id != bosId && id != eosId && id != padId)
        .map((id) => _idToWord[id] ?? '<unk>')
        .join(' ');
  }
}

/// Mock session that returns pre-configured label indices.
/// Simulates the 4-output punctuation model:
/// [pre_preds, post_preds, cap_preds, seg_preds]
class _MockInferenceSession implements InferenceSession {
  final List<int> postPreds;
  final List<List<int>> capPreds;

  _MockInferenceSession({
    required this.postPreds,
    required this.capPreds,
  });

  @override
  List<String> get inputNames => ['input_ids'];

  @override
  List<String> get outputNames => ['pre_preds', 'post_preds', 'cap_preds', 'seg_preds'];

  @override
  Future<Map<String, List<dynamic>>> run(Map<String, List<int>> inputs) async {
    final seqLen = inputs['input_ids']!.length;
    // Real model outputs fixed max_subword_len per position.
    // Pad each position's cap predictions to uniform stride.
    final maxLen = capPreds.fold<int>(0, (m, c) => c.length > m ? c.length : m);
    final flatCap = <int>[];
    for (final c in capPreds) {
      flatCap.addAll(c);
      for (var p = c.length; p < maxLen; p++) {
        flatCap.add(0);
      }
    }
    return {
      'pre_preds': List<int>.filled(seqLen, 0),
      'post_preds': postPreds,
      'cap_preds': flatCap,
      'seg_preds': List<int>.filled(seqLen, 0),
    };
  }

  @override
  Future<void> close() async {}
}

class _MockSessionPool implements SessionPool {
  final InferenceSession _session;

  _MockSessionPool(this._session);

  @override
  Future<InferenceSession> acquire(String modelId, String assetPath) async => _session;

  @override
  Future<void> release(String modelId) async {}

  @override
  Future<void> disposeAll() async {}
}

void main() {
  group('PunctuationRunner', () {
    test('restore adds period at end of sentence', () async {
      final tokenizer = _MockTokenizer();
      // Encode to learn token IDs
      final ids = tokenizer.encode('hello world');
      // +2 for BOS/EOS
      final seqLen = ids.length + 2;

      // Post-punct labels: 0=NULL, 2=period
      // [BOS, hello, world, EOS] -> [0, 0, 2, 0]
      final postPreds = List<int>.filled(seqLen, 0);
      postPreds[seqLen - 2] = 2; // period after "world"

      // Cap labels: all lowercase (0), max_subword_len=1 for simplicity
      final capPreds = List.generate(seqLen, (_) => [0]);

      final session = _MockInferenceSession(
        postPreds: postPreds,
        capPreds: capPreds,
      );
      final pool = _MockSessionPool(session);
      final runner = PunctuationRunner(
        sessionPool: pool,
        tokenizer: tokenizer,
        modelId: 'test-punct',
        assetPath: 'assets/test.onnx',
      );

      final result = await runner.restore('hello world');
      expect(result, contains('.'));
    });

    test('restore capitalizes first word of sentence', () async {
      final tokenizer = _MockTokenizer();
      final ids = tokenizer.encode('hello');
      final seqLen = ids.length + 2;

      final postPreds = List<int>.filled(seqLen, 0);
      postPreds[seqLen - 2] = 2; // period after "hello"

      // Cap: capitalize first character of "hello"
      // [BOS, hello, EOS] -> BOS has no chars, hello=[1,0,0,0,0], EOS no chars
      final capPreds = <List<int>>[
        [0], // BOS
        [1, 0, 0, 0, 0], // hello -> Hello
        [0], // EOS
      ];

      final session = _MockInferenceSession(
        postPreds: postPreds,
        capPreds: capPreds,
      );
      final pool = _MockSessionPool(session);
      final runner = PunctuationRunner(
        sessionPool: pool,
        tokenizer: tokenizer,
        modelId: 'test-punct',
        assetPath: 'assets/test.onnx',
      );

      final result = await runner.restore('hello');
      expect(result, startsWith('H'));
    });

    test('restore adds comma between clauses', () async {
      final tokenizer = _MockTokenizer();
      final ids = tokenizer.encode('i went to the store and bought milk');
      final seqLen = ids.length + 2;

      // Post-punct: comma after "store" (index 5 in tokens = index 6 with BOS)
      final postPreds = List<int>.filled(seqLen, 0);
      postPreds[5] = 3; // comma after "store"
      postPreds[seqLen - 2] = 2; // period at end

      final capPreds = List.generate(seqLen, (_) => [0]);
      capPreds[1] = [1]; // capitalize "i" -> "I"

      final session = _MockInferenceSession(
        postPreds: postPreds,
        capPreds: capPreds,
      );
      final pool = _MockSessionPool(session);
      final runner = PunctuationRunner(
        sessionPool: pool,
        tokenizer: tokenizer,
        modelId: 'test-punct',
        assetPath: 'assets/test.onnx',
      );

      final result = await runner.restore('i went to the store and bought milk');
      expect(result, contains(','));
      expect(result, startsWith('I'));
    });

    test('restore passes through empty string', () async {
      final tokenizer = _MockTokenizer();
      final session = _MockInferenceSession(
        postPreds: [],
        capPreds: [],
      );
      final pool = _MockSessionPool(session);
      final runner = PunctuationRunner(
        sessionPool: pool,
        tokenizer: tokenizer,
        modelId: 'test-punct',
        assetPath: 'assets/test.onnx',
      );

      final result = await runner.restore('');
      expect(result, '');
    });
  });
}
