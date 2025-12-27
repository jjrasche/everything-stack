/// # MediaItemObjectBoxAdapter
///
/// Stub implementation for ObjectBox on mobile/desktop platforms.
/// Full implementation pending: MediaItem entities need @Entity decorators.
///
/// Use MediaItemIndexedDBAdapter on web platform for full functionality.

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/media_item.dart';

/// Stub adapter - MediaItem persistence not yet available on native platforms.
class MediaItemObjectBoxAdapter implements PersistenceAdapter<MediaItem> {
  final Store _store;

  MediaItemObjectBoxAdapter(this._store);

  @override
  Future<MediaItem?> findById(String uuid) async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  Future<MediaItem> getById(String uuid) async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  @deprecated
  Future<MediaItem?> findByIntId(int id) async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  @deprecated
  Future<MediaItem> getByIntId(int id) async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  Future<List<MediaItem>> findAll() async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  Future<MediaItem> save(MediaItem entity, {bool touch = true}) async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  Future<List<MediaItem>> saveAll(List<MediaItem> entities) async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  Future<bool> delete(String uuid) async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  @deprecated
  Future<bool> deleteByIntId(int id) async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  Future<void> deleteAll(List<String> uuids) async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  Future<List<MediaItem>> findUnsynced() async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  Future<int> count() async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  Future<List<MediaItem>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(MediaItem entity) generateEmbedding,
  ) async =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  MediaItem? findByIdInTx(TransactionContext ctx, String uuid) =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  @deprecated
  MediaItem? findByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  List<MediaItem> findAllInTx(TransactionContext ctx) =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  MediaItem saveInTx(TransactionContext ctx, MediaItem entity, {bool touch = true}) =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  List<MediaItem> saveAllInTx(TransactionContext ctx, List<MediaItem> entities) =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) =>
      throw UnimplementedError('MediaItem persistence not yet available on native platforms');

  @override
  Future<void> close() async {}
}
