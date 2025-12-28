/// # InvocationObjectBoxAdapter Stub for Web Platform
///
/// This file is a stub that provides a no-op implementation for Web platform
/// where ObjectBox is not available.
/// Real implementation uses ObjectBox on native platforms.

library;

import '../../bootstrap/objectbox_stub.dart' if (dart.library.io) 'package:objectbox/objectbox.dart';
import '../../core/invocation_repository.dart';
import '../../domain/invocation.dart' as domain_invocation;

/// Stub InvocationObjectBoxAdapter for Web platform
class InvocationObjectBoxAdapter implements InvocationRepository<domain_invocation.Invocation> {
  final Store store;

  InvocationObjectBoxAdapter(this.store);

  @override
  Future<void> delete(String uuid) async {}

  @override
  Future<domain_invocation.Invocation?> findByUuid(String uuid) async => null;

  @override
  Future<List<domain_invocation.Invocation>> findAll() async => [];

  @override
  Future<String> save(domain_invocation.Invocation entity) async => entity.uuid;

  @override
  Future<List<domain_invocation.Invocation>> findByTurn(String turnId) async => [];

  @override
  Future<List<domain_invocation.Invocation>> findByContextType(String contextType) async => [];

  @override
  Future<List<domain_invocation.Invocation>> findByIds(List<String> ids) async => [];

  @override
  Future<int> deleteByTurn(String turnId) async => 0;
}
