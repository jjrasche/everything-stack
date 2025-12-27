/// # ChannelObjectBoxAdapter
///
/// Stub implementation for ObjectBox on mobile/desktop platforms.
/// Full implementation pending: Channel entities need @Entity decorators.
///
/// Use ChannelIndexedDBAdapter on web platform for full functionality.

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/channel.dart';

/// Stub adapter - Channel persistence not yet available on native platforms.
class ChannelObjectBoxAdapter implements PersistenceAdapter<Channel> {
  final Store _store;

  ChannelObjectBoxAdapter(this._store);

  @override
  Future<Channel?> findById(String uuid) async =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  Future<Channel> getById(String uuid) async =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  @deprecated
  Future<Channel?> findByIntId(int id) async =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  @deprecated
  Future<Channel> getByIntId(int id) async =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  Future<List<Channel>> findAll() async =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  Future<Channel> save(Channel entity, {bool touch = true}) async =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  Future<List<Channel>> saveAll(List<Channel> entities) async =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  Future<bool> delete(String uuid) async =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  @deprecated
  Future<bool> deleteByIntId(int id) async =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  Future<void> deleteAll(List<String> uuids) async =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  Future<List<Channel>> findUnsynced() async =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  Future<int> count() async =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  Future<List<Channel>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async =>
      throw UnimplementedError('Channel does not support semantic search');

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Channel entity) generateEmbedding,
  ) async =>
      throw UnimplementedError('Channel does not support semantic search');

  @override
  Channel? findByIdInTx(TransactionContext ctx, String uuid) =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  @deprecated
  Channel? findByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  List<Channel> findAllInTx(TransactionContext ctx) =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  Channel saveInTx(TransactionContext ctx, Channel entity, {bool touch = true}) =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  List<Channel> saveAllInTx(TransactionContext ctx, List<Channel> entities) =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) =>
      throw UnimplementedError('Channel persistence not yet available on native platforms');

  @override
  Future<void> close() async {}
}
