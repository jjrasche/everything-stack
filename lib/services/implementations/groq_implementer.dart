/// # GroqImplementer
///
/// Dumb API wrapper for Groq LLM API.
/// Handles authentication, retries, timeouts.
/// No state management - just calls API and returns response.

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

import 'llm_implementer.dart';
import '../types/message.dart';
import '../types/llm_types.dart';

class GroqImplementer implements LLMImplementer {
  final String apiKey;
  final String model;
  final String baseUrl;
  final Duration timeout;
  final int maxRetries;

  GroqImplementer({
    required this.apiKey,
    this.model = 'llama-3.3-70b-versatile',
    this.baseUrl = 'https://api.groq.com/openai/v1',
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
  });

  @override
  String get implementerName => 'groq';

  /// Groq's hard token limit for available models
  @override
  int get maxTokensLimit => 8192;

  @override
  Future<LLMInvocationOutput> chat({
    required List<Message> messages,
    required double temperature,
    String? systemPrompt,
  }) async {
    try {
      // Build message list for API
      final messagesList = <Map<String, dynamic>>[
        if (systemPrompt != null)
          {'role': 'system', 'content': systemPrompt},
        ...messages.map((m) => {'role': m.role, 'content': m.content}),
      ];

      // Build request body
      final body = {
        'model': model,
        'messages': messagesList,
        'temperature': temperature,
        'max_tokens': maxTokensLimit,
      };

      // Time the API call
      final stopwatch = Stopwatch()..start();
      final response = await http
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
      stopwatch.stop();

      final latencyMs = stopwatch.elapsedMilliseconds.toDouble();

      // Handle response
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Extract tokens used
        int tokensUsed = 0;
        if (data['usage'] is Map<String, dynamic>) {
          tokensUsed = (data['usage']['total_tokens'] as num?)?.toInt() ?? 0;
        }

        // Extract response text
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final firstChoice = choices.first as Map<String, dynamic>;
          final message = firstChoice['message'] as Map<String, dynamic>?;
          final content = message?['content'] as String?;
          if (content != null) {
            return LLMInvocationOutput(
              response: content,
              tokensUsed: tokensUsed,
              latencyMs: latencyMs,
            );
          }
        }
        throw GroqException('No content in API response');
      } else if (response.statusCode == 429) {
        // Rate limit
        throw GroqRateLimitException(
          'Rate limit exceeded: ${response.body}',
        );
      } else if (response.statusCode >= 500 && response.statusCode < 600) {
        throw GroqServerException(
          'Server error ${response.statusCode}: ${response.body}',
        );
      } else {
        throw GroqException(
          'API error ${response.statusCode}: ${response.body}',
        );
      }
    } on TimeoutException {
      throw GroqTimeoutException('Request timeout after ${timeout.inSeconds}s');
    } on GroqException {
      rethrow;
    } catch (e) {
      throw GroqException('Unexpected error: $e');
    }
  }
}

// ============ Exceptions ============

class GroqException implements Exception {
  final String message;
  GroqException(this.message);

  @override
  String toString() => 'GroqException: $message';
}

class GroqRateLimitException extends GroqException {
  GroqRateLimitException(super.message);
}

class GroqServerException extends GroqException {
  GroqServerException(super.message);
}

class GroqTimeoutException extends GroqException {
  GroqTimeoutException(super.message);
}
