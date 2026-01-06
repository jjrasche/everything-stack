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

      final groqResponse = await _makeRequest(body);

      // Map Groq response → LLM domain response
      return _mapToLLMResponse(groqResponse);
    } on GroqTimeoutException catch (e) {
      rethrow;
    } on GroqRateLimitException catch (e) {
      rethrow;
    } on GroqServerException catch (e) {
      rethrow;
    } on GroqException catch (e) {
      rethrow;
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
