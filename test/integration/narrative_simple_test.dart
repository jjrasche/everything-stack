import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/domain/narrative_entry.dart';
import 'package:everything_stack_template/domain/narrative_repository.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/objectbox.g.dart';

void main() {
  group('Narrative Integration - Simple', () {
    late Store store;
    late NarrativeRepository narrativeRepo;
    late Directory testDir;

    setUp(() async {
      // Create temporary directory for ObjectBox store
      testDir = await Directory.systemTemp.createTemp('narrative_test_');
      store = await openStore(directory: testDir.path);
      
      final narrativeBox = store.box<NarrativeEntry>();
      narrativeRepo = NarrativeRepository(
        adapter: NarrativeObjectBoxAdapter(store),
        embeddingService: MockEmbeddingService(),
      );
    });

    tearDown(() async {
      await store.closeAsync();
      await testDir.delete(recursive: true);
    });

    test('NarrativeEntry entity can be created and saved', () async {
      final entry = NarrativeEntry(
        content: 'Learned about offline-first architecture',
        scope: 'session',
        type: 'learning',
      );

      final id = await narrativeRepo.save(entry);
      expect(id, greaterThan(0));
    });

    test('NarrativeEntry persists and can be retrieved', () async {
      final entry = NarrativeEntry(
        content: 'Testing persistence',
        scope: 'day',
        type: 'checkpoint',
      );

      await narrativeRepo.save(entry);
      final retrieved = await narrativeRepo.findByScope('day');
      
      expect(retrieved, isNotEmpty);
      expect(retrieved.first.content, entry.content);
    });

    test('Narrative persists across app restart', () async {
      final entry = NarrativeEntry(
        content: 'Persist test',
        scope: 'session',
        type: 'learning',
      );

      await narrativeRepo.save(entry);
      final countBefore = await narrativeRepo.count();

      // Close and reopen
      await store.closeAsync();
      store = await openStore(directory: testDir.path);
      narrativeRepo = NarrativeRepository(
        adapter: NarrativeObjectBoxAdapter(store),
        embeddingService: MockEmbeddingService(),
      );

      final countAfter = await narrativeRepo.count();
      expect(countAfter, equals(countBefore));
    });
  });
}

class MockEmbeddingService extends EmbeddingService {
  @override
  Future<List<double>> generate(String text) async {
    // Return a deterministic mock embedding
    final hash = text.hashCode;
    return List.generate(384, (i) => ((hash + i) % 100).toDouble() / 100);
  }
}

class NarrativeObjectBoxAdapter {
  final Store store;
  NarrativeObjectBoxAdapter(this.store);
}
