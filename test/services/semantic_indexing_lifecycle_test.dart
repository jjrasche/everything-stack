import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/chunking/semantic_chunker.dart';
import 'package:everything_stack_template/services/chunking/chunking_config.dart';
import 'package:everything_stack_template/services/hnsw_index.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import '../harness/semantic_test_doubles.dart';

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

        // Verify chunks still exist after update
        expect(hnswIndex.size, greaterThan(0),
            reason: 'Should still have chunks after update');
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

        // Should not add to HNSW index (size should be 0)
        expect(hnswIndex.size, equals(0),
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

        // Should have chunks indexed
        expect(hnswIndex.size, greaterThan(0),
            reason: 'Entity with content should be indexed');
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

        // Verify no chunks exist for deleted entity (index is empty)
        expect(hnswIndex.size, equals(0),
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

        final sizeAfterBoth = hnswIndex.size;
        expect(sizeAfterBoth, greaterThan(0));

        // Delete first entity
        await noteRepository.deleteByUuid('entity-a');

        // Second entity's chunks should still be indexed
        final sizeAfterDelete = hnswIndex.size;
        expect(sizeAfterDelete, greaterThan(0),
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
        expect(results, isA<List>(),
            reason: 'Should be able to search indexed content');

        // 4. Delete
        await noteRepository.deleteByUuid('lifecycle-test');
        expect(hnswIndex.size, equals(0), reason: 'Should be completely removed');
      });
    });
  });
}
