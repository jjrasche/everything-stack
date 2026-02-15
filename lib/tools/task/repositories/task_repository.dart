
import '../../../core/entity_repository.dart';
import '../../../services/embedding_service.dart';
import '../entities/task.dart';

// Platform-specific adapter factory
import 'task_adapter_web.dart' if (dart.library.io) 'task_adapter_native.dart';

class TaskRepository extends EntityRepository<Task> {
  TaskRepository({EmbeddingService? embeddingService})
      : super(
          adapter: createTaskAdapter(),
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );
}
