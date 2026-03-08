import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/io/patterns/request_response.dart';
import 'package:everything_stack_template/tools/comms/teams_history_service.dart';
import 'package:everything_stack_template/tools/comms/comm_ingestion_service.dart';
import 'package:everything_stack_template/tools/comms/repositories/comm_event_repository.dart';
import 'package:everything_stack_template/persistence/objectbox/comm_event_objectbox_adapter.dart';
import 'package:everything_stack_template/objectbox.g.dart';

/// Fake RequestResponse that returns canned responses by path.
class FakeGraphClient implements RequestResponse {
  @override
  final String id = 'fake-graph';

  final Map<String, ResponseData> _responses = {};

  void stubResponse(String path, ResponseData response) {
    _responses[path] = response;
  }

  @override
  Future<ResponseData> send(RequestData request) async {
    final response = _responses[request.path];
    if (response == null) {
      return ResponseData(
        statusCode: 404,
        headers: {},
        body: '{"error": {"message": "Not found: ${request.path}"}}',
      );
    }
    return response;
  }

  @override
  void dispose() {}
}

void main() {
  late Store store;
  late CommEventRepository repo;
  late CommIngestionService ingestionService;
  late FakeGraphClient graphClient;
  late TeamsHistoryService historyService;

  setUp(() async {
    store = await openStore(
      directory: 'test_db_teams_${DateTime.now().millisecondsSinceEpoch}',
    );
    final adapter = CommEventObjectBoxAdapter(store);
    repo = CommEventRepository.withAdapter(adapter);
    ingestionService = CommIngestionService(repository: repo);
    graphClient = FakeGraphClient();
    historyService = TeamsHistoryService(
      graphClient: graphClient,
      ingestionService: ingestionService,
    );
  });

  tearDown(() {
    ingestionService.dispose();
    graphClient.dispose();
    store.close();
  });

  group('TeamsHistoryService', () {
    test('fetches channel messages and persists as CommEvents', () async {
      graphClient.stubResponse(
        '/teams/team-1/channels/chan-1/messages',
        ResponseData(
          statusCode: 200,
          headers: {},
          body: jsonEncode({
            'value': [
              {
                'id': 'msg-001',
                'messageType': 'message',
                'from': {
                  'user': {'id': 'u1', 'displayName': 'Alice'},
                },
                'body': {'contentType': 'text', 'content': 'Hello'},
                'channelIdentity': {
                  'teamId': 'team-1',
                  'channelId': 'chan-1',
                },
              },
              {
                'id': 'msg-002',
                'messageType': 'message',
                'from': {
                  'user': {'id': 'u2', 'displayName': 'Bob'},
                },
                'body': {'contentType': 'text', 'content': 'Hi Alice'},
                'channelIdentity': {
                  'teamId': 'team-1',
                  'channelId': 'chan-1',
                },
              },
            ],
          }),
        ),
      );

      final events = await historyService.fetchChannelMessages(
        teamId: 'team-1',
        channelId: 'chan-1',
        channelName: 'General',
      );

      expect(events, hasLength(2));
      expect(events[0].sourceType, 'teams');
      expect(events[0].sourceId, 'msg-001');
      expect(events[0].contentText, 'Hello');
      expect(events[0].senderName, 'Alice');
      expect(events[1].senderName, 'Bob');

      final persisted = await repo.findAll();
      expect(persisted, hasLength(2));
    });

    test('throws GraphApiException on non-2xx response', () async {
      graphClient.stubResponse(
        '/teams/t/channels/c/messages',
        ResponseData(
          statusCode: 403,
          headers: {},
          body: '{"error": {"message": "Forbidden"}}',
        ),
      );

      expect(
        () => historyService.fetchChannelMessages(teamId: 't', channelId: 'c'),
        throwsA(isA<GraphApiException>()),
      );
    });

    test('fetches chat messages and persists as CommEvents', () async {
      graphClient.stubResponse(
        '/chats/chat-1/messages',
        ResponseData(
          statusCode: 200,
          headers: {},
          body: jsonEncode({
            'value': [
              {
                'id': 'chat-msg-001',
                'messageType': 'message',
                'from': {
                  'user': {'id': 'u1', 'displayName': 'Carol'},
                },
                'body': {'contentType': 'text', 'content': 'Quick question'},
              },
            ],
          }),
        ),
      );

      final events = await historyService.fetchChatMessages(chatId: 'chat-1');

      expect(events, hasLength(1));
      expect(events.first.contentText, 'Quick question');
      expect(events.first.senderName, 'Carol');

      final persisted = await repo.findAll();
      expect(persisted, hasLength(1));
    });

    test('channel name propagates to all ingested events', () async {
      graphClient.stubResponse(
        '/teams/t1/channels/c1/messages',
        ResponseData(
          statusCode: 200,
          headers: {},
          body: jsonEncode({
            'value': [
              {'id': 'm1', 'body': {'contentType': 'text', 'content': 'A'}},
              {'id': 'm2', 'body': {'contentType': 'text', 'content': 'B'}},
            ],
          }),
        ),
      );

      final events = await historyService.fetchChannelMessages(
        teamId: 't1',
        channelId: 'c1',
        channelName: 'Engineering',
      );

      expect(events[0].channelName, 'Engineering');
      expect(events[1].channelName, 'Engineering');
    });
  });
}
