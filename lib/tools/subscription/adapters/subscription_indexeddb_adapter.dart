/// # SubscriptionIndexedDBAdapter
///
/// IndexedDB implementation of PersistenceAdapter for Subscription entities.
/// Note: idbFactory not available in idb_shim - using stub implementation.

import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/subscription.dart';

/// Stub adapter - Subscription persistence implementation pending.
class SubscriptionIndexedDBAdapter implements PersistenceAdapter<Subscription> {
  SubscriptionIndexedDBAdapter._();

  static Future<SubscriptionIndexedDBAdapter> create() async {
    return SubscriptionIndexedDBAdapter._();
  }

  @override
  Future<Subscription?> findById(int id) async =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<Subscription> getById(int id) async =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<Subscription?> findByUuid(String uuid) async =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<Subscription> getByUuid(String uuid) async =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<List<Subscription>> findAll() async =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<Subscription> save(Subscription entity, {bool touch = true}) async =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<List<Subscription>> saveAll(List<Subscription> entities) async =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<bool> delete(int id) async =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<bool> deleteByUuid(String uuid) async =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<void> deleteAll(List<int> ids) async =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<List<Subscription>> findUnsynced() async =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<int> count() async =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<List<Subscription>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async =>
      throw UnimplementedError('Subscription does not support semantic search');

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Subscription entity) generateEmbedding,
  ) async =>
      throw UnimplementedError('Subscription does not support semantic search');

  @override
  Subscription? findByIdInTx(TransactionContext ctx, int id) =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Subscription? findByUuidInTx(TransactionContext ctx, String uuid) =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  List<Subscription> findAllInTx(TransactionContext ctx) =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Subscription saveInTx(TransactionContext ctx, Subscription entity, {bool touch = true}) =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  List<Subscription> saveAllInTx(TransactionContext ctx, List<Subscription> entities) =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  bool deleteInTx(TransactionContext ctx, int id) =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  bool deleteByUuidInTx(TransactionContext ctx, String uuid) =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  void deleteAllInTx(TransactionContext ctx, List<int> ids) =>
      throw UnimplementedError('Subscription persistence not yet implemented');

  @override
  Future<void> close() async {}
}
