/// Web platform CommitmentLog adapter factory (IndexedDB)
library;

import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/commitment_log.dart';
import '../adapters/commitment_log_indexeddb_adapter.dart';

PersistenceAdapter<CommitmentLog> createCommitmentLogAdapter() {
  return _LazyIndexedDBAdapter();
}

class _LazyIndexedDBAdapter implements PersistenceAdapter<CommitmentLog> {
  late PersistenceAdapter<CommitmentLog> _delegate;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      _delegate = await CommitmentLogIndexedDBAdapter.create();
      _initialized = true;
    }
  }

  @override
  Future<CommitmentLog?> findById(String uuid) async {
    await _ensureInitialized();
    return _delegate.findById(uuid);
  }

  @override
  Future<CommitmentLog> getById(String uuid) async {
    await _ensureInitialized();
    return _delegate.getById(uuid);
  }

  @override
  @deprecated
  Future<CommitmentLog?> findByIntId(int id) async {
    await _ensureInitialized();
    // ignore: deprecated_member_use_from_same_package
    return _delegate.findByIntId(id);
  }

  @override
  @deprecated
  Future<CommitmentLog> getByIntId(int id) async {
    await _ensureInitialized();
    // ignore: deprecated_member_use_from_same_package
    return _delegate.getByIntId(id);
  }

  @override
  Future<List<CommitmentLog>> findAll() async {
    await _ensureInitialized();
    return _delegate.findAll();
  }

  @override
  Future<CommitmentLog> save(CommitmentLog entity, {bool touch = true}) async {
    await _ensureInitialized();
    return _delegate.save(entity, touch: touch);
  }

  @override
  Future<List<CommitmentLog>> saveAll(List<CommitmentLog> entities) async {
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
  Future<List<CommitmentLog>> findUnsynced() async {
    await _ensureInitialized();
    return _delegate.findUnsynced();
  }

  @override
  Future<int> count() async {
    await _ensureInitialized();
    return _delegate.count();
  }

  @override
  Future<List<CommitmentLog>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    await _ensureInitialized();
    return _delegate.semanticSearch(queryVector,
        limit: limit, minSimilarity: minSimilarity);
  }

  @override
  int get indexSize => _initialized ? _delegate.indexSize : 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(CommitmentLog entity) generateEmbedding,
  ) async {
    await _ensureInitialized();
    return _delegate.rebuildIndex(generateEmbedding);
  }

  @override
  CommitmentLog? findByIdInTx(TransactionContext ctx, String uuid) =>
      throw UnsupportedError(
          'Synchronous operations not supported with lazy adapter');

  @override
  @deprecated
  CommitmentLog? findByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnsupportedError(
          'Synchronous operations not supported with lazy adapter');

  @override
  List<CommitmentLog> findAllInTx(TransactionContext ctx) =>
      throw UnsupportedError(
          'Synchronous operations not supported with lazy adapter');

  @override
  CommitmentLog saveInTx(TransactionContext ctx, CommitmentLog entity,
          {bool touch = true}) =>
      throw UnsupportedError(
          'Synchronous operations not supported with lazy adapter');

  @override
  List<CommitmentLog> saveAllInTx(
          TransactionContext ctx, List<CommitmentLog> entities) =>
      throw UnsupportedError(
          'Synchronous operations not supported with lazy adapter');

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) =>
      throw UnsupportedError(
          'Synchronous operations not supported with lazy adapter');

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnsupportedError(
          'Synchronous operations not supported with lazy adapter');

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) =>
      throw UnsupportedError(
          'Synchronous operations not supported with lazy adapter');

  @override
  Future<void> close() async {
    if (_initialized) await _delegate.close();
  }
}
