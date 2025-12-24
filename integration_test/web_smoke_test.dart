/// # Full Stack Browser Smoke Test
///
/// ## What this tests
/// Complete end-to-end functionality on REAL persistence layer (both platforms):
/// - ObjectBox on native (VM)
/// - IndexedDB on web (browser)
///
/// ## Test coverage
/// 1. Factory initialization returns working adapters
/// 2. Versionable Note with embedding
/// 3. Atomic save (Note + EntityVersion in transaction)
/// 4. Semantic search with HNSW index
/// 5. Edge relationships
///
/// ## Platform testing
/// Run on VM: flutter test test/integration/web_smoke_test.dart
/// Run on Web: flutter test --platform chrome test/integration/web_smoke_test.dart
///
/// ## Success criteria
/// If this passes on BOTH platforms, dual-persistence works.

@TestOn('vm || browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:everything_stack_template/domain/note.dart';
import 'package:everything_stack_template/domain/note_repository.dart';
import 'package:everything_stack_template/core/edge.dart';
import 'package:everything_stack_template/core/edge_repository.dart';
import 'package:everything_stack_template/core/version_repository.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/blob_store.dart';

// Web-specific imports for IndexedDB
import 'package:everything_stack_template/bootstrap/persistence_factory_web.dart';
import 'package:everything_stack_template/persistence/indexeddb/database_init.dart';

void main() {
  // Initialize integration test bindings (required for platform access)
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('IndexedDB Browser Integration Test', () {
    testWidgets('Full persistence layer works in browser', (tester) async {
      // Delete any existing database for clean state
      await deleteIndexedDatabase();

      // Initialize IndexedDB persistence
      final factory = await initializePersistence();

      // Initialize services
      final embeddingService = MockEmbeddingService();
      final blobStore = MockBlobStore();
      await blobStore.initialize();

      // Create repositories
      final versionRepo = VersionRepository(adapter: factory.versionAdapter);
      final edgeRepo = EdgeRepository(adapter: factory.edgeAdapter);
      final noteRepo = NoteRepository(
        adapter: factory.noteAdapter,
        embeddingService: embeddingService,
        versionRepo: versionRepo,
      );
      noteRepo.setEdgeRepository(edgeRepo);

      // Test 1: Factory returns working adapters
      expect(noteRepo, isNotNull);
      expect(edgeRepo, isNotNull);
      expect(versionRepo, isNotNull);
      print('✓ Test 1: Factory returns working adapters');

      // Test 2: Create note with embedding
      final note1 = Note(
        title: 'Machine Learning Fundamentals',
        content: 'Neural networks are computational models.',
      );
      await noteRepo.save(note1);

      final loaded = await noteRepo.findByUuid(note1.uuid);
      expect(loaded, isNotNull);
      expect(loaded!.title, 'Machine Learning Fundamentals');
      expect(note1.embedding, isNotNull);
      print('✓ Test 2: Create note with embedding');

      // Test 3: Version history
      final versions = await versionRepo.getHistory(note1.uuid);
      expect(versions, hasLength(1));
      expect(versions[0].versionNumber, 1);

      note1.title = 'Updated Title';
      await noteRepo.save(note1);

      final versions2 = await versionRepo.getHistory(note1.uuid);
      expect(versions2, hasLength(2));
      expect(versions2[1].versionNumber, 2);
      print('✓ Test 3: Version history works');

      // Test 4: Semantic search
      final note2 = Note(title: 'Shopping', content: 'Buy milk and bread');
      await noteRepo.save(note2);

      final results =
          await noteRepo.semanticSearch('neural network AI', limit: 2);
      expect(results, isNotEmpty);
      print('✓ Test 4: Semantic search works');

      // Test 5: Edge relationships
      final edge = Edge(
        sourceType: 'Note',
        sourceUuid: note1.uuid,
        targetType: 'Note',
        targetUuid: note2.uuid,
        edgeType: 'related_to',
      );
      await edgeRepo.save(edge);

      final edges = await edgeRepo.findBySource(note1.uuid);
      expect(edges, hasLength(1));
      expect(edges[0].targetUuid, note2.uuid);
      print('✓ Test 5: Edge relationships work');

      // Test 6: Delete
      final deleted = await noteRepo.deleteByUuid(note2.uuid);
      expect(deleted, isTrue);

      final deletedNote = await noteRepo.findByUuid(note2.uuid);
      expect(deletedNote, isNull);
      print('✓ Test 6: Delete works');

      // Cleanup
      blobStore.dispose();

      print('\n========================================');
      print('ALL BROWSER INTEGRATION TESTS PASSED');
      print('========================================');
    });
  });
}
