import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/tools/comms/entities/comm_event.dart';
import 'package:everything_stack_template/tools/comms/repositories/comm_event_repository.dart';
import 'package:everything_stack_template/tools/comms/comm_ingestion_service.dart';
import 'package:everything_stack_template/persistence/objectbox/comm_event_objectbox_adapter.dart';
import 'package:everything_stack_template/objectbox.g.dart';

void main() {
  late Store store;
  late CommEventRepository repo;
  late CommIngestionService service;

  setUp(() async {
    store = await openStore(
        directory:
            'test_db_ingestion_${DateTime.now().millisecondsSinceEpoch}');
    final adapter = CommEventObjectBoxAdapter(store);
    repo = CommEventRepository.withAdapter(adapter);
    service = CommIngestionService(repository: repo);
  });

  tearDown(() {
    store.close();
  });

  group('CommIngestionService', () {
    test('ingests a Teams webhook payload into a CommEvent', () async {
      final payload = {
        'source_type': 'teams',
        'source_id': 'msg-123',
        'channel_id': 'ch-456',
        'channel_name': 'Data Team General',
        'sender_id': 'user-789',
        'sender_name': 'Dave Wilson',
        'content_text': 'Can you review the Dagster PR before standup?',
        'content_type': 'mention',
      };

      final event = await service.ingest(payload);

      expect(event.id, greaterThan(0));
      expect(event.sourceType, 'teams');
      expect(event.sourceId, 'msg-123');
      expect(event.channelName, 'Data Team General');
      expect(event.senderName, 'Dave Wilson');
      expect(event.contentText,
          'Can you review the Dagster PR before standup?');
      expect(event.contentType, 'mention');
      expect(event.isProcessed, isFalse);

      // Verify persisted
      final found = await repo.findByUuid(event.uuid);
      expect(found, isNotNull);
      expect(found!.contentText, event.contentText);
    });

    test('stores raw payload JSON alongside parsed fields', () async {
      final payload = {
        'source_type': 'gitlab',
        'source_id': 'pipeline-789',
        'content_text': 'Pipeline #789 failed',
        'extra_field': 'preserved in raw',
      };

      final event = await service.ingest(payload);

      expect(event.rawPayload, isNotNull);
      final raw = jsonDecode(event.rawPayload!);
      expect(raw['extra_field'], 'preserved in raw');
    });

    test('rejects payload missing required fields', () async {
      final incomplete = {
        'source_type': 'teams',
        // missing source_id and content_text
      };

      expect(
        () => service.ingest(incomplete),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('publishes to event stream on ingest', () async {
      final events = <CommEvent>[];
      service.events.listen(events.add);

      await service.ingest({
        'source_type': 'teams',
        'source_id': 'msg-001',
        'content_text': 'Hello',
      });

      await service.ingest({
        'source_type': 'gitlab',
        'source_id': 'pipeline-001',
        'content_text': 'Build passed',
      });

      // Allow stream to deliver
      await Future.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(events[0].sourceType, 'teams');
      expect(events[1].sourceType, 'gitlab');
    });

    test('handles minimal payload with defaults', () async {
      final event = await service.ingest({
        'source_type': 'sms',
        'source_id': 'sms-001',
        'content_text': 'Running late',
      });

      expect(event.contentType, 'message');
      expect(event.channelId, isNull);
      expect(event.senderName, isNull);
    });
  });
}
