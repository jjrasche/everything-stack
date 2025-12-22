/// # PersonalityRepository
///
/// ## What it does
/// Repository for Personality entities. Manages trainable agent personas.
///
/// ## CRITICAL for Phase 2
/// ContextManager calls getActive() to load the active personality's
/// attention patterns (namespace thresholds, tool selection weights).
///
/// ## Usage
/// ```dart
/// final adapter = PersonalityObjectBoxAdapter(store);
/// final repo = PersonalityRepository(adapter: adapter);
///
/// // Get active personality (CRITICAL for Phase 2)
/// final active = await repo.getActive();
///
/// // Switch active personality
/// await repo.setActive('personality_uuid');
/// ```

import '../core/entity_repository.dart';
import '../core/persistence/persistence_adapter.dart';
import '../services/embedding_service.dart';
import 'personality.dart';

class PersonalityRepository extends EntityRepository<Personality> {
  PersonalityRepository({
    required PersistenceAdapter<Personality> adapter,
    EmbeddingService? embeddingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  // ============ Personality-specific queries ============

  /// Get the currently active personality
  /// CRITICAL: ContextManager calls this to load attention patterns
  /// Returns null if no personality is active (should never happen in production)
  Future<Personality?> getActive() async {
    final all = await findAll();
    try {
      final active = all.firstWhere((p) => p.isActive);
      // Load embedded adaptation states from JSON
      active.loadAfterRead();
      return active;
    } catch (e) {
      return null;
    }
  }

  /// Set a personality as active (deactivates all others)
  Future<void> setActive(String uuid) async {
    final all = await findAll();

    // Deactivate all
    for (final personality in all) {
      if (personality.isActive) {
        personality.isActive = false;
        await save(personality);
      }
    }

    // Activate target
    final target = await findByUuid(uuid);
    if (target != null) {
      target.isActive = true;
      await save(target);
    }
  }

  /// Find personality by name
  Future<Personality?> findByName(String name) async {
    final all = await findAll();
    try {
      final personality = all.firstWhere((p) => p.name == name);
      personality.loadAfterRead();
      return personality;
    } catch (e) {
      return null;
    }
  }

  /// Get all personalities ordered by name
  Future<List<Personality>> findAllOrdered() async {
    final all = await findAll();
    // Load embedded states for all
    for (final p in all) {
      p.loadAfterRead();
    }
    return all..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Override save to prepare embedded states
  @override
  Future<int> save(Personality entity) async {
    // Serialize embedded adaptation states to JSON
    entity.prepareForSave();
    return super.save(entity);
  }

  /// Override findByUuid to load embedded states
  @override
  Future<Personality?> findByUuid(String uuid) async {
    final personality = await super.findByUuid(uuid);
    if (personality != null) {
      personality.loadAfterRead();
    }
    return personality;
  }

  /// Override findAll to load embedded states
  @override
  Future<List<Personality>> findAll() async {
    final all = await super.findAll();
    for (final p in all) {
      p.loadAfterRead();
    }
    return all;
  }
}
