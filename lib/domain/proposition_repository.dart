import '../core/entity_repository.dart';
import '../core/persistence/persistence_adapter.dart';
import '../services/embedding_service.dart';
import 'proposition.dart';

class PropositionRepository extends EntityRepository<Proposition> {
  PropositionRepository({
    required PersistenceAdapter<Proposition> adapter,
    EmbeddingService? embeddingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
          handlers: [],
        );

  Future<List<Proposition>> findByEpisode(String episodeId) async {
    final all = await findAll();
    return all
        .where((p) => p.sourceEpisodeId == episodeId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<List<Proposition>> findActive() async {
    final all = await findAll();
    return all.where((p) => p.isActive).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<Proposition>> findByStatus(String status) async {
    final all = await findAll();
    return all.where((p) => p.status == status).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> supersede(String oldUuid, String newUuid) async {
    final old = await findByUuid(oldUuid);
    if (old != null) {
      old.status = 'superseded';
      old.supersededBy = newUuid;
      await save(old);
    }
  }

  Future<void> archive(String uuid) async {
    final prop = await findByUuid(uuid);
    if (prop != null) {
      prop.status = 'archived';
      await save(prop);
    }
  }
}
