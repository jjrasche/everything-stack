import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/slm/runners/cohere_runner.dart';
import 'package:everything_stack_template/services/slm/session_pool.dart';
import 'package:everything_stack_template/services/slm/tokenizer.dart';

/// Mock tokenizer that maps each word to a unique ID.
class _MockTokenizer implements Tokenizer {
  final Map<String, int> _wordToId = {};
  final Map<int, String> _idToWord = {};
  int _nextId = 3;

  @override
  int get vocabSize => _nextId;
  @override
  int get bosId => 0; // [CLS]
  @override
  int get eosId => 1; // [SEP]
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

/// Mock session returning configurable binary coherence logits.
/// Output: 'logits' with 2 values [different_topic, same_topic].
class _MockCoherenceSession implements InferenceSession {
  final List<double> logits;
  List<int>? lastInputIds;
  List<int>? lastAttentionMask;
  List<int>? lastTokenTypeIds;

  _MockCoherenceSession({required this.logits});

  @override
  List<String> get inputNames => ['input_ids', 'attention_mask', 'token_type_ids'];

  @override
  List<String> get outputNames => ['logits'];

  @override
  Future<Map<String, List<dynamic>>> run(Map<String, List<int>> inputs) async {
    lastInputIds = inputs['input_ids'];
    lastAttentionMask = inputs['attention_mask'];
    lastTokenTypeIds = inputs['token_type_ids'];
    return {'logits': logits};
  }

  @override
  Future<void> close() async {}
}

class _MockSessionPool implements SessionPool {
  final InferenceSession _session;

  _MockSessionPool(this._session);

  @override
  Future<InferenceSession> acquire(String modelId, String assetPath) async =>
      _session;

  @override
  Future<void> release(String modelId) async {}

  @override
  Future<void> disposeAll() async {}
}

void main() {
  group('CohereRunner', () {
    late _MockTokenizer tokenizer;

    setUp(() {
      tokenizer = _MockTokenizer();
    });

    test('score returns high coherence for same-topic logits', () async {
      // Logits: [different=-2.0, same=5.0]
      final session = _MockCoherenceSession(logits: [-2.0, 5.0]);
      final pool = _MockSessionPool(session);
      final runner = CohereRunner(
        sessionPool: pool,
        tokenizer: tokenizer,
        modelId: 'test-coherence',
        assetPath: 'assets/test.onnx',
      );

      final result = await runner.score('The cat sat on the mat', 'The cat was comfortable');
      expect(result.sameTopicScore, greaterThan(0.99));
      expect(result.coherence, greaterThan(0.99));
      expect(result.differentTopicScore, lessThan(0.01));
    });

    test('score returns low coherence for different-topic logits', () async {
      // Logits: [different=5.0, same=-2.0]
      final session = _MockCoherenceSession(logits: [5.0, -2.0]);
      final pool = _MockSessionPool(session);
      final runner = CohereRunner(
        sessionPool: pool,
        tokenizer: tokenizer,
        modelId: 'test-coherence',
        assetPath: 'assets/test.onnx',
      );

      final result = await runner.score('The cat sat on the mat', 'Stock prices fell sharply');
      expect(result.differentTopicScore, greaterThan(0.99));
      expect(result.coherence, lessThan(0.01));
    });

    test('score builds CLS-SEP-SEP input format', () async {
      final session = _MockCoherenceSession(logits: [0.0, 0.0]);
      final pool = _MockSessionPool(session);
      final runner = CohereRunner(
        sessionPool: pool,
        tokenizer: tokenizer,
        modelId: 'test-coherence',
        assetPath: 'assets/test.onnx',
      );

      await runner.score('hello', 'world');

      final inputIds = session.lastInputIds!;
      // [CLS] hello [SEP] world [SEP]
      expect(inputIds.first, tokenizer.bosId);
      expect(inputIds[2], tokenizer.eosId);
      expect(inputIds.last, tokenizer.eosId);
      expect(inputIds.length, 5);
    });

    test('score builds correct token type IDs', () async {
      final session = _MockCoherenceSession(logits: [0.0, 0.0]);
      final pool = _MockSessionPool(session);
      final runner = CohereRunner(
        sessionPool: pool,
        tokenizer: tokenizer,
        modelId: 'test-coherence',
        assetPath: 'assets/test.onnx',
      );

      await runner.score('hello', 'world');

      final typeIds = session.lastTokenTypeIds!;
      // [CLS]=0 hello=0 [SEP]=0 world=1 [SEP]=1
      expect(typeIds, [0, 0, 0, 1, 1]);
    });

    test('score normalizes logits via softmax summing to 1', () async {
      final session = _MockCoherenceSession(logits: [1.0, 3.0]);
      final pool = _MockSessionPool(session);
      final runner = CohereRunner(
        sessionPool: pool,
        tokenizer: tokenizer,
        modelId: 'test-coherence',
        assetPath: 'assets/test.onnx',
      );

      final result = await runner.score('a', 'b');
      final sum = result.sameTopicScore + result.differentTopicScore;
      expect(sum, closeTo(1.0, 0.001));
      expect(result.sameTopicScore, greaterThan(result.differentTopicScore));
    });

    test('score truncates long sentences to fit model limit', () async {
      final session = _MockCoherenceSession(logits: [0.0, 0.0]);
      final pool = _MockSessionPool(session);
      final runner = CohereRunner(
        sessionPool: pool,
        tokenizer: tokenizer,
        modelId: 'test-coherence',
        assetPath: 'assets/test.onnx',
      );

      final longA = List.generate(300, (i) => 'word$i').join(' ');
      final longB = List.generate(300, (i) => 'term$i').join(' ');

      await runner.score(longA, longB);

      final inputIds = session.lastInputIds!;
      expect(inputIds.length, lessThanOrEqualTo(512));
      expect(inputIds.first, tokenizer.bosId);
      expect(inputIds.last, tokenizer.eosId);
    });
  });
}
