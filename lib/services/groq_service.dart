/// # GroqService
///
/// ## What it does
/// LLM service using Groq's OpenAI-compatible API.
/// Handles namespace selection and tool calling.
///
/// ## Key features
/// - OpenAI-compatible chat completions
/// - Tool calling (function calling)
/// - Error handling: rate limits, timeouts, server errors
/// - Exponential backoff on retries
///
/// ## Usage
/// ```dart
/// final groq = GroqService(apiKey: 'gsk_...');
/// final response = await groq.chat(
///   model: 'llama-3.3-70b-versatile',
///   messages: [{'role': 'user', 'content': 'Hello'}],
///   tools: [...],
/// );
/// ```

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'llm_service.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/llm_invocation_repository.dart';

class GroqService extends LLMService {
  final String apiKey;
  final String baseUrl;
  final Duration timeout;
  final int maxRetries;
  final LLMInvocationRepository _llmInvocationRepository;

  bool _isReady = false;

  GroqService({
    required this.apiKey,
    required LLMInvocationRepository llmInvocationRepository,
    this.baseUrl = 'https://api.groq.com/openai/v1',
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
  }) : _llmInvocationRepository = llmInvocationRepository;

  // ============================================================================
  // LLMService Implementation
  // ============================================================================

  @override
  Future<void> initialize() async {
    // Groq doesn't require initialization, but validate API key exists
    if (apiKey.isEmpty) {
      throw LLMException('Groq API key is empty');
    }
    _isReady = true;
  }

  @override
  Stream<String> chat({
    required List<Message> history,
    required String userMessage,
    String? systemPrompt,
    int? maxTokens,
  }) async* {
    // TODO: Implement streaming chat for UI
    // For now, throw not implemented
    throw LLMException('Groq streaming chat not implemented yet');
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
      throw LLMTimeoutException(e.message, cause: e);
    } on GroqRateLimitException catch (e) {
      throw LLMRateLimitException(e.message, cause: e);
    } on GroqServerException catch (e) {
      throw LLMServerException(e.message, cause: e);
    } on GroqException catch (e) {
      throw LLMException(e.message, cause: e);
    }
  }

  @override
  void dispose() {
    _isReady = false;
  }

  @override
  bool get isReady => _isReady;

  // ============================================================================
  // Trainable Implementation
  // ============================================================================

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    if (invocation is! LLMInvocation) {
      throw ArgumentError(
          'Expected LLMInvocation, got ${invocation.runtimeType}');
    }
    await _llmInvocationRepository.save(invocation);
    return invocation.uuid;
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    // TODO: Implement LLM learning from feedback
    // For MVP: placeholder - full implementation in Phase 3
    print('GroqService.trainFromFeedback() - TODO');
  }

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async {
    // TODO: Implement returning current LLM adaptation state
    // For MVP: placeholder - full implementation in Phase 3
    return {'status': 'baseline'};
  }

  @override
  Widget buildFeedbackUI(String invocationId) {
    // TODO: Implement LLM feedback UI
    // For MVP: placeholder - full implementation in Phase 3
    return Center(child: Text('LLM Feedback UI (TODO)'));
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
              params: groqCall.function.parsedArguments, // Parse JSON here
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
