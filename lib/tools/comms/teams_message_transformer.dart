/// Transforms Microsoft Graph API message JSON into CommEvent payload format.
/// Pure functions: no side effects, no dependencies.
class TeamsMessageTransformer {
  /// Transform a single Graph API message to CommEvent payload.
  Map<String, dynamic> transformMessage(
    Map<String, dynamic> graphMessage, {
    String? channelName,
  }) {
    final from = graphMessage['from'] as Map<String, dynamic>?;
    final user = from?['user'] as Map<String, dynamic>?;
    final body = graphMessage['body'] as Map<String, dynamic>?;
    final channelIdentity =
        graphMessage['channelIdentity'] as Map<String, dynamic>?;

    return {
      'source_type': 'teams',
      'source_id': graphMessage['id'] as String,
      'content_text': _extractText(body),
      'sender_id': user?['id'] as String?,
      'sender_name': user?['displayName'] as String?,
      'channel_id': channelIdentity?['channelId'] as String?,
      'channel_name': channelName,
      'content_type': graphMessage['messageType'] as String? ?? 'message',
    };
  }

  /// Transform a list of Graph API messages.
  List<Map<String, dynamic>> transformBatch(
    List<dynamic> graphMessages, {
    String? channelName,
  }) {
    return graphMessages
        .map((msg) => transformMessage(
              msg as Map<String, dynamic>,
              channelName: channelName,
            ))
        .toList();
  }

  String _extractText(Map<String, dynamic>? body) {
    if (body == null) return '';
    final content = body['content'] as String? ?? '';
    final contentType = body['contentType'] as String?;
    if (contentType == 'html') {
      return _stripHtml(content);
    }
    return content;
  }

  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
}
