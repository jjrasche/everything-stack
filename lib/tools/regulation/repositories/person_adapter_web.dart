/// Web platform Person adapter factory (IndexedDB)
///
/// This file is only imported on web platform. It creates the
/// IndexedDB-based adapter for PersonRepository.
library;

import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/person.dart';
import '../adapters/person_indexeddb_adapter.dart';

/// Create the appropriate adapter for web platform (IndexedDB)
PersistenceAdapter<Person> createPersonAdapter() {
  return _LazyIndexedDBAdapter();
}

/// Lazy adapter for web - delegates to IndexedDB on first use
class _LazyIndexedDBAdapter implements PersistenceAdapter<Person> {
  late PersistenceAdapter<Person> _delegate;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      _delegate = await PersonIndexedDBAdapter.create();
      _initialized = true;
    }
  }

  @override
  Future<Person?> findById(String uuid) async {
    await _ensureInitialized();
    return _delegate.findById(uuid);
  }

  @override
  Future<Person> getById(String uuid) async {
    await _ensureInitialized();
    return _delegate.getById(uuid);
  }

  @override
  @deprecated
  Future<Person?> findByIntId(int id) async {
    await _ensureInitialized();
    // ignore: deprecated_member_use_from_same_package
    return _delegate.findByIntId(id);
  }

  @override
  @deprecated
  Future<Person> getByIntId(int id) async {
    await _ensureInitialized();
    // ignore: deprecated_member_use_from_same_package
    return _delegate.getByIntId(id);
  }

  @override
  Future<List<Person>> findAll() async {
    await _ensureInitialized();
    return _delegate.findAll();
  }

  @override
  Future<Person> save(Person entity, {bool touch = true}) async {
    await _ensureInitialized();
    return _delegate.save(entity, touch: touch);
  }

  @override
  Future<List<Person>> saveAll(List<Person> entities) async {
    await _ensureInitialized();
    return _delegate.saveAll(entities);
  }

  @override
  Future<bool> delete(String uuid) async {
    await _ensureInitialized();
    return _delegate.delete(uuid);
  }

  @override
  @deprecated
  Future<bool> deleteByIntId(int id) async {
    await _ensureInitialized();
    // ignore: deprecated_member_use_from_same_package
    return _delegate.deleteByIntId(id);
  }

  @override
  Future<void> deleteAll(List<String> uuids) async {
    await _ensureInitialized();
    return _delegate.deleteAll(uuids);
  }

  @override
  Future<List<Person>> findUnsynced() async {
    await _ensureInitialized();
    return _delegate.findUnsynced();
  }

  @override
  Future<int> count() async {
    await _ensureInitialized();
    return _delegate.count();
  }

  @override
  Future<List<Person>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    await _ensureInitialized();
    return _delegate.semanticSearch(
      queryVector,
      limit: limit,
      minSimilarity: minSimilarity,
    );
  }

  @override
  int get indexSize {
    if (!_initialized) return 0;
    return _delegate.indexSize;
  }

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Person entity) generateEmbedding,
  ) async {
    await _ensureInitialized();
    return _delegate.rebuildIndex(generateEmbedding);
  }

  @override
  Person? findByIdInTx(TransactionContext ctx, String uuid) {
    throw UnsupportedError(
      'Synchronous findByIdInTx not supported with lazy adapter. '
      'Use async findById instead.',
    );
  }

  @override
  @deprecated
  Person? findByIntIdInTx(TransactionContext ctx, int id) {
    throw UnsupportedError(
      'Synchronous findByIntIdInTx not supported with lazy adapter. '
      'Use async findById instead.',
    );
  }

  @override
  List<Person> findAllInTx(TransactionContext ctx) {
    throw UnsupportedError(
      'Synchronous findAllInTx not supported with lazy adapter. '
      'Use async findAll instead.',
    );
  }

  @override
  Person saveInTx(TransactionContext ctx, Person entity, {bool touch = true}) {
    throw UnsupportedError(
      'Synchronous saveInTx not supported with lazy adapter. '
      'Use async save instead.',
    );
  }

  @override
  List<Person> saveAllInTx(TransactionContext ctx, List<Person> entities) {
    throw UnsupportedError(
      'Synchronous saveAllInTx not supported with lazy adapter. '
      'Use async saveAll instead.',
    );
  }

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) {
    throw UnsupportedError(
      'Synchronous deleteInTx not supported with lazy adapter. '
      'Use async delete instead.',
    );
  }

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) {
    throw UnsupportedError(
      'Synchronous deleteByIntIdInTx not supported with lazy adapter. '
      'Use async delete instead.',
    );
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) {
    throw UnsupportedError(
      'Synchronous deleteAllInTx not supported with lazy adapter. '
      'Use async deleteAll instead.',
    );
  }

  @override
  Future<void> close() async {
    if (_initialized) {
      await _delegate.close();
    }
  }
}
