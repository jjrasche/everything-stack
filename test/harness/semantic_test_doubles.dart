/// Test doubles and mocks for semantic indexing and chunking services.
///
/// Shared test utilities for:
/// - MockEmbeddingService: Generates deterministic mock embeddings
/// - MockEntityLoader: Placeholder entity loader for tests
/// - TestNote: Simple test entity with SemanticIndexable
/// - MockNoteAdapter: In-memory persistence adapter
/// - MockNoteRepository: Repository with mock adapter

/// Shared test utilities for:
/// - MockEntityLoader: Placeholder entity loader for tests
/// - TestNote: Simple test entity with SemanticIndexable
/// - MockNoteAdapter: In-memory persistence adapter
/// - MockNoteRepository: Repository with mock adapter
/// - MockEmbeddingService: Imported from main library

import 'dart:convert';
import 'dart:math' show sqrt, sin;
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/patterns/semantic_indexable.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search.dart';

import 'package:everything_stack_template/core/generic_handler_factory.dart';
// ============ Embedding Service Mock ============

/// Deterministic mock embedding service for testing.
/// Same input always produces same output, enabling reproducible tests.
/// Uses FNV-1a hashing + trigonometric functions for distribution.
class MockEmbeddingService extends EmbeddingService {
  final Map<String, List<double>> _cache = {};

  @override
  Future<List<double>> generate(String text) async {
    return mockEmbedding(text);
  }

  /// Generate deterministic embedding for text.
  /// Cached for performance - same text always returns same vector.
  List<double> mockEmbedding(String text) {
    if (_cache.containsKey(text)) {
      return _cache[text]!;
    }

    // Generate semantic vector based on word content
    // Documents with shared words will have similar vectors
    final words = _tokenize(text);

    if (words.isEmpty) {
      // Return zero vector for empty text
      return List.filled(EmbeddingService.dimension, 0.0);
    }

    // Sum word vectors
    final vector = List<double>.filled(EmbeddingService.dimension, 0.0);
    for (final word in words) {
      final wordHash = _hashString(word);
      for (var i = 0; i < EmbeddingService.dimension; i++) {
        vector[i] += _deterministicFloat(wordHash, i);
      }
    }

    // Normalize to unit length
    final normalized = _normalize(vector);
    _cache[text] = normalized;
    return normalized;
  }

  @override
  Future<List<List<double>>> generateBatch(List<String> texts) async {
    return texts.map((t) => mockEmbedding(t)).toList();
  }

  double cosineSimilarity(List<double> a, List<double> b) {
    return EmbeddingService.cosineSimilarity(a, b);
  }

  /// Tokenize text into lowercase words
  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ') // Remove punctuation
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// Hash string to int using FNV-1a algorithm.
  int _hashString(String text) {
    const fnvPrime = 0x01000193;
    const fnvOffset = 0x811c9dc5;
    var hash = fnvOffset;

    final bytes = utf8.encode(text);
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }

    return hash;
  }

  /// Generate deterministic float from hash and index.
  double _deterministicFloat(int hash, int index) {
    // Combine hash with index to get unique value per dimension
    final combined = (hash + index * 31) & 0xFFFFFFFF;
    // Use sine for smooth distribution in [-1, 1] range
    return sin(combined.toDouble() / 1000000);
  }

  /// Normalize vector to unit length.
  List<double> _normalize(List<double> vector) {
    var sumSquares = 0.0;
    for (final v in vector) {
      sumSquares += v * v;
    }

    if (sumSquares == 0) {
      // Return arbitrary unit vector if input is zero
      return List.generate(
        vector.length,
        (i) => i == 0 ? 1.0 : 0.0,
      );
    }

    final norm = sqrt(sumSquares);
    return vector.map((v) => v / norm).toList();
  }
}

// ============ Entity Loader Mock ============

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

  // Support dynamic property access for semantic indexing handler
  final Map<String, dynamic> _dynamicProperties = {};

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

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      return _dynamicProperties[invocation.memberName.toString()];
    } else if (invocation.isSetter) {
      final name = invocation.memberName.toString().replaceFirst('=', '');
      _dynamicProperties[name] = invocation.positionalArguments[0];
      return null;
    }
    return super.noSuchMethod(invocation);
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

// ============ Persistence Adapter Mock ============

class MockNoteAdapter extends PersistenceAdapter<TestNote> {
  final Map<String, TestNote> _store = {};
  int _nextId = 1;

  @override
  Future<TestNote> save(TestNote entity, {bool touch = true}) async {
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
      Future<List<double>?> Function(TestNote entity)
          generateEmbedding) async {}

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

  Future<bool> deleteEmbedding(String entityUuid) async => true;

  Future<void> close() async {}

  TestNote? findByIdInTx(dynamic ctx, int id) => null;

  TestNote? findByUuidInTx(dynamic ctx, String uuid) => _store[uuid];

  @override
  List<TestNote> findAllInTx(dynamic ctx) => _store.values.toList();

  @override
  TestNote saveInTx(dynamic ctx, TestNote entity, {bool touch = true}) {
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

// ============ Repository Mock ============

class MockNoteRepository extends EntityRepository<TestNote> {
  MockNoteRepository({
    required MockNoteAdapter adapter,
    required EmbeddingService embeddingService,
    required ChunkingService chunkingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService,
          chunkingService: chunkingService,
          handlers: GenericHandlerFactory<TestNote>(
            embeddingService: embeddingService,
            chunkingService: chunkingService,
            versionRepository: null,
            adapter: adapter,
            edgeRepository: null,
          ).createHandlers(),
        );

  // Helper for testing non-SemanticIndexable entities
  Future<int> saveNonIndexable(TestNoteNonIndexable entity) async {
    return 0; // Not stored, just testing the repository doesn't crash
  }
}
