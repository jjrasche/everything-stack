import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/tools/comms/entities/comm_event.dart';
import 'package:everything_stack_template/tools/comms/repositories/comm_event_repository.dart';
import 'package:everything_stack_template/persistence/objectbox/comm_event_objectbox_adapter.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/objectbox.g.dart';

void main() {
  late Store store;
  late CommEventRepository repo;

  setUp(() async {
    store = await openStore(directory: 'test_db_comms_${DateTime.now().millisecondsSinceEpoch}');
    final adapter = CommEventObjectBoxAdapter(store);
    repo = CommEventRepository.withAdapter(adapter);
  });

  tearDown(() {
    store.close();
  });

  group('CommEventRepository', () {
    test('saves and retrieves by uuid', () async {
      final event = CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-001',
        contentText: 'Please review the PR',
        channelName: 'Data Team General',
        senderName: 'Dave Wilson',
      );

      await repo.save(event);
      expect(event.id, greaterThan(0));

      final found = await repo.findByUuid(event.uuid);
      expect(found, isNotNull);
      expect(found!.sourceType, 'teams');
      expect(found.sourceId, 'msg-001');
      expect(found.contentText, 'Please review the PR');
      expect(found.channelName, 'Data Team General');
      expect(found.senderName, 'Dave Wilson');
    });

    test('findUnprocessed returns only events without processedAt', () async {
      final processed = CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-001',
        contentText: 'Old message',
      );
      processed.markProcessed(triageLevel: 'noise');
      await repo.save(processed);

      final unprocessed = CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-002',
        contentText: 'New message',
      );
      await repo.save(unprocessed);

      final results = await repo.findUnprocessed();
      expect(results, hasLength(1));
      expect(results.first.sourceId, 'msg-002');
    });

    test('findBySourceType filters correctly', () async {
      await repo.save(CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-001',
        contentText: 'Teams message',
      ));
      await repo.save(CommEvent(
        sourceType: 'gitlab',
        sourceId: 'pipeline-001',
        contentText: 'Pipeline failed',
      ));
      await repo.save(CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-002',
        contentText: 'Another Teams message',
      ));

      final teamsEvents = await repo.findBySourceType('teams');
      expect(teamsEvents, hasLength(2));
      expect(teamsEvents.every((e) => e.sourceType == 'teams'), isTrue);

      final gitlabEvents = await repo.findBySourceType('gitlab');
      expect(gitlabEvents, hasLength(1));
      expect(gitlabEvents.first.contentText, 'Pipeline failed');
    });

    test('findActionable returns only attention + not dismissed', () async {
      final noise = CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-001',
        contentText: 'Random chatter',
      );
      noise.markProcessed(triageLevel: 'noise');
      await repo.save(noise);

      final fyi = CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-002',
        contentText: 'FYI update',
      );
      fyi.markProcessed(triageLevel: 'fyi');
      await repo.save(fyi);

      final actionable = CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-003',
        contentText: 'Review this PR',
      );
      actionable.markProcessed(triageLevel: 'attention');
      await repo.save(actionable);

      final dismissedAction = CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-004',
        contentText: 'Old action item',
      );
      dismissedAction.markProcessed(triageLevel: 'attention');
      dismissedAction.dismiss();
      await repo.save(dismissedAction);

      final results = await repo.findActionable();
      expect(results, hasLength(1));
      expect(results.first.sourceId, 'msg-003');
    });

    test('deletes by uuid', () async {
      final event = CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-001',
        contentText: 'To be deleted',
      );
      await repo.save(event);

      final deleted = await repo.deleteByUuid(event.uuid);
      expect(deleted, isTrue);

      final found = await repo.findByUuid(event.uuid);
      expect(found, isNull);
    });

    test('findSince returns events after timestamp', () async {
      final old = CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-old',
        contentText: 'Old event',
      );
      old.createdAt = DateTime.now().subtract(const Duration(hours: 2));
      await repo.save(old);

      final cutoff = DateTime.now().subtract(const Duration(hours: 1));

      final recent = CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-recent',
        contentText: 'Recent event',
      );
      await repo.save(recent);

      final results = await repo.findSince(cutoff);
      expect(results, hasLength(1));
      expect(results.first.sourceId, 'msg-recent');
    });
  });
}
