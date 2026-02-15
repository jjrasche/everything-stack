import 'package:objectbox/objectbox.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../tools/regulation/entities/commitment.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/commitment_ob.dart';

class CommitmentObjectBoxAdapter
    extends BaseObjectBoxAdapter<Commitment, CommitmentOB>
    implements PersistenceAdapter<Commitment> {
  CommitmentObjectBoxAdapter(Store store) : super(store);

  @override
  CommitmentOB toOB(Commitment entity) => CommitmentOB.fromCommitment(entity);

  @override
  Commitment fromOB(CommitmentOB ob) => ob.toCommitment();

  @override
  Condition<CommitmentOB> uuidEqualsCondition(String uuid) =>
      CommitmentOB_.uuid.equals(uuid);

  @override
  Condition<CommitmentOB> syncStatusLocalCondition() =>
      CommitmentOB_.syncId.isNull();

  // ============ Commitment-Specific Query Methods ============

  /// Find all active commitments
  Future<List<Commitment>> findActive() async {
    final query = box.query(CommitmentOB_.active.equals(true)).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  /// Find all commitments for a specific person (by UUID in personIds list)
  Future<List<Commitment>> findByPerson(String personId) async {
    // Query: dbPersonIds contains personId
    // Note: Contains query on comma-separated string
    final allCommitments = await findAll();
    return allCommitments
        .where((commitment) => commitment.personIds.contains(personId))
        .toList();
  }

  /// Find commitments by interval
  Future<List<Commitment>> findByInterval(String interval) async {
    final query = box.query(CommitmentOB_.interval.equals(interval)).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }
}
