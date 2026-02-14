import '../core/entity_repository.dart';
import '../core/persistence/persistence_adapter.dart';
import '../services/embedding_service.dart';
import 'prompt_version.dart';

class PromptVersionRepository extends EntityRepository<PromptVersion> {
  PromptVersionRepository({
    required PersistenceAdapter<PromptVersion> adapter,
    EmbeddingService? embeddingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
          handlers: [],
        );

  factory PromptVersionRepository.production({
    required PersistenceAdapter<PromptVersion> adapter,
  }) {
    return PromptVersionRepository(
      adapter: adapter,
      embeddingService: EmbeddingService.instance,
    );
  }

  Future<List<PromptVersion>> findByComponent(String componentType) async {
    final all = await findAll();
    return all
        .where((v) => v.componentType == componentType)
        .toList()
      ..sort((a, b) => b.version.compareTo(a.version));
  }

  Future<PromptVersion?> findActive(String componentType) async {
    final versions = await findByComponent(componentType);
    for (final v in versions) {
      if (v.isActive) return v;
    }
    return null;
  }

  /// Deactivate all versions for a component, then activate the given one.
  Future<void> activateVersion(String versionUuid) async {
    final target = await findByUuid(versionUuid);
    if (target == null) return;

    final others = await findByComponent(target.componentType);
    for (final other in others) {
      if (other.isActive && other.uuid != versionUuid) {
        other.isActive = false;
        await save(other);
      }
    }

    target.isActive = true;
    await save(target);
  }

  Future<int> nextVersionNumber(String componentType) async {
    final versions = await findByComponent(componentType);
    if (versions.isEmpty) return 1;
    return versions.map((v) => v.version).reduce((a, b) => a > b ? a : b) + 1;
  }
}
