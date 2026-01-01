/// # Task ObjectBox Adapter Stub
///
/// This stub exists only for web platform compilation.
/// On web, this stub is imported instead of the real task_objectbox_adapter.dart
/// to prevent Dart analyzer from analyzing `dart:ffi` code (which fails on web).
///
/// The stub provides a TaskObjectBoxAdapter class that will never be instantiated
/// on web (since TaskRepository checks kIsWeb first), but allows the code to compile.

import '../../../core/persistence/persistence_adapter.dart';
import '../../../core/persistence/transaction_context.dart';
import '../entities/task.dart';

/// Stub class that provides a dummy implementation for web platform.
/// This is never instantiated at runtime on web - it exists only for compilation.
class TaskObjectBoxAdapter implements PersistenceAdapter<Task> {
  TaskObjectBoxAdapter(dynamic store) {
    throw UnsupportedError(
      'TaskObjectBoxAdapter is only available on native platforms. '
      'Web should use TaskIndexedDBAdapter.',
    );
  }

  @override
  Future<Task?> findById(String uuid) => throw UnsupportedError('Native only');

  @override
  Future<Task> getById(String uuid) => throw UnsupportedError('Native only');

  @override
  @deprecated
  Future<Task?> findByIntId(int id) => throw UnsupportedError('Native only');

  @override
  @deprecated
  Future<Task> getByIntId(int id) => throw UnsupportedError('Native only');

  @override
  Future<List<Task>> findAll() => throw UnsupportedError('Native only');

  @override
  Future<Task> save(Task entity, {bool touch = true}) =>
      throw UnsupportedError('Native only');

  @override
  Future<List<Task>> saveAll(List<Task> entities) =>
      throw UnsupportedError('Native only');

  @override
  Future<bool> delete(String uuid) => throw UnsupportedError('Native only');

  @override
  @deprecated
  Future<bool> deleteByIntId(int id) => throw UnsupportedError('Native only');

  @override
  Future<void> deleteAll(List<String> uuids) =>
      throw UnsupportedError('Native only');

  @override
  Future<void> close() => throw UnsupportedError('Native only');

  @override
  Future<int> count() => throw UnsupportedError('Native only');

  @override
  Future<List<Task>> findUnsynced() => throw UnsupportedError('Native only');

  @override
  int get indexSize => throw UnsupportedError('Native only');

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(Task entity) generateEmbedding,
  ) =>
      throw UnsupportedError('Native only');

  @override
  Future<List<Task>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) =>
      throw UnsupportedError('Native only');

  @override
  Task? findByIdInTx(TransactionContext ctx, String uuid) =>
      throw UnsupportedError('Native only');

  @override
  @deprecated
  Task? findByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnsupportedError('Native only');

  @override
  List<Task> findAllInTx(TransactionContext ctx) =>
      throw UnsupportedError('Native only');

  @override
  Task saveInTx(TransactionContext ctx, Task entity, {bool touch = true}) =>
      throw UnsupportedError('Native only');

  @override
  List<Task> saveAllInTx(TransactionContext ctx, List<Task> entities) =>
      throw UnsupportedError('Native only');

  @override
  bool deleteInTx(TransactionContext ctx, String uuid) =>
      throw UnsupportedError('Native only');

  @override
  @deprecated
  bool deleteByIntIdInTx(TransactionContext ctx, int id) =>
      throw UnsupportedError('Native only');

  @override
  void deleteAllInTx(TransactionContext ctx, List<String> uuids) =>
      throw UnsupportedError('Native only');
}
