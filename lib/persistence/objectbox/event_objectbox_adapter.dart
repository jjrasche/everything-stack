/// # EventObjectBoxAdapter

import 'package:objectbox/objectbox.dart';
import '../../domain/event.dart';
import '../../objectbox.g.dart';
import 'base_objectbox_adapter.dart';
import 'wrappers/event_ob.dart';

class EventObjectBoxAdapter extends BaseObjectBoxAdapter<Event, EventOB> {
  EventObjectBoxAdapter(Store store) : super(store);

  @override
  EventOB toOB(Event entity) => EventOB.fromEvent(entity);

  @override
  Event fromOB(EventOB ob) => ob.toEvent();

  @override
  Condition<EventOB> uuidEqualsCondition(String uuid) =>
      EventOB_.uuid.equals(uuid);

  @override
  Condition<EventOB> syncStatusLocalCondition() => EventOB_.syncId.notNull();
}
