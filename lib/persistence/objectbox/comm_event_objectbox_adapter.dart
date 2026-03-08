import 'package:objectbox/objectbox.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../tools/comms/entities/comm_event.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/comm_event_ob.dart';

class CommEventObjectBoxAdapter
    extends BaseObjectBoxAdapter<CommEvent, CommEventOB>
    implements PersistenceAdapter<CommEvent> {
  CommEventObjectBoxAdapter(Store store) : super(store);

  @override
  CommEventOB toOB(CommEvent entity) => CommEventOB.fromCommEvent(entity);

  @override
  CommEvent fromOB(CommEventOB ob) => ob.toCommEvent();

  @override
  Condition<CommEventOB> uuidEqualsCondition(String uuid) =>
      CommEventOB_.uuid.equals(uuid);

  @override
  Condition<CommEventOB> syncStatusLocalCondition() =>
      CommEventOB_.syncId.isNull();

  // ============ Domain-specific queries ============

  Future<List<CommEvent>> findUnprocessed() async {
    final query = box.query(CommEventOB_.processedAt.isNull()).build();
    try {
      return query.find().map(fromOB).toList();
    } finally {
      query.close();
    }
  }

  Future<List<CommEvent>> findBySourceType(String sourceType) async {
    final query =
        box.query(CommEventOB_.sourceType.equals(sourceType)).build();
    try {
      return query.find().map(fromOB).toList();
    } finally {
      query.close();
    }
  }

  Future<List<CommEvent>> findActionable() async {
    final query = box
        .query(CommEventOB_.triageLevel.equals('attention') &
            CommEventOB_.dismissed.equals(false))
        .build();
    try {
      return query.find().map(fromOB).toList();
    } finally {
      query.close();
    }
  }

  Future<List<CommEvent>> findSince(DateTime cutoff) async {
    final query = box
        .query(CommEventOB_.createdAt.greaterThan(cutoff.millisecondsSinceEpoch))
        .build();
    try {
      return query.find().map(fromOB).toList();
    } finally {
      query.close();
    }
  }
}
