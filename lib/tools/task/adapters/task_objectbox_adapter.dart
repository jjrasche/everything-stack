/// # TaskObjectBoxAdapter
///
/// Stub implementation for ObjectBox on mobile/desktop platforms.
/// Full implementation pending: Task entities need @Entity decorators.

import 'package:objectbox/objectbox.dart';
import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/task.dart';

/// Stub adapter - Task persistence available on web via IndexedDB only.
class TaskObjectBoxAdapter implements PersistenceAdapter<Task> {
  final Store _store;

  TaskObjectBoxAdapter(this._store);

  @override
  Future<Task?> findById(int id) async =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<Task> getById(int id) async =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<Task?> findByUuid(String uuid) async =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<Task> getByUuid(String uuid) async =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<List<Task>> findAll() async =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<Task> save(Task entity, {bool touch = true}) async =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<List<Task>> saveAll(List<Task> entities) async =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<bool> delete(int id) async =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<bool> deleteByUuid(String uuid) async =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<void> deleteAll(List<int> ids) async =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<List<Task>> findUnsynced() async =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<int> count() async =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<List<Task>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async =>
      throw UnimplementedError('Task does not support semantic search');

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Task entity) generateEmbedding,
  ) async =>
      throw UnimplementedError('Task does not support semantic search');

  @override
  Task? findByIdInTx(TransactionContext ctx, int id) =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Task? findByUuidInTx(TransactionContext ctx, String uuid) =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  List<Task> findAllInTx(TransactionContext ctx) =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Task saveInTx(TransactionContext ctx, Task entity, {bool touch = true}) =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  List<Task> saveAllInTx(TransactionContext ctx, List<Task> entities) =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  bool deleteInTx(TransactionContext ctx, int id) =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  bool deleteByUuidInTx(TransactionContext ctx, String uuid) =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  void deleteAllInTx(TransactionContext ctx, List<int> ids) =>
      throw UnimplementedError('Task persistence not yet available on native platforms');

  @override
  Future<void> close() async {}
}
