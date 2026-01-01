/// # MediaItemIndexedDBAdapter
///
/// IndexedDB implementation for MediaItem entities.
/// Note: idbFactory not available in idb_shim - using stub implementation.

import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/media_item.dart';

/// Stub adapter - MediaItem persistence implementation pending.
class MediaItemIndexedDBAdapter implements PersistenceAdapter<MediaItem> {
  MediaItemIndexedDBAdapter._();

  static Future<MediaItemIndexedDBAdapter> create() async {
    return MediaItemIndexedDBAdapter._();
  }

  @override
  Future<MediaItem?> findById(String uuid) async =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  Future<MediaItem> getById(String uuid) async =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  @deprecated
  Future<MediaItem?> findByIntId(int id) async =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  @deprecated
  Future<MediaItem> getByIntId(int id) async =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  Future<List<MediaItem>> findAll() async =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  Future<MediaItem> save(MediaItem entity, {bool touch = true}) async =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  Future<List<MediaItem>> saveAll(List<MediaItem> entities) async =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  Future<bool> delete(String uuid) async =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  @deprecated
  Future<bool> deleteByIntId(int id) async =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  Future<void> deleteAll(List<String> uuids) async =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  Future<List<MediaItem>> findUnsynced() async =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  Future<int> count() async =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  Future<List<MediaItem>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async =>
      throw UnimplementedError('MediaItem does not support semantic search');

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(MediaItem entity) generateEmbedding,
  ) async =>
      throw UnimplementedError('MediaItem does not support semantic search');

  @override
  MediaItem? findByIdInTx(TransactionContext ctx, String uuid) =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  @deprecated
  MediaItem? findByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  List<MediaItem> findAllInTx(TransactionContext ctx) =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  MediaItem saveInTx(TransactionContext ctx, MediaItem entity,
          {bool touch = true}) =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  List<MediaItem> saveAllInTx(
          TransactionContext ctx, List<MediaItem> entities) =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) =>
      throw UnimplementedError('MediaItem persistence not yet implemented');

  @override
  Future<void> close() async {}
}
