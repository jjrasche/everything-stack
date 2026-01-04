/// # TaskRepository
///
/// ## What it does
/// Repository for Task entities. Manages user tasks/todos.
/// Uses platform-specific adapters - ObjectBox on native, IndexedDB on web.

import '../../../core/entity_repository.dart';
import '../../../services/embedding_service.dart';
import '../entities/task.dart';

// Platform-specific adapter factory
import 'task_adapter_web.dart'
    if (dart.library.io) 'task_adapter_native.dart';

class TaskRepository extends EntityRepository<Task> {
  TaskRepository({EmbeddingService? embeddingService})
      : super(
          adapter: createTaskAdapter(),
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );
}
