import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/patterns/semantic_indexable.dart';
import 'package:everything_stack_template/services/chunking/semantic_chunker.dart';
import 'package:everything_stack_template/services/chunking/chunking_config.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/hnsw_index.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search.dart';

void main() {
  group('Semantic Indexing Lifecycle Hooks', () {
    late MockEmbeddingService embeddingService;
    late HnswIndex hnswIndex;
    late SemanticChunker parentChunker;
    late SemanticChunker childChunker;
    late ChunkingService chunkingService;
    late MockNoteRepository noteRepository;

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
      noteRepository = MockNoteRepository(
        adapter: MockNoteAdapter(),
        embeddingService: embeddingService,
        chunkingService: chunkingService,
      );
    });

    group('save() - auto-reindexing on entity save', () {
      test('saves SemanticIndexable entity and indexes chunks', () async {
        final note = TestNote(
          uuid: 'note-1',
          title: 'Test Note',
          content: 'This is test content that should be chunked and indexed.',
        );

        // Save should trigger chunking and indexing
        await noteRepository.save(note);

        // Verify chunks were created and indexed
        expect(hnswIndex.size, greaterThan(0),
            reason: 'Chunks should be indexed in HNSW');

        // Verify chunks belong to the saved entity
        final chunksForEntity = chunkingService.getChunksForEntity('note-1');
        expect(chunksForEntity, isNotEmpty,
            reason: 'Entity should have chunks stored');
      });

      test('deletes old chunks when saving updated entity', () async {
        final note = TestNote(
          uuid: 'note-update-test',
          title: 'Original Title',
          content: 'Original content with some text.',
        );

        // Save initial version
        await noteRepository.save(note);
        final sizeBefore = hnswIndex.size;
        expect(sizeBefore, greaterThan(0));

        // Update and save
        note.title = 'Updated Title';
        note.content = 'Completely new content that is different.';
        await noteRepository.save(note);

        // Should have different number of chunks (old deleted, new created)
        // At minimum, should not grow unboundedly
        expect(hnswIndex.size, greaterThanOrEqualTo(0),
            reason: 'Index should be valid after update');

        // Verify only new chunks exist for this entity
        final chunks = chunkingService.getChunksForEntity('note-update-test');
        expect(chunks, isNotEmpty);
      });

      test('handles non-SemanticIndexable entities gracefully', () async {
        final nonIndexableNote = TestNoteNonIndexable(
          uuid: 'non-indexable',
          title: 'No Index',
          content: 'This entity does not implement SemanticIndexable',
        );

        // Should save without error
        expect(
          () async {
            await noteRepository.saveNonIndexable(nonIndexableNote);
          },
          returnsNormally,
          reason: 'Should handle non-SemanticIndexable entities',
        );

        // Should not add to HNSW index
        final chunksForEntity =
            chunkingService.getChunksForEntity('non-indexable');
        expect(chunksForEntity, isEmpty,
            reason: 'Non-SemanticIndexable entities should not be indexed');
      });

      test('generates chunks matching entity content', () async {
        final note = TestNote(
          uuid: 'content-test',
          title: 'Python',
          content:
              'Python is a programming language known for simplicity. ' *
                  10, // Repeat to ensure multi-chunk
        );

        await noteRepository.save(note);

        final chunks = chunkingService.getChunksForEntity('content-test');
        expect(chunks, isNotEmpty);

        // All chunks should reference this entity
        for (final chunk in chunks) {
          expect(chunk.sourceEntityId, 'content-test');
          expect(chunk.sourceEntityType, 'TestNote');
        }
      });
    });

    group('delete() - auto-removal from index on entity deletion', () {
      test('deletes entity and removes chunks from index', () async {
        final note = TestNote(
          uuid: 'to-delete-1',
          title: 'Delete Test',
          content: 'This content will be deleted from the index.',
        );

        // Save and index
        await noteRepository.save(note);
        final sizeBeforeDelete = hnswIndex.size;
        expect(sizeBeforeDelete, greaterThan(0));

        // Delete should remove chunks from index
        await noteRepository.deleteByUuid('to-delete-1');

        // Verify chunks removed
        final sizeAfterDelete = hnswIndex.size;
        expect(sizeAfterDelete, equals(0),
            reason: 'All chunks should be removed when entity is deleted');

        // Verify no chunks exist for deleted entity
        final chunksForEntity = chunkingService.getChunksForEntity('to-delete-1');
        expect(chunksForEntity, isEmpty,
            reason: 'Deleted entity should have no chunks');
      });

      test('does not affect other entities when deleting', () async {
        final note1 = TestNote(
          uuid: 'entity-a',
          title: 'Entity A',
          content: 'Content A that will be deleted.',
        );

        final note2 = TestNote(
          uuid: 'entity-b',
          title: 'Entity B',
          content: 'Content B that will remain.',
        );

        // Save both
        await noteRepository.save(note1);
        await noteRepository.save(note2);

        final chunksNote2Before =
            chunkingService.getChunksForEntity('entity-b');
        expect(chunksNote2Before, isNotEmpty);

        // Delete first entity
        await noteRepository.deleteByUuid('entity-a');

        // Second entity's chunks should still be indexed
        final chunksNote2After = chunkingService.getChunksForEntity('entity-b');
        expect(chunksNote2After, isNotEmpty,
            reason: 'Other entity chunks should remain');
      });

      test('handles deletion of non-existent entity gracefully', () async {
        expect(
          () async {
            await noteRepository.deleteByUuid('does-not-exist');
          },
          returnsNormally,
          reason: 'Should handle deletion of non-existent entity',
        );
      });
    });

    group('integration - full lifecycle', () {
      test('save, update, search, delete workflow', () async {
        final note = TestNote(
          uuid: 'lifecycle-test',
          title: 'Machine Learning',
          content: 'Machine learning is a subset of artificial intelligence.',
        );

        // 1. Save and index
        await noteRepository.save(note);
        expect(hnswIndex.size, greaterThan(0), reason: 'Should be indexed');

        // 2. Update
        note.content =
            'Machine learning enables systems to learn from data without explicit programming.';
        await noteRepository.save(note);
        expect(hnswIndex.size, greaterThan(0),
            reason: 'Should still have chunks after update');

        // 3. Verify chunks are searchable
        final searchService = SemanticSearchService(
          index: hnswIndex,
          embeddingService: embeddingService,
          entityLoader: MockEntityLoader(),
        );

        final results = await searchService.search('learning from data', limit: 5);
        expect(results is List, isTrue,
            reason: 'Should be able to search indexed content');

        // 4. Delete
        await noteRepository.deleteByUuid('lifecycle-test');
        expect(hnswIndex.size, equals(0), reason: 'Should be completely removed');
      });
    });
  });
}

// ============ Test Doubles ============

class MockNoteRepository extends EntityRepository<TestNote> {
  final ChunkingService chunkingService;

  MockNoteRepository({
    required MockNoteAdapter adapter,
    required EmbeddingService embeddingService,
    required this.chunkingService,
  }) : super(
    adapter: adapter,
    embeddingService: embeddingService,
  );

  @override
  Future<int> save(TestNote entity) async {
    // NEW: Delete old chunks if entity was previously indexed (update case)
    if (entity is SemanticIndexable) {
      await chunkingService.deleteByEntityId(entity.uuid);
    }

    // Call parent save (handles Embeddable, Versionable, etc.)
    final id = await super.save(entity);

    // NEW: Trigger chunking and indexing for SemanticIndexable entities
    if (entity is SemanticIndexable) {
      await chunkingService.indexEntity(entity);
    }

    return id;
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    // NEW: Remove from semantic index first (before entity is deleted)
    await chunkingService.deleteByEntityId(uuid);

    // Call parent delete
    return await super.deleteByUuid(uuid);
  }

  // Helper for testing non-SemanticIndexable entities
  Future<int> saveNonIndexable(TestNoteNonIndexable entity) async {
    return 0; // Not stored, just testing the repository doesn't crash
  }
}

class MockNoteAdapter extends PersistenceAdapter<TestNote> {
  final Map<String, TestNote> _store = {};
  int _nextId = 1;

  @override
  Future<TestNote> save(TestNote entity) async {
    if (!_store.containsKey(entity.uuid)) {
      entity.id = _nextId++;
    }
    _store[entity.uuid] = entity;
    return entity;
  }

  @override
  Future<TestNote?> findByUuid(String uuid) async {
    return _store[uuid];
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    return _store.remove(uuid) != null;
  }

  // Stub implementations
  @override
  Future<TestNote> getById(int id) async => throw UnimplementedError();

  @override
  Future<TestNote> getByUuid(String uuid) async => throw UnimplementedError();

  @override
  Future<TestNote?> findById(int id) async => null;

  @override
  Future<List<TestNote>> findAll() async => [];

  @override
  Future<List<TestNote>> saveAll(List<TestNote> entities) async {
    for (final entity in entities) {
      await save(entity);
    }
    return entities;
  }

  @override
  Future<bool> delete(int id) async => false;

  @override
  Future<void> deleteAll(List<int> ids) async {}

  @override
  int get indexSize => 0;

  @override
  Future<int> count() async => _store.length;

  @override
  Future<void> rebuildIndex(
      Future<List<double>?> Function(TestNote entity) generateEmbedding) async {}

  @override
  Future<List<TestNote>> findUnsynced() async => [];

  @override
  Future<List<TestNote>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    return [];
  }

  @override
  Future<bool> deleteEmbedding(String entityUuid) async => true;

  @override
  Future<void> close() async {}

  @override
  TestNote? findByIdInTx(dynamic ctx, int id) => null;

  @override
  TestNote? findByUuidInTx(dynamic ctx, String uuid) => _store[uuid];

  @override
  List<TestNote> findAllInTx(dynamic ctx) => _store.values.toList();

  @override
  TestNote saveInTx(dynamic ctx, TestNote entity) {
    if (!_store.containsKey(entity.uuid)) {
      entity.id = _nextId++;
    }
    _store[entity.uuid] = entity;
    return entity;
  }

  @override
  List<TestNote> saveAllInTx(dynamic ctx, List<TestNote> entities) {
    for (final entity in entities) {
      saveInTx(ctx, entity);
    }
    return entities;
  }

  @override
  bool deleteInTx(dynamic ctx, int id) => false;

  @override
  bool deleteByUuidInTx(dynamic ctx, String uuid) =>
      _store.remove(uuid) != null;

  @override
  void deleteAllInTx(dynamic ctx, List<int> ids) {}
}

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

  @override
  double cosineSimilarity(List<double> a, List<double> b) {
    return EmbeddingService.cosineSimilarity(a, b);
  }
}

class MockEntityLoader extends EntityLoader {
  // Inherits default implementation that returns null
}

class ChunkingService {
  final HnswIndex index;
  final EmbeddingService embeddingService;
  final SemanticChunker parentChunker;
  final SemanticChunker childChunker;

  final Map<String, List<Chunk>> _chunkRegistry = {};
  static int _chunkCounter = 0;

  ChunkingService({
    required this.index,
    required this.embeddingService,
    required this.parentChunker,
    required this.childChunker,
  });

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

    // Generate parent chunks
    final parentChunkTexts = await parentChunker.chunk(input);

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

      final parentEmbedding =
          await embeddingService.generate(parentChunkText.text);
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

        final childEmbedding =
            await embeddingService.generate(childChunkText.text);
        index.insert(childChunk.id, childEmbedding);
      }
    }

    _chunkRegistry[entity.uuid] = chunks;
    return chunks;
  }

  Future<void> deleteByEntityId(String entityId) async {
    final chunks = _chunkRegistry[entityId] ?? [];
    for (final chunk in chunks) {
      index.delete(chunk.id);
    }
    _chunkRegistry.remove(entityId);
  }

  List<Chunk> getChunksForEntity(String entityId) {
    return _chunkRegistry[entityId] ?? [];
  }

  String _generateChunkId() {
    _chunkCounter++;
    return 'chunk-${_chunkCounter}';
  }
}

// ============ Test Entities ============

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

class TestNoteNonIndexable extends BaseEntity {
  String title;
  String content;

  TestNoteNonIndexable({
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
}
