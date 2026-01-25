/// Web platform Commitment adapter factory (IndexedDB)
library;

import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/commitment.dart';
import '../adapters/commitment_indexeddb_adapter.dart';

PersistenceAdapter<Commitment> createCommitmentAdapter() {
  return _LazyIndexedDBAdapter();
}

class _LazyIndexedDBAdapter implements PersistenceAdapter<Commitment> {
  late PersistenceAdapter<Commitment> _delegate;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      _delegate = await CommitmentIndexedDBAdapter.create();
      _initialized = true;
    }
  }

  @override
  Future<Commitment?> findById(String uuid) async {
    await _ensureInitialized();
    return _delegate.findById(uuid);
  }

  @override
  Future<Commitment> getById(String uuid) async {
    await _ensureInitialized();
    return _delegate.getById(uuid);
  }

  @override
  @deprecated
  Future<Commitment?> findByIntId(int id) async {
    await _ensureInitialized();
    // ignore: deprecated_member_use_from_same_package
    return _delegate.findByIntId(id);
  }

  @override
  @deprecated
  Future<Commitment> getByIntId(int id) async {
    await _ensureInitialized();
    // ignore: deprecated_member_use_from_same_package
    return _delegate.getByIntId(id);
  }

  @override
  Future<List<Commitment>> findAll() async {
    await _ensureInitialized();
    return _delegate.findAll();
  }

  @override
  Future<Commitment> save(Commitment entity, {bool touch = true}) async {
    await _ensureInitialized();
    return _delegate.save(entity, touch: touch);
  }

  @override
  Future<List<Commitment>> saveAll(List<Commitment> entities) async {
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
  Future<List<Commitment>> findUnsynced() async {
    await _ensureInitialized();
    return _delegate.findUnsynced();
  }

  @override
  Future<int> count() async {
    await _ensureInitialized();
    return _delegate.count();
  }

  @override
  Future<List<Commitment>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    await _ensureInitialized();
    return _delegate.semanticSearch(queryVector, limit: limit, minSimilarity: minSimilarity);
  }

  @override
  int get indexSize => _initialized ? _delegate.indexSize : 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Commitment entity) generateEmbedding,
  ) async {
    await _ensureInitialized();
    return _delegate.rebuildIndex(generateEmbedding);
  }

  @override
  Commitment? findByIdInTx(TransactionContext ctx, String uuid) =>
      throw UnsupportedError('Synchronous operations not supported with lazy adapter');

  @override
  @deprecated
  Commitment? findByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnsupportedError('Synchronous operations not supported with lazy adapter');

  @override
  List<Commitment> findAllInTx(TransactionContext ctx) =>
      throw UnsupportedError('Synchronous operations not supported with lazy adapter');

  @override
  Commitment saveInTx(TransactionContext ctx, Commitment entity, {bool touch = true}) =>
      throw UnsupportedError('Synchronous operations not supported with lazy adapter');

  @override
  List<Commitment> saveAllInTx(TransactionContext ctx, List<Commitment> entities) =>
      throw UnsupportedError('Synchronous operations not supported with lazy adapter');

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) =>
      throw UnsupportedError('Synchronous operations not supported with lazy adapter');

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnsupportedError('Synchronous operations not supported with lazy adapter');

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) =>
      throw UnsupportedError('Synchronous operations not supported with lazy adapter');

  @override
  Future<void> close() async {
    if (_initialized) await _delegate.close();
  }
}
