import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
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

  @override
  Set<String> get supportedPlatforms => {
        'android',
        'ios',
        'macos',
        'windows',
        'linux',
        'web',
        // Pure Dart HTTP - works everywhere
      };

  /// Groq's hard token limit for available models
  @override
  int get maxTokensLimit => 8192;

  /// Available Groq models for model selection.
  /// These are the production models available via the Groq API.
  @override
  List<String> get availableModels => const [
        'llama-3.3-70b-versatile', // Best for function calling
        'llama-3.1-8b-instant', // Fast, good for simple tasks
        // Note: mixtral-8x7b-32768 was decommissioned by Groq (Jan 2025)
      ];

  @override
  Future<LLMInvocationOutput> chat({
    required List<Message> messages,
    required double temperature,
    required double topP,
    required double frequencyPenalty,
    required double presencePenalty,
    required int maxTokens,
  }) async {
    try {
      final messagesList = <Map<String, dynamic>>[
        ...messages.map((m) => {'role': m.role, 'content': m.content}),
      ];

      final body = {
        'model': model,
        'messages': messagesList,
        'temperature': temperature,
        'top_p': topP,
        'frequency_penalty': frequencyPenalty,
        'presence_penalty': presencePenalty,
        'max_tokens': maxTokens,
      };

      debugPrint('[Groq.chat] model=$model, messages=${messagesList.length}');

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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        int tokensUsed = 0;
        if (data['usage'] is Map<String, dynamic>) {
          tokensUsed = (data['usage']['total_tokens'] as num?)?.toInt() ?? 0;
        }

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

  @override
  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    try {
      final body = {
        'model': model,
        'messages': messages,
        'temperature': temperature,
        if (tools != null && tools.isNotEmpty)
          'tools': tools.map((t) => t.toJson()).toList(),
        if (maxTokens != null) 'max_tokens': maxTokens,
      };

      debugPrint('[Groq.chatWithTools] model=$model, messages=${messages.length}');

      final groqResponse = await _makeRequest(body);

      return _mapToLLMResponse(groqResponse);
    } on GroqTimeoutException {
      rethrow;
    } on GroqRateLimitException {
      rethrow;
    } on GroqServerException {
      rethrow;
    } on GroqException {
      rethrow;
    }
  }

  @override
  Stream<String> chatStream({
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    int? maxTokens,
  }) async* {
    final body = {
      'model': model,
      'messages': messages,
      'temperature': temperature,
      'stream': true,
      if (maxTokens != null) 'max_tokens': maxTokens,
    };

    debugPrint('[Groq.chatStream] model=$model, messages=${messages.length}');

    final request = http.Request(
      'POST',
      Uri.parse('$baseUrl/chat/completions'),
    );
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(body);

    try {
      final client = http.Client();
      try {
        final response = await client.send(request).timeout(timeout);

        if (response.statusCode != 200) {
          final body = await response.stream.bytesToString();
          throw GroqException('Stream error ${response.statusCode}: $body');
        }

        // Parse SSE: each line starts with "data: " followed by JSON
        // Stream ends with "data: [DONE]"
        String buffer = '';
        await for (final chunk in response.stream.transform(utf8.decoder)) {
          buffer += chunk;

          while (buffer.contains('\n')) {
            final newlineIndex = buffer.indexOf('\n');
            final line = buffer.substring(0, newlineIndex).trim();
            buffer = buffer.substring(newlineIndex + 1);

            if (line.isEmpty) continue;
            if (line == 'data: [DONE]') return;
            if (!line.startsWith('data: ')) continue;

            final jsonStr = line.substring(6); // Remove "data: " prefix
            try {
              final data = jsonDecode(jsonStr) as Map<String, dynamic>;
              final choices = data['choices'] as List?;
              if (choices != null && choices.isNotEmpty) {
                final delta =
                    (choices[0] as Map<String, dynamic>)['delta'] as Map<String, dynamic>?;
                final content = delta?['content'] as String?;
                if (content != null && content.isNotEmpty) {
                  yield content;
                }
              }
            } catch (e) {
              debugPrint('GroqImplementer.chatStream: SSE parse error: $e');
            }
          }
        }
      } finally {
        client.close();
      }
    } on TimeoutException {
      throw GroqTimeoutException('Stream timeout after ${timeout.inSeconds}s');
    } on GroqException {
      rethrow;
    } catch (e) {
      throw GroqException('Stream failed: $e');
    }
  }

  /// Map Groq response to provider-agnostic LLM response
  LLMResponse _mapToLLMResponse(GroqResponse groqResp) {
    return LLMResponse(
      id: groqResp.id,
      content: groqResp.content,
      toolCalls: groqResp.toolCalls?.map((groqCall) {
            return LLMToolCall(
              id: groqCall.id,
              toolName: groqCall.function.name,
              params: groqCall.function.parsedArguments,
            );
          }).toList() ??
          [],
      tokensUsed: groqResp.usage.totalTokens,
    );
  }

  /// Make request with retry logic
  Future<GroqResponse> _makeRequest(
    Map<String, dynamic> body, {
    int attempt = 1,
  }) async {
    try {
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

      if (response.statusCode == 200) {
        return GroqResponse.fromJson(jsonDecode(response.body));
      } else if (response.statusCode == 429) {
        // Rate limit - retry with exponential backoff
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 1000 * (1 << attempt));
          debugPrint('[Groq] 429 rate limit, retry $attempt/${maxRetries} '
              'after ${delay.inMilliseconds}ms, model=${body['model']}');
          await Future.delayed(delay);
          return _makeRequest(body, attempt: attempt + 1);
        }
        throw GroqRateLimitException(
            'Rate limit exceeded after $maxRetries retries');
      } else if (response.statusCode >= 500 && response.statusCode < 600) {
        // Server error - retry once
        if (attempt < 2) {
          await Future.delayed(const Duration(seconds: 2));
          return _makeRequest(body, attempt: attempt + 1);
        }
        throw GroqServerException('Server error: ${response.statusCode}');
      } else {
        throw GroqException(
          'API error: ${response.statusCode} - ${response.body}',
        );
      }
    } on TimeoutException {
      throw GroqTimeoutException('Request timeout after ${timeout.inSeconds}s');
    } catch (e) {
      if (e is GroqException) rethrow;
      throw GroqException('Request failed: $e');
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

// ============ Response Classes ============

/// Response from Groq API
class GroqResponse {
  final String id;
  final List<GroqChoice> choices;
  final GroqUsage usage;
  final String model;

  GroqResponse({
    required this.id,
    required this.choices,
    required this.usage,
    required this.model,
  });

  factory GroqResponse.fromJson(Map<String, dynamic> json) {
    return GroqResponse(
      id: json['id'] as String,
      choices: (json['choices'] as List)
          .map((c) => GroqChoice.fromJson(c as Map<String, dynamic>))
          .toList(),
      usage: GroqUsage.fromJson(json['usage'] as Map<String, dynamic>),
      model: json['model'] as String,
    );
  }

  /// Get the first choice (most common case)
  GroqChoice get firstChoice => choices.first;

  /// Get tool calls from first choice
  List<GroqToolCall>? get toolCalls => firstChoice.message.toolCalls;

  /// Get text content from first choice
  String? get content => firstChoice.message.content;
}

class GroqChoice {
  final int index;
  final GroqMessage message;
  final String finishReason;

  GroqChoice({
    required this.index,
    required this.message,
    required this.finishReason,
  });

  factory GroqChoice.fromJson(Map<String, dynamic> json) {
    return GroqChoice(
      index: json['index'] as int,
      message: GroqMessage.fromJson(json['message'] as Map<String, dynamic>),
      finishReason: json['finish_reason'] as String,
    );
  }

  /// Did the LLM want to call tools?
  bool get wantsToolCall => finishReason == 'tool_calls';
}

class GroqMessage {
  final String role;
  final String? content;
  final List<GroqToolCall>? toolCalls;

  GroqMessage({
    required this.role,
    this.content,
    this.toolCalls,
  });

  factory GroqMessage.fromJson(Map<String, dynamic> json) {
    return GroqMessage(
      role: json['role'] as String,
      content: json['content'] as String?,
      toolCalls: json['tool_calls'] != null
          ? (json['tool_calls'] as List)
              .map((tc) => GroqToolCall.fromJson(tc as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}

class GroqToolCall {
  final String id;
  final String type;
  final GroqFunction function;

  GroqToolCall({
    required this.id,
    required this.type,
    required this.function,
  });

  factory GroqToolCall.fromJson(Map<String, dynamic> json) {
    return GroqToolCall(
      id: json['id'] as String,
      type: json['type'] as String,
      function: GroqFunction.fromJson(json['function'] as Map<String, dynamic>),
    );
  }
}

class GroqFunction {
  final String name;
  final String arguments;

  GroqFunction({
    required this.name,
    required this.arguments,
  });

  factory GroqFunction.fromJson(Map<String, dynamic> json) {
    return GroqFunction(
      name: json['name'] as String,
      arguments: json['arguments'] as String,
    );
  }

  /// Parse arguments as JSON
  Map<String, dynamic> get parsedArguments {
    return jsonDecode(arguments) as Map<String, dynamic>;
  }
}

class GroqUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  GroqUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  factory GroqUsage.fromJson(Map<String, dynamic> json) {
    return GroqUsage(
      promptTokens: json['prompt_tokens'] as int,
      completionTokens: json['completion_tokens'] as int,
      totalTokens: json['total_tokens'] as int,
    );
  }
}
