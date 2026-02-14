import 'package:objectbox/objectbox.dart';
import '../../domain/prompt_version.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/prompt_version_ob.dart';

class PromptVersionObjectBoxAdapter
    extends BaseObjectBoxAdapter<PromptVersion, PromptVersionOB>
    implements PersistenceAdapter<PromptVersion> {
  PromptVersionObjectBoxAdapter(Store store) : super(store);

  @override
  PromptVersionOB toOB(PromptVersion entity) =>
      PromptVersionOB.fromPromptVersion(entity);

  @override
  PromptVersion fromOB(PromptVersionOB ob) => ob.toPromptVersion();

  @override
  Condition<PromptVersionOB> uuidEqualsCondition(String uuid) =>
      PromptVersionOB_.uuid.equals(uuid);

  @override
  Condition<PromptVersionOB> syncStatusLocalCondition() =>
      PromptVersionOB_.syncStatus.notEquals(0);

  Future<List<PromptVersion>> findByComponent(String componentType) async {
    final query = box
        .query(PromptVersionOB_.componentType.equals(componentType))
        .order(PromptVersionOB_.version, flags: Order.descending)
        .build();
    try {
      return query.find().map(fromOB).toList();
    } finally {
      query.close();
    }
  }

  Future<PromptVersion?> findActive(String componentType) async {
    final condition = PromptVersionOB_.componentType
        .equals(componentType)
        .and(PromptVersionOB_.isActive.equals(true));
    final query = box.query(condition).build();
    try {
      final ob = query.findFirst();
      return ob != null ? fromOB(ob) : null;
    } finally {
      query.close();
    }
  }
}
