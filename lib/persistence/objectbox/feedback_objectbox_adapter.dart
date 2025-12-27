/// # FeedbackObjectBoxAdapter

import 'package:objectbox/objectbox.dart';
import '../../core/feedback_repository.dart';
import '../../domain/feedback.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/feedback_ob.dart';

class FeedbackObjectBoxAdapter extends BaseObjectBoxAdapter<Feedback, FeedbackOB>
    implements FeedbackRepository {
  FeedbackObjectBoxAdapter(Store store) : super(store);

  @override
  FeedbackOB toOB(Feedback entity) => FeedbackOB.fromFeedback(entity);

  @override
  Feedback fromOB(FeedbackOB ob) => ob.toFeedback();

  @override
  Condition<FeedbackOB> uuidEqualsCondition(String uuid) =>
      FeedbackOB_.uuid.equals(uuid);

  @override
  Condition<FeedbackOB> syncStatusLocalCondition() =>
      FeedbackOB_.syncId.notNull();

  // ============ FeedbackRepository Implementation ============

  @override
  Future<List<Feedback>> findByInvocationId(String invocationId) async {
    final query = box
        .query(FeedbackOB_.invocationId.equals(invocationId))
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Feedback>> findByInvocationIds(List<String> invocationIds) async {
    final allFeedback = await findAll();
    return allFeedback
        .where((f) => invocationIds.contains(f.invocationId))
        .toList();
  }

  @override
  Future<List<Feedback>> findByTurn(String turnId) async {
    final query = box
        .query(FeedbackOB_.turnId.equals(turnId))
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Feedback>> findByTurnAndComponent(
    String turnId,
    String componentType,
  ) async {
    final query = box
        .query(FeedbackOB_.turnId.equals(turnId)
            .and(FeedbackOB_.componentType.equals(componentType)))
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Feedback>> findByContextType(String contextType) async {
    final query = box
        .query(FeedbackOB_.componentType.equals(contextType))
        .build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Feedback>> findAllConversational() async {
    final query = box.query(FeedbackOB_.turnId.notNull()).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<List<Feedback>> findAllBackground() async {
    final query = box.query(FeedbackOB_.turnId.isNull()).build();
    try {
      final obList = query.find();
      return obList.map((ob) => fromOB(ob)).toList();
    } finally {
      query.close();
    }
  }

  @override
  Future<int> deleteByTurn(String turnId) async {
    final query = box.query(FeedbackOB_.turnId.equals(turnId)).build();
    try {
      return query.remove();
    } finally {
      query.close();
    }
  }
}
