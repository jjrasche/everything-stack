/// # CommitmentRepository
///
/// ## What it does
/// Repository for Commitment entities. Manages commitment tracking.
/// Uses platform-specific adapters - ObjectBox on native, IndexedDB on web.
///
/// ## Usage
/// ```dart
/// final repo = CommitmentRepository();
///
/// // Find active commitments
/// final active = await repo.findActive();
///
/// // Find by person
/// final personCommitments = await repo.findByPerson(personUuid);
/// ```

import '../../../core/entity_repository.dart';
import '../../../services/embedding_service.dart';
import '../entities/commitment_stub.dart'
    if (dart.library.io) '../entities/commitment.dart';

// Platform-specific adapter factory
import 'commitment_adapter_web.dart'
    if (dart.library.io) 'commitment_adapter_native.dart';

class CommitmentRepository extends EntityRepository<Commitment> {
  CommitmentRepository({EmbeddingService? embeddingService})
      : super(
          adapter: createCommitmentAdapter(),
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  // ============ Commitment-specific queries ============

  /// Find all active commitments
  Future<List<Commitment>> findActive() async {
    final all = await findAll();
    return all.where((commitment) => commitment.active).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Find all commitments for a specific person (by UUID in personIds list)
  Future<List<Commitment>> findByPerson(String personId) async {
    final all = await findAll();
    return all
        .where((commitment) => commitment.personIds.contains(personId))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Find commitments by interval
  Future<List<Commitment>> findByInterval(String interval) async {
    final all = await findAll();
    return all
        .where((commitment) => commitment.interval == interval)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
}
