import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/tools/comms/entities/comm_event.dart';

void main() {
  group('CommEvent', () {
    test('creates with required fields and sensible defaults', () {
      final event = CommEvent(
        sourceType: 'teams',
        sourceId: 'msg-123',
        contentText: 'Hey, can you review this PR?',
      );

      expect(event.sourceType, 'teams');
      expect(event.sourceId, 'msg-123');
      expect(event.contentText, 'Hey, can you review this PR?');
      expect(event.uuid, isNotEmpty);
      expect(event.triageLevel, isNull);
      expect(event.processedAt, isNull);
      expect(event.isDismissed, isFalse);
      expect(event.isProcessed, isFalse);
      expect(event.contentType, 'message');
    });

    test('creates with all optional fields', () {
      final event = CommEvent(
        sourceType: 'gitlab',
        sourceId: 'pipeline-456',
        channelId: 'project-789',
        channelName: 'analytics-pipeline',
        senderId: 'user-101',
        senderName: 'Dave Wilson',
        contentText: 'Pipeline #456 failed on staging',
        contentType: 'pipeline_status',
        rawPayload: '{"id": 456, "status": "failed"}',
      );

      expect(event.sourceType, 'gitlab');
      expect(event.channelId, 'project-789');
      expect(event.channelName, 'analytics-pipeline');
      expect(event.senderId, 'user-101');
      expect(event.senderName, 'Dave Wilson');
      expect(event.contentType, 'pipeline_status');
      expect(event.rawPayload, '{"id": 456, "status": "failed"}');
    });

    group('serialization', () {
      test('round-trips through JSON with all fields', () {
        final event = CommEvent(
          sourceType: 'teams',
          sourceId: 'msg-123',
          channelId: 'ch-456',
          channelName: 'Data Team General',
          senderId: 'user-789',
          senderName: 'Dave Wilson',
          contentText: 'Hey, can you review the Dagster PR?',
          contentType: 'mention',
          rawPayload: '{"full": "payload"}',
        );

        final json = event.toJson();
        final restored = CommEvent.fromJson(json);

        expect(restored.sourceType, event.sourceType);
        expect(restored.sourceId, event.sourceId);
        expect(restored.channelId, event.channelId);
        expect(restored.channelName, event.channelName);
        expect(restored.senderId, event.senderId);
        expect(restored.senderName, event.senderName);
        expect(restored.contentText, event.contentText);
        expect(restored.contentType, event.contentType);
        expect(restored.rawPayload, event.rawPayload);
      });

      test('round-trips through JSON with minimal fields', () {
        final event = CommEvent(
          sourceType: 'sms',
          sourceId: 'sms-001',
          contentText: 'Running late',
        );

        final json = event.toJson();
        final restored = CommEvent.fromJson(json);

        expect(restored.sourceType, 'sms');
        expect(restored.sourceId, 'sms-001');
        expect(restored.contentText, 'Running late');
        expect(restored.channelId, isNull);
        expect(restored.senderName, isNull);
      });

      test('preserves triage state through JSON', () {
        final event = CommEvent(
          sourceType: 'teams',
          sourceId: 'msg-123',
          contentText: 'Review needed',
        );
        event.markProcessed(triageLevel: 'attention');

        final json = event.toJson();
        final restored = CommEvent.fromJson(json);

        expect(restored.triageLevel, 'attention');
        expect(restored.processedAt, isNotNull);
        expect(restored.isProcessed, isTrue);
      });

      test('preserves dismissed state through JSON', () {
        final event = CommEvent(
          sourceType: 'teams',
          sourceId: 'msg-123',
          contentText: 'FYI update',
        );
        event.dismiss();

        final json = event.toJson();
        final restored = CommEvent.fromJson(json);

        expect(restored.isDismissed, isTrue);
      });
    });

    group('lifecycle', () {
      test('markProcessed sets processedAt and triageLevel', () {
        final event = CommEvent(
          sourceType: 'teams',
          sourceId: 'msg-123',
          contentText: 'Hello',
        );

        expect(event.isProcessed, isFalse);

        event.markProcessed(triageLevel: 'fyi');

        expect(event.isProcessed, isTrue);
        expect(event.processedAt, isNotNull);
        expect(event.triageLevel, 'fyi');
      });

      test('markProcessed calls touch', () {
        final event = CommEvent(
          sourceType: 'teams',
          sourceId: 'msg-123',
          contentText: 'Hello',
        );
        final beforeUpdate = event.updatedAt;

        // Small delay to ensure timestamp differs
        event.markProcessed(triageLevel: 'noise');

        expect(event.updatedAt.millisecondsSinceEpoch,
            greaterThanOrEqualTo(beforeUpdate.millisecondsSinceEpoch));
      });

      test('dismiss marks event as dismissed', () {
        final event = CommEvent(
          sourceType: 'teams',
          sourceId: 'msg-123',
          contentText: 'Hello',
        );

        expect(event.isDismissed, isFalse);
        event.dismiss();
        expect(event.isDismissed, isTrue);
      });
    });

    group('computed properties', () {
      test('isActionable is false when untriaged', () {
        final event = CommEvent(
          sourceType: 'teams',
          sourceId: 'msg-123',
          contentText: 'Hello',
        );

        expect(event.isActionable, isFalse);
      });

      test('isActionable is false for noise', () {
        final event = CommEvent(
          sourceType: 'teams',
          sourceId: 'msg-123',
          contentText: 'Hello',
        );
        event.markProcessed(triageLevel: 'noise');

        expect(event.isActionable, isFalse);
      });

      test('isActionable is true for attention', () {
        final event = CommEvent(
          sourceType: 'teams',
          sourceId: 'msg-123',
          contentText: 'Review this PR please',
        );
        event.markProcessed(triageLevel: 'attention');

        expect(event.isActionable, isTrue);
      });

      test('isActionable is false when dismissed even if attention', () {
        final event = CommEvent(
          sourceType: 'teams',
          sourceId: 'msg-123',
          contentText: 'Review this PR please',
        );
        event.markProcessed(triageLevel: 'attention');
        event.dismiss();

        expect(event.isActionable, isFalse);
      });

      test('toEncoderSourceText returns contentText', () {
        final event = CommEvent(
          sourceType: 'teams',
          sourceId: 'msg-123',
          contentText: 'We decided to use PostgreSQL for analytics.',
        );

        expect(event.toEncoderSourceText(), event.contentText);
      });
    });
  });
}
