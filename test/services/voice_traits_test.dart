/// # VoiceTraits Tests
///
/// Unit tests for contrastive few-shot example retrieval.

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/voice_traits.dart';
import 'package:everything_stack_template/services/types/voice_traits_types.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search_service.dart';
import 'package:everything_stack_template/services/semantic_search/search_result.dart';
import 'package:everything_stack_template/services/semantic_search/chunk.dart';
import 'package:everything_stack_template/services/hnsw_index.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/core/invocation.dart' as inv;
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/core/base_entity.dart';

// Type alias for easier use
typedef Invocation = inv.Invocation;

// ============ Mock Classes ============

class MockSemanticSearchService extends SemanticSearchService {
  List<SemanticSearchResult> searchResults = [];
  bool shouldThrow = false;

  MockSemanticSearchService() : super(
    index: _FakeHnswIndex(),
    embeddingService: _FakeEmbeddingService(),
    entityLoader: MockEntityLoader(),
  );

  @override
  Future<List<SemanticSearchResult>> search(
    String query, {
    List<String>? entityTypes,
    int limit = 10,
  }) async {
    if (shouldThrow) {
      throw StateError('Index is stale');
    }
    return searchResults.take(limit).toList();
  }
}

// Minimal fake implementations that throw on any method call
// We don't actually call these - MockSemanticSearchService overrides search()
class _FakeHnswIndex extends HnswIndex {
  _FakeHnswIndex() : super(dimensions: 384);
}

class _FakeEmbeddingService extends EmbeddingService {
  _FakeEmbeddingService();

  @override
  Future<List<double>> generate(String text) async {
    throw UnimplementedError('Should not be called in tests');
  }
}

class MockEntityLoader implements EntityLoader {
  @override
  Future<BaseEntity?> getById(String uuid) async => null;
}

class MockInvocationRepository implements InvocationRepository<Invocation> {
  final Map<String, Invocation> _invocations = {};

  void addInvocation(Invocation inv) {
    _invocations[inv.uuid] = inv;
  }

  @override
  Future<Invocation?> findById(String id) async => _invocations[id];

  @override
  Future<List<Invocation>> findAll() async => _invocations.values.toList();

  @override
  Future<Invocation> save(Invocation entity) async {
    _invocations[entity.uuid] = entity;
    return entity;
  }

  @override
  Future<bool> delete(String id) async {
    return _invocations.remove(id) != null;
  }

  @override
  Future<List<Invocation>> findByEventId(String eventId) async {
    return _invocations.values.where((i) => i.eventId == eventId).toList();
  }

  @override
  Future<List<Invocation>> findByComponentType(String componentType) async {
    return _invocations.values.where((i) => i.componentType == componentType).toList();
  }

  @override
  Future<List<Invocation>> findSince(DateTime since) async {
    return _invocations.values.where((i) => i.createdAt.isAfter(since)).toList();
  }

  @override
  Future<List<Invocation>> findByContextType(String contextType) async {
    return [];
  }

  @override
  Future<List<Invocation>> findByIds(List<String> ids) async {
    return _invocations.values.where((i) => ids.contains(i.uuid)).toList();
  }
}

class MockFeedbackRepository implements FeedbackRepository {
  final List<Feedback> _feedbacks = [];

  void addFeedback(Feedback f) {
    _feedbacks.add(f);
  }

  @override
  Future<List<Feedback>> findByInvocationId(String invocationId) async {
    return _feedbacks.where((f) => f.invocationId == invocationId).toList();
  }

  @override
  Future<List<Feedback>> findByInvocationIds(List<String> invocationIds) async {
    return _feedbacks.where((f) => invocationIds.contains(f.invocationId)).toList();
  }

  @override
  Future<List<Feedback>> findByTurn(String turnId) async {
    return _feedbacks.where((f) => f.turnId == turnId).toList();
  }

  @override
  Future<List<Feedback>> findByTurnAndComponent(String turnId, String componentType) async {
    return _feedbacks.where((f) => f.turnId == turnId && f.componentType == componentType).toList();
  }

  @override
  Future<List<Feedback>> findByContextType(String contextType) async => [];

  @override
  Future<List<Feedback>> findAllConversational() async {
    return _feedbacks.where((f) => f.turnId != null).toList();
  }

  @override
  Future<List<Feedback>> findAllBackground() async {
    return _feedbacks.where((f) => f.turnId == null).toList();
  }

  @override
  Future<Feedback> save(Feedback feedback) async {
    _feedbacks.add(feedback);
    return feedback;
  }

  @override
  Future<bool> delete(String id) async {
    final len = _feedbacks.length;
    _feedbacks.removeWhere((f) => f.uuid == id);
    return _feedbacks.length < len;
  }

  @override
  Future<int> deleteByTurn(String turnId) async {
    final len = _feedbacks.length;
    _feedbacks.removeWhere((f) => f.turnId == turnId);
    return len - _feedbacks.length;
  }
}

// ============ Test Helpers ============

Invocation createLLMInvocation({
  required String uuid,
  required String query,
  required String response,
}) {
  return Invocation(
    eventId: 'evt_$uuid',
    componentType: 'llm',
    implementer: 'groq',
    success: true,
    confidence: 0.9,
    input: {
      'messages': [
        {'role': 'user', 'content': query}
      ]
    },
    output: {
      'content': response,
    },
  )..uuid = uuid;
}

Chunk createChunk({
  required String id,
  required String sourceEntityId,
}) {
  return Chunk(
    id: id,
    sourceEntityId: sourceEntityId,
    sourceEntityType: 'Invocation',
    startToken: 0,
    endToken: 10,
    config: 'invocation',
    text: 'Test chunk text',
  );
}

// ============ Tests ============

void main() {
  group('VoiceTraits', () {
    late MockSemanticSearchService mockSearch;
    late MockInvocationRepository mockInvRepo;
    late MockFeedbackRepository mockFeedbackRepo;
    late VoiceTraits voiceTraits;

    setUp(() {
      mockSearch = MockSemanticSearchService();
      mockInvRepo = MockInvocationRepository();
      mockFeedbackRepo = MockFeedbackRepository();
      voiceTraits = VoiceTraits(
        searchService: mockSearch,
        invocationRepo: mockInvRepo,
        feedbackRepo: mockFeedbackRepo,
      );
    });

    group('getExamples', () {
      test('returns empty when no similar invocations found', () async {
        mockSearch.searchResults = [];

        final result = await voiceTraits.getExamples(
          query: 'Set a timer',
          eventId: 'evt_1',
        );

        expect(result.positive, isEmpty);
        expect(result.negative, isEmpty);
        expect(result.hasExamples, isFalse);
      });

      test('returns empty when similar invocations have no feedback', () async {
        final inv = createLLMInvocation(
          uuid: 'inv_1',
          query: 'Set timer for 5 minutes',
          response: 'Timer set!',
        );
        mockInvRepo.addInvocation(inv);

        mockSearch.searchResults = [
          SemanticSearchResult(
            chunk: createChunk(id: 'chunk_1', sourceEntityId: 'inv_1'),
            sourceEntity: inv,
            similarity: 0.8,
          ),
        ];

        final result = await voiceTraits.getExamples(
          query: 'Set a timer',
          eventId: 'evt_1',
        );

        expect(result.positive, isEmpty);
        expect(result.negative, isEmpty);
      });

      test('returns positive examples for confirmed invocations', () async {
        final inv = createLLMInvocation(
          uuid: 'inv_1',
          query: 'Set timer for 5 minutes',
          response: 'Timer set for 5 minutes!',
        );
        mockInvRepo.addInvocation(inv);

        mockFeedbackRepo.addFeedback(Feedback(
          invocationId: 'inv_1',
          componentType: 'llm',
          action: FeedbackAction.confirm,
        ));

        mockSearch.searchResults = [
          SemanticSearchResult(
            chunk: createChunk(id: 'chunk_1', sourceEntityId: 'inv_1'),
            sourceEntity: inv,
            similarity: 0.8,
          ),
        ];

        final result = await voiceTraits.getExamples(
          query: 'Set a timer',
          eventId: 'evt_1',
        );

        expect(result.positive.length, equals(1));
        expect(result.negative, isEmpty);
        expect(result.positive.first.query, equals('Set timer for 5 minutes'));
        expect(result.positive.first.response, equals('Timer set for 5 minutes!'));
        expect(result.positive.first.isPositive, isTrue);
      });

      test('returns negative examples for denied invocations', () async {
        final inv = createLLMInvocation(
          uuid: 'inv_1',
          query: 'Set timer for 5 minutes',
          response: 'I cannot do that.',
        );
        mockInvRepo.addInvocation(inv);

        mockFeedbackRepo.addFeedback(Feedback(
          invocationId: 'inv_1',
          componentType: 'llm',
          action: FeedbackAction.deny,
        ));

        mockSearch.searchResults = [
          SemanticSearchResult(
            chunk: createChunk(id: 'chunk_1', sourceEntityId: 'inv_1'),
            sourceEntity: inv,
            similarity: 0.8,
          ),
        ];

        final result = await voiceTraits.getExamples(
          query: 'Set a timer',
          eventId: 'evt_1',
        );

        expect(result.positive, isEmpty);
        expect(result.negative.length, equals(1));
        expect(result.negative.first.isNegative, isTrue);
      });

      test('separates positive and negative examples correctly', () async {
        final inv1 = createLLMInvocation(
          uuid: 'inv_1',
          query: 'Set timer for 5 minutes',
          response: 'Timer set for 5 minutes!',
        );
        final inv2 = createLLMInvocation(
          uuid: 'inv_2',
          query: 'Set timer for 10 minutes',
          response: 'Sorry, I cannot help.',
        );
        mockInvRepo.addInvocation(inv1);
        mockInvRepo.addInvocation(inv2);

        mockFeedbackRepo.addFeedback(Feedback(
          invocationId: 'inv_1',
          componentType: 'llm',
          action: FeedbackAction.confirm,
        ));
        mockFeedbackRepo.addFeedback(Feedback(
          invocationId: 'inv_2',
          componentType: 'llm',
          action: FeedbackAction.deny,
        ));

        mockSearch.searchResults = [
          SemanticSearchResult(
            chunk: createChunk(id: 'chunk_1', sourceEntityId: 'inv_1'),
            sourceEntity: inv1,
            similarity: 0.9,
          ),
          SemanticSearchResult(
            chunk: createChunk(id: 'chunk_2', sourceEntityId: 'inv_2'),
            sourceEntity: inv2,
            similarity: 0.8,
          ),
        ];

        final result = await voiceTraits.getExamples(
          query: 'Set a timer',
          eventId: 'evt_1',
        );

        expect(result.positive.length, equals(1));
        expect(result.negative.length, equals(1));
        expect(result.positive.first.invocationId, equals('inv_1'));
        expect(result.negative.first.invocationId, equals('inv_2'));
      });

      test('respects config limits for examples', () async {
        // Create 5 positive invocations
        for (int i = 1; i <= 5; i++) {
          final inv = createLLMInvocation(
            uuid: 'inv_$i',
            query: 'Query $i',
            response: 'Response $i',
          );
          mockInvRepo.addInvocation(inv);
          mockFeedbackRepo.addFeedback(Feedback(
            invocationId: 'inv_$i',
            componentType: 'llm',
            action: FeedbackAction.confirm,
          ));
          mockSearch.searchResults.add(SemanticSearchResult(
            chunk: createChunk(id: 'chunk_$i', sourceEntityId: 'inv_$i'),
            sourceEntity: inv,
            similarity: 0.9 - (i * 0.01),
          ));
        }

        // Default config: maxPositiveExamples = 2
        final result = await voiceTraits.getExamples(
          query: 'Test query',
          eventId: 'evt_1',
        );

        expect(result.positive.length, equals(2));
      });

      test('filters out low similarity results', () async {
        final inv = createLLMInvocation(
          uuid: 'inv_1',
          query: 'Set timer',
          response: 'Timer set!',
        );
        mockInvRepo.addInvocation(inv);
        mockFeedbackRepo.addFeedback(Feedback(
          invocationId: 'inv_1',
          componentType: 'llm',
          action: FeedbackAction.confirm,
        ));

        mockSearch.searchResults = [
          SemanticSearchResult(
            chunk: createChunk(id: 'chunk_1', sourceEntityId: 'inv_1'),
            sourceEntity: inv,
            similarity: 0.1, // Below default threshold of 0.3
          ),
        ];

        final result = await voiceTraits.getExamples(
          query: 'Test query',
          eventId: 'evt_1',
        );

        expect(result.positive, isEmpty);
        expect(result.negative, isEmpty);
      });

      test('ignores non-LLM feedback', () async {
        final inv = createLLMInvocation(
          uuid: 'inv_1',
          query: 'Set timer',
          response: 'Timer set!',
        );
        mockInvRepo.addInvocation(inv);

        // Add STT feedback (should be ignored)
        mockFeedbackRepo.addFeedback(Feedback(
          invocationId: 'inv_1',
          componentType: 'stt',
          action: FeedbackAction.confirm,
        ));

        mockSearch.searchResults = [
          SemanticSearchResult(
            chunk: createChunk(id: 'chunk_1', sourceEntityId: 'inv_1'),
            sourceEntity: inv,
            similarity: 0.8,
          ),
        ];

        final result = await voiceTraits.getExamples(
          query: 'Test query',
          eventId: 'evt_1',
        );

        expect(result.positive, isEmpty);
        expect(result.negative, isEmpty);
      });

      test('ignores feedback with ignore action', () async {
        final inv = createLLMInvocation(
          uuid: 'inv_1',
          query: 'Set timer',
          response: 'Timer set!',
        );
        mockInvRepo.addInvocation(inv);

        mockFeedbackRepo.addFeedback(Feedback(
          invocationId: 'inv_1',
          componentType: 'llm',
          action: FeedbackAction.ignore,
        ));

        mockSearch.searchResults = [
          SemanticSearchResult(
            chunk: createChunk(id: 'chunk_1', sourceEntityId: 'inv_1'),
            sourceEntity: inv,
            similarity: 0.8,
          ),
        ];

        final result = await voiceTraits.getExamples(
          query: 'Test query',
          eventId: 'evt_1',
        );

        expect(result.positive, isEmpty);
        expect(result.negative, isEmpty);
      });

      test('degrades gracefully when search fails', () async {
        mockSearch.shouldThrow = true;

        final result = await voiceTraits.getExamples(
          query: 'Test query',
          eventId: 'evt_1',
        );

        expect(result.positive, isEmpty);
        expect(result.negative, isEmpty);
        expect(result.hasExamples, isFalse);
      });
    });

    group('formatPrompt', () {
      test('returns empty string for empty examples', () {
        final examples = ContrastiveExamples.empty();
        final prompt = voiceTraits.formatPrompt(examples);
        expect(prompt, isEmpty);
      });

      test('formats positive examples correctly', () {
        final examples = ContrastiveExamples(
          positive: [
            FeedbackExample(
              query: 'Set a timer for 5 minutes',
              response: 'Timer set for 5 minutes!',
              feedbackAction: FeedbackAction.confirm,
              similarity: 0.9,
              invocationId: 'inv_1',
              timestamp: DateTime.now(),
            ),
          ],
          negative: [],
        );

        final prompt = voiceTraits.formatPrompt(examples);

        expect(prompt, contains('## Response Style'));
        expect(prompt, contains('Examples of good responses'));
        expect(prompt, contains('Set a timer for 5 minutes'));
        expect(prompt, contains('Timer set for 5 minutes!'));
        expect(prompt, isNot(contains('What to avoid')));
      });

      test('formats negative examples correctly', () {
        final examples = ContrastiveExamples(
          positive: [],
          negative: [
            FeedbackExample(
              query: 'Set a timer',
              response: 'I cannot do that.',
              feedbackAction: FeedbackAction.deny,
              similarity: 0.8,
              invocationId: 'inv_1',
              timestamp: DateTime.now(),
            ),
          ],
        );

        final prompt = voiceTraits.formatPrompt(examples);

        expect(prompt, contains('## Response Style'));
        expect(prompt, contains('What to avoid'));
        expect(prompt, contains('Set a timer'));
        expect(prompt, contains('I cannot do that.'));
      });

      test('formats both positive and negative examples', () {
        final examples = ContrastiveExamples(
          positive: [
            FeedbackExample(
              query: 'Good query',
              response: 'Good response',
              feedbackAction: FeedbackAction.confirm,
              similarity: 0.9,
              invocationId: 'inv_1',
              timestamp: DateTime.now(),
            ),
          ],
          negative: [
            FeedbackExample(
              query: 'Bad query',
              response: 'Bad response',
              feedbackAction: FeedbackAction.deny,
              similarity: 0.8,
              invocationId: 'inv_2',
              timestamp: DateTime.now(),
            ),
          ],
        );

        final prompt = voiceTraits.formatPrompt(examples);

        expect(prompt, contains('Examples of good responses'));
        expect(prompt, contains('Good query'));
        expect(prompt, contains('Good response'));
        expect(prompt, contains('What to avoid'));
        expect(prompt, contains('Bad query'));
        expect(prompt, contains('Bad response'));
      });
    });

    group('FeedbackExample', () {
      test('isPositive returns true for confirm action', () {
        final example = FeedbackExample(
          query: 'Q',
          response: 'R',
          feedbackAction: FeedbackAction.confirm,
          similarity: 0.9,
          invocationId: 'inv',
          timestamp: DateTime.now(),
        );

        expect(example.isPositive, isTrue);
        expect(example.isNegative, isFalse);
      });

      test('isNegative returns true for deny action', () {
        final example = FeedbackExample(
          query: 'Q',
          response: 'R',
          feedbackAction: FeedbackAction.deny,
          similarity: 0.9,
          invocationId: 'inv',
          timestamp: DateTime.now(),
        );

        expect(example.isPositive, isFalse);
        expect(example.isNegative, isTrue);
      });
    });

    group('ContrastiveExamples', () {
      test('empty factory creates empty lists', () {
        final examples = ContrastiveExamples.empty();
        expect(examples.positive, isEmpty);
        expect(examples.negative, isEmpty);
        expect(examples.hasExamples, isFalse);
        expect(examples.totalCount, equals(0));
      });

      test('hasExamples returns true when positive present', () {
        final examples = ContrastiveExamples(
          positive: [
            FeedbackExample(
              query: 'Q',
              response: 'R',
              feedbackAction: FeedbackAction.confirm,
              similarity: 0.9,
              invocationId: 'inv',
              timestamp: DateTime.now(),
            ),
          ],
          negative: [],
        );

        expect(examples.hasExamples, isTrue);
        expect(examples.totalCount, equals(1));
      });

      test('hasExamples returns true when negative present', () {
        final examples = ContrastiveExamples(
          positive: [],
          negative: [
            FeedbackExample(
              query: 'Q',
              response: 'R',
              feedbackAction: FeedbackAction.deny,
              similarity: 0.9,
              invocationId: 'inv',
              timestamp: DateTime.now(),
            ),
          ],
        );

        expect(examples.hasExamples, isTrue);
        expect(examples.totalCount, equals(1));
      });
    });

    group('VoiceTraitsConfig', () {
      test('defaults have reasonable values', () {
        const config = VoiceTraitsConfig.defaults;
        expect(config.maxPositiveExamples, equals(2));
        expect(config.maxNegativeExamples, equals(1));
        expect(config.minSimilarity, equals(0.3));
        expect(config.maxAge, isNull);
      });

      test('custom config overrides defaults', () {
        const config = VoiceTraitsConfig(
          maxPositiveExamples: 5,
          maxNegativeExamples: 3,
          minSimilarity: 0.5,
          maxAge: Duration(days: 7),
        );

        expect(config.maxPositiveExamples, equals(5));
        expect(config.maxNegativeExamples, equals(3));
        expect(config.minSimilarity, equals(0.5));
        expect(config.maxAge, equals(const Duration(days: 7)));
      });
    });
  });
}
