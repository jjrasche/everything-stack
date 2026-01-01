/// # SubscriptionObjectBoxAdapter
///
/// Stub implementation for ObjectBox on mobile/desktop platforms.
/// Full implementation pending: Subscription entities need @Entity decorators.

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/subscription.dart';

/// Stub adapter - Subscription persistence available on web via IndexedDB only.
class SubscriptionObjectBoxAdapter implements PersistenceAdapter<Subscription> {
  final Store _store;

  SubscriptionObjectBoxAdapter(this._store);

  @override
  Future<Subscription?> findById(String uuid) async => throw UnimplementedError(
      'Subscription persistence not yet available on native platforms');

  @override
  Future<Subscription> getById(String uuid) async => throw UnimplementedError(
      'Subscription persistence not yet available on native platforms');

  @override
  @deprecated
  Future<Subscription?> findByIntId(int id) async => throw UnimplementedError(
      'Subscription persistence not yet available on native platforms');

  @override
  @deprecated
  Future<Subscription> getByIntId(int id) async => throw UnimplementedError(
      'Subscription persistence not yet available on native platforms');

  @override
  Future<List<Subscription>> findAll() async => throw UnimplementedError(
      'Subscription persistence not yet available on native platforms');

  @override
  Future<Subscription> save(Subscription entity, {bool touch = true}) async =>
      throw UnimplementedError(
          'Subscription persistence not yet available on native platforms');

  @override
  Future<List<Subscription>> saveAll(List<Subscription> entities) async =>
      throw UnimplementedError(
          'Subscription persistence not yet available on native platforms');

  @override
  Future<bool> delete(String uuid) async => throw UnimplementedError(
      'Subscription persistence not yet available on native platforms');

  @override
  @deprecated
  Future<bool> deleteByIntId(int id) async => throw UnimplementedError(
      'Subscription persistence not yet available on native platforms');

  @override
  Future<void> deleteAll(List<String> uuids) async => throw UnimplementedError(
      'Subscription persistence not yet available on native platforms');

  @override
  Future<List<Subscription>> findUnsynced() async => throw UnimplementedError(
      'Subscription persistence not yet available on native platforms');

  @override
  Future<int> count() async => throw UnimplementedError(
      'Subscription persistence not yet available on native platforms');

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
  Subscription? findByIdInTx(TransactionContext ctx, String uuid) =>
      throw UnimplementedError(
          'Subscription persistence not yet available on native platforms');

  @override
  @deprecated
  Subscription? findByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnimplementedError(
          'Subscription persistence not yet available on native platforms');

  @override
  List<Subscription> findAllInTx(TransactionContext ctx) =>
      throw UnimplementedError(
          'Subscription persistence not yet available on native platforms');

  @override
  Subscription saveInTx(TransactionContext ctx, Subscription entity,
          {bool touch = true}) =>
      throw UnimplementedError(
          'Subscription persistence not yet available on native platforms');

  @override
  List<Subscription> saveAllInTx(
          TransactionContext ctx, List<Subscription> entities) =>
      throw UnimplementedError(
          'Subscription persistence not yet available on native platforms');

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) =>
      throw UnimplementedError(
          'Subscription persistence not yet available on native platforms');

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnimplementedError(
          'Subscription persistence not yet available on native platforms');

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) =>
      throw UnimplementedError(
          'Subscription persistence not yet available on native platforms');

  @override
  Future<void> close() async {}
}
