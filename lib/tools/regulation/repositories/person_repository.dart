/// # PersonRepository
///
/// ## What it does
/// Repository for Person entities. Manages people involved in regulation tracking.
/// Uses platform-specific adapters - ObjectBox on native, IndexedDB on web.
///
/// ## Usage
/// ```dart
/// final repo = PersonRepository();
///
/// // Find by name
/// final person = await repo.findByName('Alice');
///
/// // Find by role
/// final parents = await repo.findByRole('parent');
/// ```

import '../../../core/entity_repository.dart';
import '../../../services/embedding_service.dart';
import '../entities/person_stub.dart'
    if (dart.library.io) '../entities/person.dart';

// Platform-specific adapter factory
import 'person_adapter_web.dart'
    if (dart.library.io) 'person_adapter_native.dart';

class PersonRepository extends EntityRepository<Person> {
  PersonRepository({EmbeddingService? embeddingService})
      : super(
          adapter: createPersonAdapter(),
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  // ============ Person-specific queries ============

  /// Find person by name (case-insensitive)
  Future<Person?> findByName(String name) async {
    final all = await findAll();
    try {
      return all.firstWhere(
        (person) => person.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Find all people with a specific role
  Future<List<Person>> findByRole(String role) async {
    final all = await findAll();
    return all.where((person) => person.role == role).toList();
  }
}
