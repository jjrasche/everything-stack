import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/hnsw_index.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search.dart';
import 'package:everything_stack_template/patterns/semantic_indexable.dart';

void main() {
  group('Chunk model contract', () {
    test('Chunk has required fields', () {
      final chunk = Chunk(
        id: 'chunk-uuid-123',
        sourceEntityId: 'note-uuid-456',
        sourceEntityType: 'Note',
        startToken: 0,
        endToken: 128,
        config: 'parent',
      );

      expect(chunk.id, isNotEmpty);
      expect(chunk.sourceEntityId, isNotEmpty);
      expect(chunk.sourceEntityType, isNotEmpty);
      expect(chunk.startToken, 0);
      expect(chunk.endToken, 128);
      expect(chunk.config, 'parent');
    });

    test('Chunk config can be parent or child', () {
      final parentChunk = Chunk(
        id: 'c1',
        sourceEntityId: 'e1',
        sourceEntityType: 'Note',
        startToken: 0,
        endToken: 200,
        config: 'parent',
      );

      final childChunk = Chunk(
        id: 'c2',
        sourceEntityId: 'e1',
        sourceEntityType: 'Note',
        startToken: 0,
        endToken: 25,
        config: 'child',
      );

      expect(parentChunk.config, 'parent');
      expect(childChunk.config, 'child');
    });

    test('Chunk has valid token range', () {
      final chunk = Chunk(
        id: 'c1',
        sourceEntityId: 'e1',
        sourceEntityType: 'Note',
        startToken: 10,
        endToken: 50,
        config: 'parent',
      );

      expect(chunk.startToken, lessThan(chunk.endToken));
      expect(chunk.tokenCount, 40);
    });

    test('Chunk validates token range', () {
      expect(
        () => Chunk(
          id: 'c1',
          sourceEntityId: 'e1',
          sourceEntityType: 'Note',
          startToken: 50,
          endToken: 50,
          config: 'parent',
        ),
        throwsArgumentError,
      );
    });

    test('Chunk validates config values', () {
      expect(
        () => Chunk(
          id: 'c1',
          sourceEntityId: 'e1',
          sourceEntityType: 'Note',
          startToken: 0,
          endToken: 50,
          config: 'invalid',
        ),
        throwsArgumentError,
      );
    });

    test('Chunk equality compares all fields', () {
      final chunk1 = Chunk(
        id: 'c1',
        sourceEntityId: 'e1',
        sourceEntityType: 'Note',
        startToken: 0,
        endToken: 50,
        config: 'parent',
      );

      final chunk2 = Chunk(
        id: 'c1',
        sourceEntityId: 'e1',
        sourceEntityType: 'Note',
        startToken: 0,
        endToken: 50,
        config: 'parent',
      );

      final chunk3 = Chunk(
        id: 'c2',
        sourceEntityId: 'e1',
        sourceEntityType: 'Note',
        startToken: 0,
        endToken: 50,
        config: 'parent',
      );

      expect(chunk1, equals(chunk2));
      expect(chunk1, isNot(equals(chunk3)));
    });
  });

  group('SemanticSearchResult contract', () {
    test('SemanticSearchResult contains chunk and similarity', () {
      final chunk = Chunk(
        id: 'chunk-1',
        sourceEntityId: 'note-1',
        sourceEntityType: 'Note',
        startToken: 5,
        endToken: 55,
        config: 'child',
      );

      final result = SemanticSearchResult(
        chunk: chunk,
        sourceEntity: null,
        similarity: 0.85,
      );

      expect(result.chunk, isNotNull);
      expect(result.chunk.id, 'chunk-1');
      expect(result.similarity, 0.85);
      expect(result.sourceEntity, isNull);
    });

    test('SemanticSearchResult similarity is between 0 and 1', () {
      final validSimilarities = [0.0, 0.5, 1.0, 0.123, 0.999];

      for (final sim in validSimilarities) {
        final result = SemanticSearchResult(
          chunk: Chunk(
            id: 'test',
            sourceEntityId: 'test',
            sourceEntityType: 'Note',
            startToken: 0,
            endToken: 10,
            config: 'parent',
          ),
          sourceEntity: null,
          similarity: sim,
        );

        expect(result.similarity, greaterThanOrEqualTo(0.0));
        expect(result.similarity, lessThanOrEqualTo(1.0));
      }
    });

    test('SemanticSearchResult rejects invalid similarity', () {
      expect(
        () => SemanticSearchResult(
          chunk: Chunk(
            id: 'test',
            sourceEntityId: 'test',
            sourceEntityType: 'Note',
            startToken: 0,
            endToken: 10,
            config: 'parent',
          ),
          sourceEntity: null,
          similarity: 1.5,
        ),
        throwsArgumentError,
      );

      expect(
        () => SemanticSearchResult(
          chunk: Chunk(
            id: 'test',
            sourceEntityId: 'test',
            sourceEntityType: 'Note',
            startToken: 0,
            endToken: 10,
            config: 'parent',
          ),
          sourceEntity: null,
          similarity: -0.1,
        ),
        throwsArgumentError,
      );
    });

    test('SemanticSearchResult provides similarity percentage', () {
      final result = SemanticSearchResult(
        chunk: Chunk(
          id: 'test',
          sourceEntityId: 'test',
          sourceEntityType: 'Note',
          startToken: 0,
          endToken: 10,
          config: 'parent',
        ),
        sourceEntity: null,
        similarity: 0.85,
      );

      expect(result.similarityPercent, '85.0%');
    });

    test('SemanticSearchResult equality compares chunk and similarity', () {
      final chunk = Chunk(
        id: 'c1',
        sourceEntityId: 'e1',
        sourceEntityType: 'Note',
        startToken: 0,
        endToken: 10,
        config: 'parent',
      );

      final result1 = SemanticSearchResult(
        chunk: chunk,
        sourceEntity: null,
        similarity: 0.85,
      );

      final result2 = SemanticSearchResult(
        chunk: chunk,
        sourceEntity: null,
        similarity: 0.85,
      );

      final result3 = SemanticSearchResult(
        chunk: chunk,
        sourceEntity: null,
        similarity: 0.80,
      );

      expect(result1, equals(result2));
      expect(result1, isNot(equals(result3)));
    });
  });

  group('SemanticSearchService contract', () {
    late MockEmbeddingService embeddingService;
    late HnswIndex index;
    late SemanticSearchService searchService;

    setUp(() {
      embeddingService = MockEmbeddingService();
      index = HnswIndex(dimensions: 384);
      searchService = SemanticSearchService(
        index: index,
        embeddingService: embeddingService,
        entityLoader: MockEntityLoader(),
      );
    });

    test('returns empty results when index is empty', () async {
      final results = await searchService.search('machine learning');
      expect(results, isEmpty);
    });

    test('search generates embedding for query', () async {
      await searchService.search('test query');
      expect(embeddingService.lastGeneratedText, 'test query');
    });

    test('search respects limit parameter', () async {
      // Index is empty, so just verify parameter is accepted
      final results = await searchService.search(
        'query',
        limit: 5,
      );
      expect(results, isEmpty);
    });

    test('search filters by entity type when specified', () async {
      // With empty index, just verify entityTypes parameter is accepted
      final results = await searchService.search(
        'query',
        entityTypes: ['Note', 'Article'],
      );
      expect(results, isEmpty);
    });
  });

  group('SemanticIndexable mixin contract', () {
    test('Entity implements toChunkableInput', () {
      final note = TestNote(
        title: 'Title',
        content: 'Content',
      );

      expect(note, isA<SemanticIndexable>());
      expect(note.toChunkableInput(), isNotEmpty);
      expect(note.toChunkableInput(), contains('Title'));
      expect(note.toChunkableInput(), contains('Content'));
    });

    test('Entity implements getChunkingConfig', () {
      final note = TestNote(
        title: 'Title',
        content: 'Content',
      );

      final config = note.getChunkingConfig();
      expect(config, isNotEmpty);
      expect(['parent', 'child'], contains(config));
    });

    test('Entity provides needsReChunking check', () {
      final note = TestNote(
        title: 'Title',
        content: 'Content',
      );

      expect(note.needsReChunking, isTrue);
    });
  });
}

// ============ Test Doubles ============

class MockEmbeddingService extends EmbeddingService {
  final Map<String, List<double>> _cache = {};
  String? lastGeneratedText;

  @override
  Future<List<double>> generate(String text) async {
    lastGeneratedText = text;
    return mockEmbedding(text);
  }

  List<double> mockEmbedding(String text) {
    if (_cache.containsKey(text)) {
      return _cache[text]!;
    }

    // Generate consistent mock embedding based on text
    final embedding = List<double>.generate(
      384,
      (i) {
        final hash = text.hashCode ^ i;
        return ((hash.abs() % 1000) / 1000.0);
      },
    );

    _cache[text] = embedding;
    return embedding;
  }

  @override
  Future<List<List<double>>> generateBatch(List<String> texts) async {
    return texts.map((t) => mockEmbedding(t)).toList();
  }

  double cosineSimilarity(List<double> a, List<double> b) {
    return EmbeddingService.cosineSimilarity(a, b);
  }
}

class MockEntityLoader extends EntityLoader {
  // Inherits default implementation that returns null
}

// ============ Test Entity ============

class TestNote with SemanticIndexable {
  String title;
  String content;
  String chunkingStrategy;

  TestNote({
    required this.title,
    required this.content,
    this.chunkingStrategy = 'parent',
  });

  @override
  String toChunkableInput() {
    return '$title\n$content';
  }

  @override
  String getChunkingConfig() {
    return chunkingStrategy;
  }
}
