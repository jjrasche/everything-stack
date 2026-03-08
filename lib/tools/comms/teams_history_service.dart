import 'dart:convert';
import '../../io/patterns/request_response.dart';
import 'comm_ingestion_service.dart';
import 'entities/comm_event.dart';
import 'teams_message_transformer.dart';

/// Fetches Teams message history via Microsoft Graph API and ingests it.
/// Orchestrator: delegates to transformer and ingestion service.
class TeamsHistoryService {
  final RequestResponse _graphClient;
  final CommIngestionService _ingestionService;
  final TeamsMessageTransformer _transformer;

  TeamsHistoryService({
    required RequestResponse graphClient,
    required CommIngestionService ingestionService,
    TeamsMessageTransformer? transformer,
  })  : _graphClient = graphClient,
        _ingestionService = ingestionService,
        _transformer = transformer ?? TeamsMessageTransformer();

  /// Fetch messages from a Teams channel and ingest them.
  Future<List<CommEvent>> fetchChannelMessages({
    required String teamId,
    required String channelId,
    String? channelName,
    int limit = 50,
  }) async {
    final messages = await _fetchMessages(
      '/teams/$teamId/channels/$channelId/messages',
      limit,
    );
    final payloads = _transformer.transformBatch(
      messages,
      channelName: channelName,
    );
    return _ingestAll(payloads);
  }

  /// Fetch messages from a 1:1 or group chat and ingest them.
  Future<List<CommEvent>> fetchChatMessages({
    required String chatId,
    int limit = 50,
  }) async {
    final messages = await _fetchMessages('/chats/$chatId/messages', limit);
    final payloads = _transformer.transformBatch(messages);
    return _ingestAll(payloads);
  }

  Future<List<dynamic>> _fetchMessages(String path, int limit) async {
    final response = await _graphClient.send(RequestData(
      method: 'GET',
      path: path,
      queryParams: {'\$top': '$limit'},
    ));
    _checkResponse(response);
    final parsed = jsonDecode(response.body) as Map<String, dynamic>;
    return parsed['value'] as List<dynamic>;
  }

  Future<List<CommEvent>> _ingestAll(List<Map<String, dynamic>> payloads) async {
    final events = <CommEvent>[];
    for (final payload in payloads) {
      final event = await _ingestionService.ingest(payload);
      events.add(event);
    }
    return events;
  }

  void _checkResponse(ResponseData response) {
    if (!response.isSuccess) {
      throw GraphApiException(
        'Graph API ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }
  }
}

class GraphApiException implements Exception {
  final String message;
  final int statusCode;

  GraphApiException(this.message, {required this.statusCode});

  @override
  String toString() => 'GraphApiException: $message';
}
