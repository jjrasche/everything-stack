/// # Notes Demo Integration Tests
///
/// Comprehensive integration tests proving all patterns work together.
/// This test suite validates the full stack functionality of the template.

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/domain/note.dart';
import 'package:everything_stack_template/domain/note_repository.dart';
import 'package:everything_stack_template/core/edge.dart';
import 'package:everything_stack_template/core/edge_repository.dart';
import 'package:everything_stack_template/core/entity_version.dart';
import 'package:everything_stack_template/core/version_repository.dart';
import 'package:everything_stack_template/persistence/objectbox/note_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/edge_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/entity_version_objectbox_adapter.dart';
import 'package:everything_stack_template/core/persistence/objectbox_transaction_manager.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/blob_store.dart';
import 'package:everything_stack_template/patterns/file_storable.dart';
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/objectbox.g.dart';

void main() {
  late Store store;
  late NoteRepository noteRepo;
  late EdgeRepository edgeRepo;
  late VersionRepository versionRepo;
  late MockEmbeddingService embeddingService;
  late MockBlobStore blobStore;
  late Directory testDir;

  setUp(() async {
    // Create temporary directory for ObjectBox store
    testDir = await Directory.systemTemp.createTemp('objectbox_test_');

    // Open ObjectBox store
    store = await openStore(directory: testDir.path);

    // Initialize services
    embeddingService = MockEmbeddingService();
    blobStore = MockBlobStore();
    await blobStore.initialize();

    // Initialize repositories with adapters
    final versionAdapter = EntityVersionObjectBoxAdapter(store);
    versionRepo = VersionRepository(adapter: versionAdapter);

    final edgeAdapter = EdgeObjectBoxAdapter(store);
    edgeRepo = EdgeRepository(adapter: edgeAdapter);

    final noteAdapter = NoteObjectBoxAdapter(store);
    noteRepo = NoteRepository(
      adapter: noteAdapter,
      embeddingService: embeddingService,
      versionRepo: versionRepo,
      // IMPORTANT: ObjectBox's transaction manager cannot be used with EntityRepository's
      // transactional save path due to Dart isolate serialization limitations.
      // ObjectBox.runInTransactionAsync uses isolates to execute callbacks, but the lambda
      // would need to capture the repository instance (which contains the Store), and
      // the Store cannot be serialized across isolate boundaries.
      //
      // Without transactionManager: VersionableHandler falls back to non-transactional
      // version recording (calls _recordVersionChange after save). This is not atomic
      // but maintains consistency for the demo.
      //
      // For production systems requiring atomic version tracking with ObjectBox,
      // consider alternatives:
      // - Use IndexedDB on Web (doesn't have this limitation)
      // - Implement custom atomic operations at the adapter level
      // - Use a different persistence backend that supports atomic transactions
    );
    noteRepo.setEdgeRepository(edgeRepo);
  });

  tearDown(() async {
    store.close();
    blobStore.dispose();
    // Clean up temp directory
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('Notes Demo Integration', () {
    group('1. Create and Search', () {
      test('semantic search returns most relevant notes', () async {
        // Create notes with different content
        final note1 = Note(
          title: 'Project Timeline',
          content:
              'The project deadline is December 15th. We need to complete the API integration by next week.',
        );
        final note2 = Note(
          title: 'Grocery List',
          content: 'Buy milk, eggs, bread, and coffee from the store.',
        );
        final note3 = Note(
          title: 'API Documentation',
          content:
              'REST API endpoints for user authentication and project management.',
        );

        await noteRepo.save(note1);
        await noteRepo.save(note2);
        await noteRepo.save(note3);

        // Search for project-related content
        final results =
            await noteRepo.semanticSearch('project deadlines', limit: 2);

        // Should find note1 and note3, not note2
        expect(results, hasLength(2));
        expect(results.any((n) => n.uuid == note1.uuid), isTrue);
        expect(results.any((n) => n.uuid == note3.uuid), isTrue);
        expect(results.any((n) => n.uuid == note2.uuid), isFalse);
      });
    });

    group('2. Version Tracking', () {
      test('tracks version history and reconstructs past state', () async {
        // Create note
        final note = Note(
          title: 'Version Test',
          content: 'Initial content',
        );
        await noteRepo.save(note);

        // Edit title 3 times
        await Future.delayed(const Duration(milliseconds: 10));
        note.title = 'Version Test - Edit 1';
        await noteRepo.save(note);

        await Future.delayed(const Duration(milliseconds: 10));
        final timestampBeforeEdit3 = DateTime.now();
        await Future.delayed(const Duration(milliseconds: 10));

        note.title = 'Version Test - Edit 2';
        await noteRepo.save(note);

        await Future.delayed(const Duration(milliseconds: 10));
        note.title = 'Version Test - Edit 3';
        await noteRepo.save(note);

        // Get history - should show 4 versions (initial + 3 edits)
        final history = await noteRepo.getHistory(note.uuid);
        expect(history, hasLength(4));

        // Reconstruct state before edit 3
        final reconstructed = await versionRepo.reconstruct(
          note.uuid,
          timestampBeforeEdit3,
        );
        expect(reconstructed, isNotNull);
        expect(reconstructed!['title'], 'Version Test - Edit 1');
      });
    });

    group('3. File Attachments', () {
      test('attaches files and stores blobs', () async {
        // Create note
        final note = Note(
          title: 'Note with Attachments',
          content: 'This note has files attached',
        );
        await noteRepo.save(note);

        // Attach mock image
        final imageBytes =
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]); // JPEG header
        final fileMetadata = FileMetadata(
          uuid: 'file-123',
          filename: 'screenshot.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: imageBytes.length,
        )..createdAt = DateTime.now();
        note.addAttachment(fileMetadata);
        await noteRepo.save(note);

        // Save blob separately
        await blobStore.save(fileMetadata.uuid, imageBytes);

        // Verify FileMetadata stored in note
        final reloaded = await noteRepo.findByUuid(note.uuid);
        expect(reloaded!.hasAttachments, isTrue);
        expect(reloaded.attachments, hasLength(1));
        expect(reloaded.attachments[0].filename, 'screenshot.jpg');

        // Verify blob in BlobStore
        final loadedBlob = await blobStore.load(fileMetadata.uuid);
        expect(loadedBlob, equals(imageBytes));
      });
    });

    group('4. Graph Edges', () {
      test('traverses multi-hop note links', () async {
        // Create notes
        final noteA = Note(title: 'Note A', content: 'First note');
        final noteB = Note(title: 'Note B', content: 'Second note');
        final noteC = Note(title: 'Note C', content: 'Third note');

        await noteRepo.save(noteA);
        await noteRepo.save(noteB);
        await noteRepo.save(noteC);

        // Link A → B → C
        await edgeRepo.save(Edge(
          sourceType: 'Note',
          sourceUuid: noteA.uuid,
          targetType: 'Note',
          targetUuid: noteB.uuid,
          edgeType: 'references',
        ));
        await edgeRepo.save(Edge(
          sourceType: 'Note',
          sourceUuid: noteB.uuid,
          targetType: 'Note',
          targetUuid: noteC.uuid,
          edgeType: 'references',
        ));

        // Traverse from A with depth 2 - should find both B and C
        final reachable = await edgeRepo.traverse(
          startUuid: noteA.uuid,
          depth: 2,
          direction: 'outgoing',
        );

        expect(reachable.keys, contains(noteB.uuid));
        expect(reachable.keys, contains(noteC.uuid));
        expect(reachable[noteB.uuid], 1); // B at depth 1
        expect(reachable[noteC.uuid], 2); // C at depth 2

        // Use NoteRepository convenience method
        final linkedNotes = await noteRepo.getLinkedNotes(noteA.uuid);
        expect(linkedNotes, hasLength(2));
        expect(linkedNotes.any((n) => n.uuid == noteB.uuid), isTrue);
        expect(linkedNotes.any((n) => n.uuid == noteC.uuid), isTrue);
      });
    });

    group('5. Pattern Composition', () {
      test('all patterns work together without conflict', () async {
        // Create note with location (Locatable)
        final note = Note(
          title: 'Meeting Notes',
          content: 'Discussed Q4 roadmap',
        );
        note.setLocation(37.7749, -122.4194); // San Francisco
        await noteRepo.save(note);

        // Edit it (Versionable)
        await Future.delayed(const Duration(milliseconds: 10));
        note.content = 'Discussed Q4 roadmap and budget';
        await noteRepo.save(note);

        // Attach file (FileStorable)
        final fileBytes =
            Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // PDF header
        final fileMetadata = FileMetadata(
          uuid: 'file-456',
          filename: 'roadmap.pdf',
          mimeType: 'application/pdf',
          sizeBytes: fileBytes.length,
        )..createdAt = DateTime.now();
        note.addAttachment(fileMetadata);
        await noteRepo.save(note);
        await blobStore.save(fileMetadata.uuid, fileBytes);

        // Link to another note (Edgeable)
        final relatedNote =
            Note(title: 'Budget Details', content: 'Q4 budget breakdown');
        await noteRepo.save(relatedNote);
        await edgeRepo.save(Edge(
          sourceType: 'Note',
          sourceUuid: note.uuid,
          targetType: 'Note',
          targetUuid: relatedNote.uuid,
          edgeType: 'references',
        ));

        // Verify all patterns work
        final reloaded = await noteRepo.findByUuid(note.uuid);
        expect(reloaded, isNotNull);

        // Locatable
        expect(reloaded!.hasLocation, isTrue);
        expect(reloaded.latitude, 37.7749);
        expect(reloaded.longitude, -122.4194);

        // Versionable
        final history = await versionRepo.getHistory(note.uuid);
        expect(history.length, greaterThanOrEqualTo(2)); // At least 2 versions

        // FileStorable
        expect(reloaded.hasAttachments, isTrue);
        expect(reloaded.attachments[0].filename, 'roadmap.pdf');
        final blob = await blobStore.load('file-456');
        expect(blob, equals(fileBytes));

        // Edgeable
        final edges = await edgeRepo.findBySource(note.uuid);
        expect(edges, hasLength(1));
        expect(edges[0].targetUuid, relatedNote.uuid);

        // Embeddable (search should find it)
        final searchResults =
            await noteRepo.semanticSearch('roadmap', limit: 5);
        expect(searchResults.any((n) => n.uuid == note.uuid), isTrue);

        // Ownable (set owner)
        reloaded.ownerId = 'user-123';
        await noteRepo.save(reloaded);
        final withOwner = await noteRepo.findByUuid(note.uuid);
        expect(withOwner!.ownerId, 'user-123');
        expect(withOwner.isOwnedBy('user-123'), isTrue);
      });
    });

    group('6. Sync Status Flow', () {
      test('tracks sync status through edit cycle', () async {
        // Create note - should be local
        final note = Note(
          title: 'Sync Test',
          content: 'Testing sync flow',
        );
        await noteRepo.save(note);
        expect(note.syncStatus, SyncStatus.local);

        // Simulate sync
        note.syncId = 'remote-123';
        note.syncStatus = SyncStatus.synced;
        await noteRepo.save(note);

        final synced = await noteRepo.findByUuid(note.uuid);
        expect(synced!.syncStatus, SyncStatus.synced);
        expect(synced.syncId, 'remote-123');

        // Edit note - should go back to local
        synced.content = 'Updated content after sync';
        synced.syncStatus = SyncStatus.local;
        await noteRepo.save(synced);

        final modified = await noteRepo.findByUuid(note.uuid);
        expect(modified!.syncStatus, SyncStatus.local);

        // Find unsynced notes
        final unsynced = await noteRepo.findUnsynced();
        expect(unsynced, hasLength(1));
        expect(unsynced[0].uuid, note.uuid);
      });
    });
  });
}
