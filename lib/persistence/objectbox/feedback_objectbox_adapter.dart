/// # FeedbackObjectBoxAdapter

import 'package:objectbox/objectbox.dart';
import '../../domain/feedback.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/feedback_ob.dart';

class FeedbackObjectBoxAdapter extends BaseObjectBoxAdapter<Feedback, FeedbackOB> {
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
}
