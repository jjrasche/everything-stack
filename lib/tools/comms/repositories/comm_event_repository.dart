
import '../../../core/entity_repository.dart';
import '../../../services/embedding_service.dart';
import '../../../persistence/objectbox/comm_event_objectbox_adapter.dart';
import '../entities/comm_event_stub.dart'
    if (dart.library.io) '../entities/comm_event.dart';

class CommEventRepository extends EntityRepository<CommEvent> {
  final CommEventObjectBoxAdapter _commAdapter;

  CommEventRepository.withAdapter(CommEventObjectBoxAdapter adapter)
      : _commAdapter = adapter,
        super(
          adapter: adapter,
          embeddingService: EmbeddingService.instance,
        );

  // ============ Domain-specific queries ============

  Future<List<CommEvent>> findUnprocessed() =>
      _commAdapter.findUnprocessed();

  Future<List<CommEvent>> findBySourceType(String sourceType) =>
      _commAdapter.findBySourceType(sourceType);

  Future<List<CommEvent>> findActionable() =>
      _commAdapter.findActionable();

  Future<List<CommEvent>> findSince(DateTime cutoff) =>
      _commAdapter.findSince(cutoff);
}
