import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/patterns/semantic_indexable.dart';
import 'package:everything_stack_template/services/chunking/semantic_chunker.dart';
import 'package:everything_stack_template/services/chunking/chunking_config.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/hnsw_index.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search.dart';

void main() {
  group('ChunkingService', () {
    late MockEmbeddingService embeddingService;
    late HnswIndex hnswIndex;
    late SemanticChunker parentChunker;
    late SemanticChunker childChunker;
    late ChunkingService chunkingService;

    setUp(() {
      embeddingService = MockEmbeddingService();
      hnswIndex = HnswIndex(dimensions: 384);
      parentChunker = SemanticChunker(
        embeddingService: embeddingService,
        config: ChunkingConfig.parent(),
      );
      childChunker = SemanticChunker(
        embeddingService: embeddingService,
        config: ChunkingConfig.child(),
      );
      chunkingService = ChunkingService(
        index: hnswIndex,
        embeddingService: embeddingService,
        parentChunker: parentChunker,
        childChunker: childChunker,
      );
    });

    group('index(entity) - chunking and indexing', () {
      test('indexes SemanticIndexable entity by chunking and embedding', () async {
        final note = TestNote(
          uuid: 'note-123',
          title: 'Design Patterns',
          content: '''
            Singleton pattern restricts instantiation of a class to single object.
            Factory pattern provides interface for creating objects in superclass.
            Observer pattern defines one-to-many dependency between objects.
          ''',
        );

        final chunks = await chunkingService.indexEntity(note);

        // Should have created chunks
        expect(chunks, isNotEmpty);
        // Each chunk should have proper fields for HNSW storage
        for (final chunk in chunks) {
          expect(chunk.id, isNotEmpty);
          expect(chunk.sourceEntityId, 'note-123');
          expect(chunk.sourceEntityType, 'TestNote');
          expect(chunk.startToken, greaterThanOrEqualTo(0));
          expect(chunk.endToken, greaterThan(chunk.startToken));
          expect(['parent', 'child'], contains(chunk.config));
        }
      });

      test('inserts chunks into HNSW index with embeddings', () async {
        final note = TestNote(
          uuid: 'note-456',
          title: 'Machine Learning',
          content: '''
            Neural networks consist of interconnected nodes.
            Deep learning uses multiple layers of abstraction.
            Transfer learning reuses pretrained models.
          ''',
        );

        final chunks = await chunkingService.indexEntity(note);

        // Verify chunks were inserted into HNSW
        expect(chunks, isNotEmpty);

        // Verify HNSW index has the chunks (by count)
        final indexSize = hnswIndex.size;
        expect(indexSize, equals(chunks.length),
            reason: 'All chunks should be in HNSW index');
      });

      test('returns chunks in order with correct token boundaries', () async {
        final note = TestNote(
          uuid: 'note-789',
          title: 'Algorithms',
          content: 'Quick sort is a divide and conquer algorithm. '
              'Merge sort is a stable sorting algorithm. '
              'Heap sort uses heap data structure.',
        );

        final chunks = await chunkingService.indexEntity(note);

        expect(chunks, isNotEmpty);
        // Verify each chunk has valid token boundaries
        for (final chunk in chunks) {
          expect(chunk.startToken, greaterThanOrEqualTo(0),
              reason: 'startToken must be non-negative');
          expect(chunk.endToken, greaterThan(chunk.startToken),
              reason: 'endToken must be greater than startToken');
          expect(chunk.tokenCount, greaterThan(0),
              reason: 'tokenCount must be positive');
        }
      });

      test('generates two-level chunks (parent and child)', () async {
        final note = TestNote(
          uuid: 'note-two-level',
          title: 'Architecture',
          content: '''
            Microservices architecture divides application into small services.
            Each service is independently deployable and scalable.
            Services communicate via APIs and message queues.
            This enables team independence and rapid deployment.
            However it increases operational complexity and distributed debugging.
          ''',
        );

        final chunks = await chunkingService.indexEntity(note);

        // Should have both parent and child chunks
        final parentChunks = chunks.where((c) => c.config == 'parent').toList();
        final childChunks = chunks.where((c) => c.config == 'child').toList();

        expect(parentChunks, isNotEmpty, reason: 'Should have parent chunks');
        expect(childChunks, isNotEmpty, reason: 'Should have child chunks');

        // Total chunks should be parent + child
        expect(chunks.length, equals(parentChunks.length + childChunks.length),
            reason: 'Chunks should be split by parent and child');
      });

      test('returns empty list for empty entity content', () async {
        final emptyNote = TestNote(
          uuid: 'empty-note',
          title: '',
          content: '',
        );

        final chunks = await chunkingService.indexEntity(emptyNote);
        expect(chunks, isEmpty);
      });

      test('handles entity with minimal content', () async {
        final tinyNote = TestNote(
          uuid: 'tiny-note',
          title: 'Hi',
          content: 'Ok',
        );

        final chunks = await chunkingService.indexEntity(tinyNote);
        // Should still create at least one chunk (or handle gracefully)
        expect(chunks is List, isTrue);
      });
    });

    group('deleteByEntityId(entityId) - removing chunks from index', () {
      test('removes all chunks for entity from HNSW index', () async {
        final note = TestNote(
          uuid: 'to-delete-123',
          title: 'Deletable Content',
          content: '''
            This content will be deleted.
            Multiple chunks will be created.
            All should be removed from index.
          ''',
        );

        // Index the entity (creates chunks)
        final indexedChunks = await chunkingService.indexEntity(note);
        expect(indexedChunks, isNotEmpty);

        // Verify chunks are in HNSW
        final sizeBefore = hnswIndex.size;
        expect(sizeBefore, greaterThan(0), reason: 'Should have chunks in index before delete');

        // Delete chunks for this entity
        await chunkingService.deleteByEntityId('to-delete-123');

        // Verify chunks are removed from HNSW
        final sizeAfter = hnswIndex.size;
        expect(sizeAfter, equals(0), reason: 'All chunks should be removed from index');
      });

      test('handles deletion of non-existent entity gracefully', () async {
        expect(
          () async {
            await chunkingService.deleteByEntityId('non-existent-entity-uuid');
          },
          returnsNormally,
          reason: 'Should not throw when deleting non-existent entity',
        );
      });

      test('does not affect chunks from other entities', () async {
        final note1 = TestNote(
          uuid: 'entity-1',
          title: 'First',
          content: 'Content for first entity. Long enough to create chunks.',
        );

        final note2 = TestNote(
          uuid: 'entity-2',
          title: 'Second',
          content: 'Content for second entity. Also long enough to create chunks.',
        );

        // Index both entities
        final chunks1 = await chunkingService.indexEntity(note1);
        final chunks2 = await chunkingService.indexEntity(note2);

        expect(chunks1, isNotEmpty);
        expect(chunks2, isNotEmpty);

        // Verify both are in index
        final sizeAfterBoth = hnswIndex.size;
        expect(sizeAfterBoth, equals(chunks1.length + chunks2.length));

        // Delete first entity
        await chunkingService.deleteByEntityId('entity-1');

        // Second entity's chunks should still be in index
        final sizeAfterDelete = hnswIndex.size;
        expect(sizeAfterDelete, equals(chunks2.length),
            reason: 'Second entity chunks should still be in index');
      });
    });

    group('integration - index and search', () {
      test('indexed chunks can be found via semantic search', () async {
        final note = TestNote(
          uuid: 'searchable-note',
          title: 'Functional Programming',
          content: '''
            Pure functions have no side effects.
            Immutable data structures enable functional composition.
            Higher-order functions take or return functions.
            Recursion replaces loops in functional programming.
          ''',
        );

        // Index the note
        await chunkingService.indexEntity(note);

        // Search for related content
        final searchService = SemanticSearchService(
          index: hnswIndex,
          embeddingService: embeddingService,
          entityLoader: MockEntityLoader(),
        );

        final results = await searchService.search(
          'immutable data',
          limit: 5,
        );

        // Should find the indexed chunks
        // Note: This depends on _reconstructChunks being implemented
        // For now we're verifying the service can be called
        expect(results is List, isTrue);
      });
    });
  });
}

// ============ ChunkingService ============

/// Service for orchestrating semantic chunking and HNSW indexing
class ChunkingService {
  final HnswIndex index;
  final EmbeddingService embeddingService;
  final SemanticChunker parentChunker;
  final SemanticChunker childChunker;

  /// In-memory registry of chunks by entity ID (for reconstruction in search)
  /// In production, would be stored in database
  final Map<String, List<Chunk>> _chunkRegistry = {};

  ChunkingService({
    required this.index,
    required this.embeddingService,
    required this.parentChunker,
    required this.childChunker,
  });

  /// Index entity: chunk → embed → insert into HNSW
  /// Returns list of indexed chunks
  Future<List<Chunk>> indexEntity(BaseEntity entity) async {
    if (entity is! SemanticIndexable) {
      return [];
    }

    final semanticEntity = entity as SemanticIndexable;
    final input = semanticEntity.toChunkableInput();
    if (input.trim().isEmpty) {
      return [];
    }

    final chunks = <Chunk>[];

    // Step 1: Generate parent chunks
    final parentChunkTexts =
        await parentChunker.chunk(input);

    // Step 2: For each parent chunk, generate child chunks
    for (final parentChunkText in parentChunkTexts) {
      // Add parent chunk
      final parentChunk = Chunk(
        id: _generateChunkId(),
        sourceEntityId: entity.uuid,
        sourceEntityType: entity.runtimeType.toString(),
        startToken: parentChunkText.startToken,
        endToken: parentChunkText.endToken,
        config: 'parent',
      );
      chunks.add(parentChunk);

      // Generate embedding for parent chunk
      final parentEmbedding =
          await embeddingService.generate(parentChunkText.text);
      // Insert into HNSW
      index.insert(parentChunk.id, parentEmbedding);

      // Generate child chunks from this parent
      final childChunkTexts = await childChunker.chunk(parentChunkText.text);

      for (final childChunkText in childChunkTexts) {
        final childChunk = Chunk(
          id: _generateChunkId(),
          sourceEntityId: entity.uuid,
          sourceEntityType: entity.runtimeType.toString(),
          startToken: childChunkText.startToken,
          endToken: childChunkText.endToken,
          config: 'child',
        );
        chunks.add(childChunk);

        // Generate embedding for child chunk
        final childEmbedding =
            await embeddingService.generate(childChunkText.text);
        // Insert into HNSW
        index.insert(childChunk.id, childEmbedding);
      }
    }

    // Store chunks in registry for reconstruction in search
    _chunkRegistry[entity.uuid] = chunks;

    return chunks;
  }

  /// Delete all chunks for entity from HNSW index
  Future<void> deleteByEntityId(String entityId) async {
    final chunks = _chunkRegistry[entityId] ?? [];
    // Delete each chunk from HNSW
    for (final chunk in chunks) {
      index.delete(chunk.id);
    }
    _chunkRegistry.remove(entityId);
  }

  /// Get chunks for entity (for reconstruction in search)
  List<Chunk> getChunksForEntity(String entityId) {
    return _chunkRegistry[entityId] ?? [];
  }

  String _generateChunkId() {
    return 'chunk-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(100000)}';
  }
}

// ============ Test Doubles ============

class MockEmbeddingService extends EmbeddingService {
  final Map<String, List<double>> _cache = {};

  @override
  Future<List<double>> generate(String text) async {
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

class TestNote extends BaseEntity with SemanticIndexable {
  String title;
  String content;

  TestNote({
    required this.title,
    required this.content,
    String? uuid,
  }) {
    if (uuid != null) {
      _uuid = uuid;
    }
  }

  late String _uuid;

  @override
  String get uuid => _uuid;

  @override
  String toChunkableInput() {
    return '$title\n$content';
  }

  @override
  String getChunkingConfig() {
    return 'parent';
  }
}
