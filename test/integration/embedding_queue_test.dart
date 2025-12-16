/// Integration test for EmbeddingQueueService
///
/// Tests end-to-end flow: Note save → queue → embedding → search

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/note.dart';
import 'package:everything_stack_template/domain/note_repository.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/embedding_queue_service.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import '../harness/persistence_test_harness.dart';

void main() {
  group('EmbeddingQueueService integration', () {
    late PersistenceTestHarness harness;
    late NoteRepository noteRepo;
    late EmbeddingQueueService embeddingQueueService;
    late MockEmbeddingService embeddingService;

    setUp(() async {
      // Use test harness for persistence setup
      harness = PersistenceTestHarness();
      await harness.initialize();

      // Use mock embedding service for predictable tests
      embeddingService = MockEmbeddingService();

      // Create embedding queue service
      final noteAdapter = harness.factory.noteAdapter as PersistenceAdapter<Note>;
      embeddingQueueService = EmbeddingQueueService(
        store: harness.factory.store,
        embeddingService: embeddingService,
        noteAdapter: noteAdapter,
      );

      // Don't start periodic timer in tests - use flush() for immediate processing

      // Create repository with mock embedding service
      noteRepo = NoteRepository(
        adapter: noteAdapter,
        embeddingService: embeddingService,
        embeddingQueueService: embeddingQueueService,
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('Note save enqueues embedding task and processes in background',
        () async {
      // 1. Save a note
      final note = Note(
        title: 'Test Note',
        content: 'This is test content for embedding generation.',
      );

      final noteId = await noteRepo.save(note);
      expect(noteId, greaterThan(0));

      // 2. Verify embedding is NOT yet generated (happens in background)
      final savedNote = await noteRepo.findByUuid(note.uuid);
      expect(savedNote, isNotNull);
      expect(savedNote!.embedding, isNull); // Not yet embedded

      // 3. Check queue stats - should have 1 pending task
      final stats = await embeddingQueueService.getStats();
      expect(stats['pending'], equals(1));

      // 4. Process the queue immediately (flush)
      await embeddingQueueService.flush();

      // 5. Verify embedding was generated
      final embeddedNote = await noteRepo.findByUuid(note.uuid);
      expect(embeddedNote, isNotNull);
      expect(embeddedNote!.embedding, isNotEmpty);
      expect(embeddedNote.embedding?.length, equals(EmbeddingService.dimension));

      // 6. Check queue stats - should be empty now
      final completedStats = await embeddingQueueService.getStats();
      expect(completedStats['pending'], equals(0));
      expect(completedStats['completed'], greaterThan(0));
    });

    test('Semantic search works after embedding generation', () async {
      // 1. Create multiple notes
      final note1 = Note(
        title: 'Dart Programming',
        content: 'Dart is a great language for Flutter development.',
      );
      final note2 = Note(
        title: 'Python Tutorial',
        content: 'Python is widely used for data science and ML.',
      );

      await noteRepo.save(note1);
      await noteRepo.save(note2);

      // 2. Process embeddings
      await embeddingQueueService.flush();

      // 3. Search for Dart-related content
      final results = await noteRepo.semanticSearch(
        'Flutter',
        limit: 10,
      );

      // 4. Verify results
      expect(results, isNotEmpty);
      // MockEmbeddingService returns identical vectors, so both will match
      // In production with real embeddings, note1 would rank higher
      expect(results.length, equals(2));
    });

    test('Embedding queue survives Note deletion', () async {
      // 1. Save a note
      final note = Note(
        title: 'To be deleted',
        content: 'This note will be deleted before embedding completes.',
      );

      await noteRepo.save(note);

      // 2. Delete the note immediately (before queue processes)
      await noteRepo.deleteByUuid(note.uuid);

      // 3. Process the queue
      await embeddingQueueService.flush();

      // 4. Queue should handle gracefully (mark as completed, not failed)
      final stats = await embeddingQueueService.getStats();
      expect(stats['pending'], equals(0));
      expect(stats['failed'], equals(0)); // Should NOT be marked as failed
    });

    test('Note update does not change updatedAt when embedding is saved',
        () async {
      // 1. Save a note
      final note = Note(
        title: 'Timestamp Test',
        content: 'Testing that embedding save preserves updatedAt.',
      );

      await noteRepo.save(note);
      final savedNote = await noteRepo.findByUuid(note.uuid);
      final originalUpdatedAt = savedNote!.updatedAt;

      // 2. Wait a moment to ensure timestamp would change if touched
      await Future.delayed(Duration(milliseconds: 100));

      // 3. Process embedding queue (should use touch: false)
      await embeddingQueueService.flush();

      // 4. Verify updatedAt was NOT changed
      final embeddedNote = await noteRepo.findByUuid(note.uuid);
      expect(embeddedNote!.updatedAt, equals(originalUpdatedAt));
      expect(embeddedNote.embedding, isNotEmpty); // But embedding was added
    });
  });
}
