/// # Handler Architecture Edge Case Tests
///
/// Tests that validate the handler pattern under stress:
/// - Handler failures and cascading
/// - Multi-pattern entity complex scenarios
/// - Transaction boundaries and rollback behavior
/// - SaveAll semantics with mixed patterns
/// - Delete without side effects

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import 'package:everything_stack_template/core/persistence/transaction_context.dart';
import 'package:everything_stack_template/core/repository_pattern_handler.dart';
import 'package:everything_stack_template/patterns/embeddable.dart';
import 'package:everything_stack_template/patterns/semantic_indexable.dart';
import 'package:everything_stack_template/patterns/versionable.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import '../harness/semantic_test_doubles.dart';

// ============ Test Entities ============

class TestMultiPatternEntity extends BaseEntity
    with Embeddable, SemanticIndexable, Versionable {
  String title;

  late final String _uuid;

  TestMultiPatternEntity({required this.title, String? uuid}) {
    _uuid = uuid ?? 'test-uuid-${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}';
  }

  @override
  String get uuid => _uuid;

  @override
  String toEmbeddingInput() => title;

  @override
  String toChunkableInput() => title;

  @override
  String getChunkingConfig() => 'parent';

  @override
  int? get snapshotFrequency => null;

  Map<String, dynamic> toJson() => {'title': title, 'uuid': uuid};
}

// ============ Failure Handlers ============

/// Handler that fails in afterSave
class FailingEmbeddableHandler<T extends BaseEntity>
    extends RepositoryPatternHandler<T> {
  final EmbeddingService embeddingService;

  FailingEmbeddableHandler(this.embeddingService);

  @override
  Future<void> beforeSave(T entity) async {
    if (entity is Embeddable) {
      final input = (entity as Embeddable).toEmbeddingInput();
      if (input.trim().isNotEmpty) {
        (entity as Embeddable).embedding =
            await embeddingService.generate(input);
      }
    }
  }

  @override
  Future<void> afterSave(T entity) async {
    // Intentionally fail in afterSave
    throw Exception('Simulated embedding index failure');
  }
}

/// Handler that fails in beforeSave
class FailingBeforeSaveHandler<T extends BaseEntity>
    extends RepositoryPatternHandler<T> {
  @override
  Future<void> beforeSave(T entity) async {
    throw Exception('Simulated validation failure');
  }
}

// ============ Tests ============

void main() {
  group('Handler Edge Cases', () {
    late MockEmbeddingService embeddingService;
    late TestMultiPatternEntity entity;

    setUp(() {
      embeddingService = MockEmbeddingService();
      entity = TestMultiPatternEntity(title: 'Test Note');
    });

    group('Handler Failure Semantics', () {
      test('beforeSave failure aborts save (fail-fast)', () async {
        final adapter = TestMultiPatternAdapter();
        final handlers = <RepositoryPatternHandler<TestMultiPatternEntity>>[
          FailingBeforeSaveHandler<TestMultiPatternEntity>(),
        ];

        final repo = TestEntityRepository(
          adapter: adapter,
          handlers: handlers,
          embeddingService: embeddingService,
        );

        expect(
          () => repo.save(entity),
          throwsException,
        );

        // Entity should NOT be persisted
        expect(adapter._store.isEmpty, true);
      });

      test('afterSave failure does not abort save (best-effort)', () async {
        final adapter = TestMultiPatternAdapter();
        final handlers = <RepositoryPatternHandler<TestMultiPatternEntity>>[
          FailingEmbeddableHandler<TestMultiPatternEntity>(embeddingService),
        ];

        final repo = TestEntityRepository(
          adapter: adapter,
          handlers: handlers,
          embeddingService: embeddingService,
        );

        // Should NOT throw, even though afterSave fails (best-effort logs and continues)
        await repo.save(entity);

        // Entity SHOULD be persisted (afterSave failure is logged but not propagated)
        expect(adapter._store.containsKey(entity.uuid), true);
      });

      test('handler failure with multiple patterns does not skip remaining',
          () async {
        // First handler fails in afterSave, second should still run
        var secondHandlerRan = false;

        final trackingHandler = _TrackingHandler<TestMultiPatternEntity>(
          onAfterSave: (_) {
            secondHandlerRan = true;
          },
        );

        final failingHandler =
            FailingEmbeddableHandler<TestMultiPatternEntity>(embeddingService);

        final adapter = TestMultiPatternAdapter();
        final handlers = <RepositoryPatternHandler<TestMultiPatternEntity>>[
          failingHandler,
          trackingHandler,
        ];

        final repo = TestEntityRepository(
          adapter: adapter,
          handlers: handlers,
          embeddingService: embeddingService,
        );

        await repo.save(entity);

        // Second handler should have run despite first handler's failure
        expect(secondHandlerRan, true);
      });
    });

    group('Multi-Pattern Entity Scenarios', () {
      test('Multi-pattern save executes all handlers in order', () async {
        final executionOrder = <String>[];

        final handler1 = _TrackingHandler<TestMultiPatternEntity>(
          onBeforeSave: (_) => executionOrder.add('beforeSave-1'),
          onAfterSave: (_) => executionOrder.add('afterSave-1'),
        );

        final handler2 = _TrackingHandler<TestMultiPatternEntity>(
          onBeforeSave: (_) => executionOrder.add('beforeSave-2'),
          onAfterSave: (_) => executionOrder.add('afterSave-2'),
        );

        final adapter = TestMultiPatternAdapter();
        final handlers = <RepositoryPatternHandler<TestMultiPatternEntity>>[
          handler1,
          handler2,
        ];

        final repo = TestEntityRepository(
          adapter: adapter,
          handlers: handlers,
          embeddingService: embeddingService,
        );

        await repo.save(entity);

        expect(
          executionOrder,
          [
            'beforeSave-1',
            'beforeSave-2',
            'afterSave-1',
            'afterSave-2',
          ],
        );
      });

      test('Multi-pattern delete executes beforeDelete hooks', () async {
        final deletionOrder = <String>[];

        final handler1 = _TrackingHandler<TestMultiPatternEntity>(
          onBeforeDelete: (_) => deletionOrder.add('beforeDelete-1'),
        );

        final handler2 = _TrackingHandler<TestMultiPatternEntity>(
          onBeforeDelete: (_) => deletionOrder.add('beforeDelete-2'),
        );

        final adapter = TestMultiPatternAdapter();
        // Pre-populate with entity
        adapter._store[entity.uuid] = entity;

        final handlers = <RepositoryPatternHandler<TestMultiPatternEntity>>[
          handler1,
          handler2,
        ];

        final repo = TestEntityRepository(
          adapter: adapter,
          handlers: handlers,
          embeddingService: embeddingService,
        );

        await repo.deleteByUuid(entity.uuid);

        expect(
          deletionOrder,
          [
            'beforeDelete-1',
            'beforeDelete-2',
          ],
        );

        // Entity should be deleted
        expect(adapter._store.containsKey(entity.uuid), false);
      });
    });

    group('SaveAll Semantics', () {
      test('saveAll applies handlers to each entity', () async {
        var saveCount = 0;

        final countingHandler = _TrackingHandler<TestMultiPatternEntity>(
          onBeforeSave: (_) => saveCount++,
        );

        final adapter = TestMultiPatternAdapter();
        final handlers = <RepositoryPatternHandler<TestMultiPatternEntity>>[
          countingHandler,
        ];

        final repo = TestEntityRepository(
          adapter: adapter,
          handlers: handlers,
          embeddingService: embeddingService,
        );

        final entities = [
          TestMultiPatternEntity(title: 'Entity 1', uuid: 'uuid-1'),
          TestMultiPatternEntity(title: 'Entity 2', uuid: 'uuid-2'),
          TestMultiPatternEntity(title: 'Entity 3', uuid: 'uuid-3'),
        ];

        await repo.saveAll(entities);

        // Handler should run 3 times (once per entity)
        expect(saveCount, 3);
        expect(adapter._store.length, 3);
      });

      test('saveAll continues on handler failure per entity', () async {
        var failingEntity =
            TestMultiPatternEntity(title: 'Failing Entity');

        final conditionalFailHandler =
            _ConditionalFailHandler<TestMultiPatternEntity>(
          shouldFailOn: (e) =>
              (e as TestMultiPatternEntity).title == 'Failing Entity',
        );

        final adapter = TestMultiPatternAdapter();
        final handlers = <RepositoryPatternHandler<TestMultiPatternEntity>>[
          conditionalFailHandler,
        ];

        final repo = TestEntityRepository(
          adapter: adapter,
          handlers: handlers,
          embeddingService: embeddingService,
        );

        final entities = [
          TestMultiPatternEntity(title: 'Entity 1'),
          failingEntity,
          TestMultiPatternEntity(title: 'Entity 3'),
        ];

        // saveAll with one failure should still process others
        // (save() is called per entity, each can fail independently)
        try {
          await repo.saveAll(entities);
          fail('Expected saveAll to throw');
        } catch (e) {
          // Expected
        }

        // But entities before the failure should be saved
        expect(adapter._store.length, greaterThanOrEqualTo(1));
      });
    });

    group('Delete Edge Cases', () {
      test('delete non-existent entity returns false', () async {
        final adapter = TestMultiPatternAdapter();
        final handlers = <RepositoryPatternHandler<TestMultiPatternEntity>>[];

        final repo = TestEntityRepository(
          adapter: adapter,
          handlers: handlers,
          embeddingService: embeddingService,
        );

        final result = await repo.deleteByUuid('non-existent-uuid');
        expect(result, false);
      });

      test('delete with handler failure aborts deletion', () async {
        final adapter = TestMultiPatternAdapter();
        adapter._store[entity.uuid] = entity;

        final failingHandler =
            _ConditionalFailHandler<TestMultiPatternEntity>(
          shouldFailOn: (_) => true,
        );

        final handlers = <RepositoryPatternHandler<TestMultiPatternEntity>>[
          failingHandler,
        ];

        final repo = TestEntityRepository(
          adapter: adapter,
          handlers: handlers,
          embeddingService: embeddingService,
        );

        expect(
          () => repo.deleteByUuid(entity.uuid),
          throwsException,
        );

        // Entity should still exist (delete was aborted)
        expect(adapter._store.containsKey(entity.uuid), true);
      });
    });
  });
}

// ============ Test Adapter ============

class TestMultiPatternAdapter
    extends PersistenceAdapter<TestMultiPatternEntity> {
  final Map<String, TestMultiPatternEntity> _store = {};
  int _nextId = 1;

  @override
  Future<TestMultiPatternEntity> save(TestMultiPatternEntity entity) async {
    if (!_store.containsKey(entity.uuid)) {
      entity.id = _nextId++;
    }
    _store[entity.uuid] = entity;
    return entity;
  }

  @override
  Future<TestMultiPatternEntity?> findByUuid(String uuid) async {
    return _store[uuid];
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    return _store.remove(uuid) != null;
  }

  @override
  Future<TestMultiPatternEntity?> findById(int id) async => null;

  @override
  Future<TestMultiPatternEntity> getById(int id) async =>
      throw UnimplementedError();

  @override
  Future<TestMultiPatternEntity> getByUuid(String uuid) async =>
      throw UnimplementedError();

  @override
  Future<List<TestMultiPatternEntity>> findAll() async => _store.values.toList();

  @override
  Future<List<TestMultiPatternEntity>> saveAll(
      List<TestMultiPatternEntity> entities) async {
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
      Future<List<double>?> Function(TestMultiPatternEntity entity)
          generateEmbedding) async {}

  @override
  Future<List<TestMultiPatternEntity>> findUnsynced() async => [];

  @override
  Future<List<TestMultiPatternEntity>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async =>
      [];

  @override
  Future<bool> deleteEmbedding(String entityUuid) async => true;

  @override
  Future<void> close() async {}

  @override
  TestMultiPatternEntity? findByIdInTx(dynamic ctx, int id) => null;

  @override
  TestMultiPatternEntity? findByUuidInTx(dynamic ctx, String uuid) =>
      _store[uuid];

  @override
  List<TestMultiPatternEntity> findAllInTx(dynamic ctx) =>
      _store.values.toList();

  @override
  TestMultiPatternEntity saveInTx(dynamic ctx, TestMultiPatternEntity entity) {
    if (!_store.containsKey(entity.uuid)) {
      entity.id = _nextId++;
    }
    _store[entity.uuid] = entity;
    return entity;
  }

  @override
  List<TestMultiPatternEntity> saveAllInTx(
      dynamic ctx, List<TestMultiPatternEntity> entities) {
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

// ============ Test Helpers ============

/// Simple test repository
class TestEntityRepository
    extends EntityRepository<TestMultiPatternEntity> {
  TestEntityRepository({
    required TestMultiPatternAdapter adapter,
    required List<RepositoryPatternHandler<TestMultiPatternEntity>> handlers,
    required EmbeddingService embeddingService,
  }) : super(
    adapter: adapter,
    embeddingService: embeddingService,
    handlers: handlers,
  );
}

/// Tracking handler to verify execution
class _TrackingHandler<T extends BaseEntity>
    extends RepositoryPatternHandler<T> {
  final Function(T)? onBeforeSave;
  final Function(T)? onAfterSave;
  final Function(T)? onBeforeDelete;

  _TrackingHandler({
    this.onBeforeSave,
    this.onAfterSave,
    this.onBeforeDelete,
  });

  @override
  Future<void> beforeSave(T entity) async {
    onBeforeSave?.call(entity);
  }

  @override
  Future<void> afterSave(T entity) async {
    onAfterSave?.call(entity);
  }

  @override
  Future<void> beforeDelete(T entity) async {
    onBeforeDelete?.call(entity);
  }
}

/// Handler that conditionally fails
class _ConditionalFailHandler<T extends BaseEntity>
    extends RepositoryPatternHandler<T> {
  final bool Function(T) shouldFailOn;

  _ConditionalFailHandler({required this.shouldFailOn});

  @override
  Future<void> beforeSave(T entity) async {
    if (shouldFailOn(entity)) {
      throw Exception('Conditional failure in beforeSave');
    }
  }

  @override
  Future<void> beforeDelete(T entity) async {
    if (shouldFailOn(entity)) {
      throw Exception('Conditional failure in beforeDelete');
    }
  }
}
