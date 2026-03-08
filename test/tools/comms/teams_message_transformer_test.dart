import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/tools/comms/teams_message_transformer.dart';

void main() {
  late TeamsMessageTransformer transformer;

  setUp(() {
    transformer = TeamsMessageTransformer();
  });

  group('TeamsMessageTransformer', () {
    test('transforms complete Graph API message to CommEvent payload', () {
      final graphMessage = {
        'id': '1234567890',
        'messageType': 'message',
        'createdDateTime': '2024-01-15T10:30:00Z',
        'from': {
          'user': {
            'id': 'user-123',
            'displayName': 'Jane Doe',
          }
        },
        'body': {
          'contentType': 'text',
          'content': 'Hello team!',
        },
        'channelIdentity': {
          'teamId': 'team-123',
          'channelId': 'channel-456',
        },
      };

      final payload = transformer.transformMessage(
        graphMessage,
        channelName: 'General',
      );

      expect(payload['source_type'], 'teams');
      expect(payload['source_id'], '1234567890');
      expect(payload['content_text'], 'Hello team!');
      expect(payload['sender_id'], 'user-123');
      expect(payload['sender_name'], 'Jane Doe');
      expect(payload['channel_id'], 'channel-456');
      expect(payload['channel_name'], 'General');
      expect(payload['content_type'], 'message');
    });

    test('strips HTML tags from message body', () {
      final graphMessage = {
        'id': 'msg-html',
        'body': {
          'contentType': 'html',
          'content': '<div><p>Hello <b>team</b>!</p></div>',
        },
      };

      final payload = transformer.transformMessage(graphMessage);

      expect(payload['content_text'], 'Hello team!');
    });

    test('handles missing from field gracefully', () {
      final graphMessage = {
        'id': 'msg-no-from',
        'body': {
          'contentType': 'text',
          'content': 'System message',
        },
      };

      final payload = transformer.transformMessage(graphMessage);

      expect(payload['sender_id'], isNull);
      expect(payload['sender_name'], isNull);
      expect(payload['content_text'], 'System message');
    });

    test('returns empty string for missing body', () {
      final graphMessage = {'id': 'msg-no-body'};

      final payload = transformer.transformMessage(graphMessage);

      expect(payload['content_text'], '');
    });

    test('defaults content_type to message when messageType absent', () {
      final graphMessage = {
        'id': 'msg-no-type',
        'body': {'contentType': 'text', 'content': 'hi'},
      };

      final payload = transformer.transformMessage(graphMessage);

      expect(payload['content_type'], 'message');
    });

    test('transforms batch of messages preserving channel name', () {
      final messages = [
        {'id': 'msg-1', 'body': {'contentType': 'text', 'content': 'First'}},
        {'id': 'msg-2', 'body': {'contentType': 'text', 'content': 'Second'}},
      ];

      final payloads =
          transformer.transformBatch(messages, channelName: 'Dev');

      expect(payloads, hasLength(2));
      expect(payloads[0]['source_id'], 'msg-1');
      expect(payloads[1]['source_id'], 'msg-2');
      expect(payloads[0]['channel_name'], 'Dev');
      expect(payloads[1]['channel_name'], 'Dev');
    });

    test('passes through text content without modification', () {
      final graphMessage = {
        'id': 'msg-text',
        'body': {
          'contentType': 'text',
          'content': 'Plain text with special chars: <>&"',
        },
      };

      final payload = transformer.transformMessage(graphMessage);

      expect(payload['content_text'], 'Plain text with special chars: <>&"');
    });
  });
}
