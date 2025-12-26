/// # InvocationRepository Implementation
///
/// Concrete implementation of InvocationRepository using a persistence adapter.
/// Supports both real persistence (ObjectBox/IndexedDB) and in-memory mode for testing.

import 'package:everything_stack_template/domain/invocation.dart';
import 'invocation_repository.dart';
import 'persistence/persistence_adapter.dart';

/// Simple in-memory adapter for testing
class _InMemoryInvocationAdapter {
  final Map<String, Invocation> _store = {};

  Future<Invocation?> findByUuid(String uuid) async => _store[uuid];

  Future<Invocation> save(Invocation entity) async {
    if (entity.uuid.isEmpty) {
      entity.uuid = DateTime.now().millisecondsSinceEpoch.toString();
    }
    _store[entity.uuid] = entity;
    return entity;
  }

  Future<bool> deleteByUuid(String uuid) async {
    return _store.remove(uuid) != null;
  }

  Future<List<Invocation>> findAll() async => _store.values.toList();

  Future<void> close() async {}
}

class InvocationRepositoryImpl implements InvocationRepository<Invocation> {
  final dynamic _adapter; // PersistenceAdapter<Invocation> or _InMemoryInvocationAdapter
  final bool _isInMemory;

  InvocationRepositoryImpl({required dynamic adapter})
      : _adapter = adapter,
        _isInMemory = adapter is _InMemoryInvocationAdapter;

  /// Create an in-memory repository for testing
  factory InvocationRepositoryImpl.inMemory() {
    return InvocationRepositoryImpl(
      adapter: _InMemoryInvocationAdapter(),
    );
  }

  /// Find invocation by ID (UUID)
  @override
  Future<Invocation?> findById(String id) async {
    if (_isInMemory) {
      return await (_adapter as _InMemoryInvocationAdapter).findByUuid(id);
    } else {
      return await (_adapter as PersistenceAdapter<Invocation>).findByUuid(id);
    }
  }

  /// Find all invocations for a specific turn
  @override
  Future<List<Invocation>> findByTurn(String turnId) async {
    final all = await findAll();
    return all.where((inv) => inv.metadata?['turnId'] == turnId).toList();
  }

  /// Find all invocations of a specific context type
  @override
  Future<List<Invocation>> findByContextType(String contextType) async {
    final all = await findAll();
    return all
        .where((inv) =>
            inv.metadata?['contextType'] == contextType ||
            inv.input?['contextType'] == contextType)
        .toList();
  }

  /// Find invocations by multiple IDs
  @override
  Future<List<Invocation>> findByIds(List<String> ids) async {
    final results = <Invocation>[];
    for (final id in ids) {
      final inv = await findById(id);
      if (inv != null) {
        results.add(inv);
      }
    }
    return results;
  }

  /// Save (create or update) an invocation
  @override
  Future<Invocation> save(Invocation invocation) async {
    if (_isInMemory) {
      return await (_adapter as _InMemoryInvocationAdapter).save(invocation);
    } else {
      await (_adapter as PersistenceAdapter<Invocation>).save(invocation);
      return invocation;
    }
  }

  /// Delete an invocation by ID (UUID)
  @override
  Future<bool> delete(String id) async {
    if (_isInMemory) {
      return await (_adapter as _InMemoryInvocationAdapter).deleteByUuid(id);
    } else {
      return await (_adapter as PersistenceAdapter<Invocation>).deleteByUuid(id);
    }
  }

  /// Delete all invocations for a turn
  @override
  Future<int> deleteByTurn(String turnId) async {
    final invocations = await findByTurn(turnId);
    int count = 0;
    for (final inv in invocations) {
      if (await delete(inv.uuid)) {
        count++;
      }
    }
    return count;
  }

  /// Find all invocations
  @override
  Future<List<Invocation>> findAll() async {
    if (_isInMemory) {
      return await (_adapter as _InMemoryInvocationAdapter).findAll();
    } else {
      return await (_adapter as PersistenceAdapter<Invocation>).findAll();
    }
  }
}
