import 'dart:convert';
import 'dart:io';

import '../lib/services/types/chat_client.dart';
import '../lib/services/types/message.dart';

/// Direct Groq HTTP chat client for CLI scripts. No Flutter dependency.
class CliChatClient implements ChatClient {
  final String _apiKey;
  final String _model;
  final String _baseUrl;
  final HttpClient _httpClient;

  CliChatClient({
    required String apiKey,
    String model = 'llama-3.1-8b-instant',
    String baseUrl = 'https://api.groq.com/openai/v1',
  })  : _apiKey = apiKey,
        _model = model,
        _baseUrl = baseUrl,
        _httpClient = HttpClient();

  @override
  Future<String> chat({
    required String eventId,
    required List<Message> messages,
  }) async {
    final body = jsonEncode({
      'model': _model,
      'messages': messages.map((m) => {'role': m.role, 'content': m.content}).toList(),
      'temperature': 0.3,
      'max_tokens': 4096,
    });

    final uri = Uri.parse('$_baseUrl/chat/completions');
    final request = await _httpClient.postUrl(uri);
    request.headers.set('Authorization', 'Bearer $_apiKey');
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.add(utf8.encode(body));

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode == 429 || response.statusCode >= 500) {
      final delay = response.statusCode == 429 ? 2 : 5;
      await Future.delayed(Duration(seconds: delay));
      return chat(eventId: eventId, messages: messages);
    }

    if (response.statusCode != 200) {
      throw Exception('Groq API error ${response.statusCode}: $responseBody');
    }

    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    final choices = data['choices'] as List;
    final content = (choices.first as Map<String, dynamic>)['message']['content'] as String;
    return content;
  }

  void close() {
    _httpClient.close();
  }
}

/// Load GROQ_API_KEY from .env file.
String loadGroqApiKey() {
  final file = File('.env');
  if (!file.existsSync()) {
    print('Missing .env file with GROQ_API_KEY');
    exit(1);
  }
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.startsWith('GROQ_API_KEY=')) {
      return trimmed.substring('GROQ_API_KEY='.length).trim();
    }
  }
  print('GROQ_API_KEY not found in .env');
  exit(1);
}
