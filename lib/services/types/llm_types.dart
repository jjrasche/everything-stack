/// # LLM Service Type Definitions
///
/// Typed payloads for LLM service adaptation, invocations, and feedback.
/// Provides compile-time safety, IDE autocomplete, and self-documentation.
///
/// Note: LLMAdaptationData renamed to InferenceAdaptationData for clarity.

import 'dart:convert';
import 'package:everything_stack_template/core/adaptation_data.dart';
import 'message.dart';

/// Learned inference preferences (per implementer, per user).
/// These are adaptable parameters that training adjusts.
class InferenceAdaptationData extends AdaptationData {
  /// How "creative" vs "rigid" the LLM should be (0.0-2.0).
  /// Higher = more creative/risky, Lower = more factual/conservative.
  final double temperature;

  /// Nucleus sampling threshold (0.0-1.0).
  /// Only tokens with cumulative probability <= topP are considered.
  final double topP;

  /// Frequency penalty (-2.0 to 2.0).
  /// Positive values decrease likelihood of repeating tokens based on frequency.
  final double frequencyPenalty;

  /// Presence penalty (-2.0 to 2.0).
  /// Positive values decrease likelihood of repeating any token that appeared.
  final double presencePenalty;

  /// Maximum tokens to generate.
  /// Implementer-specific bounds (Groq: 8K, Claude: 200K).
  final int maxTokens;

  InferenceAdaptationData({
    required this.temperature,
    required this.topP,
    required this.frequencyPenalty,
    required this.presencePenalty,
    required this.maxTokens,
  });

  /// Default adaptation state (untrained).
  factory InferenceAdaptationData.defaults() => InferenceAdaptationData(
    temperature: 0.7,
    topP: 1.0,
    frequencyPenalty: 0.0,
    presencePenalty: 0.0,
    maxTokens: 1024,
  );

  /// Deserialize from JSON.
  factory InferenceAdaptationData.fromJson(Map<String, dynamic> json) => InferenceAdaptationData(
    temperature: json['temperature'] as double? ?? 0.7,
    topP: json['topP'] as double? ?? 1.0,
    frequencyPenalty: json['frequencyPenalty'] as double? ?? 0.0,
    presencePenalty: json['presencePenalty'] as double? ?? 0.0,
    maxTokens: json['maxTokens'] as int? ?? 1024,
  );

  /// Serialize to JSON string.
  @override
  String toJson() => jsonEncode({
    'temperature': temperature,
    'topP': topP,
    'frequencyPenalty': frequencyPenalty,
    'presencePenalty': presencePenalty,
    'maxTokens': maxTokens,
  });

  /// Create a copy with modified fields (for GP optimizer updates).
  InferenceAdaptationData copyWith({
    double? temperature,
    double? topP,
    double? frequencyPenalty,
    double? presencePenalty,
    int? maxTokens,
  }) {
    return InferenceAdaptationData(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }
}

/// LLM invocation input (what was sent to the LLM).
/// Service defines type, service populates values.
class LLMInvocationInput {
  /// Conversation messages sent to LLM.
  final List<Message> messages;

  /// System prompt used (if any).
  final String? systemPrompt;

  LLMInvocationInput({
    required this.messages,
    this.systemPrompt,
  });

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'messages': messages.map((m) => m.toJson()).toList(),
    if (systemPrompt != null) 'systemPrompt': systemPrompt,
  };

  /// Deserialize from JSON.
  factory LLMInvocationInput.fromJson(Map<String, dynamic> json) => LLMInvocationInput(
    messages: (json['messages'] as List).map((m) => Message.fromJson(m as Map<String, dynamic>)).toList(),
    systemPrompt: json['systemPrompt'] as String?,
  );
}

/// LLM invocation output (what the LLM returned).
/// Service defines type, implementer provides values (tokensUsed, latencyMs from API).
class LLMInvocationOutput {
  /// The LLM's text response.
  final String response;

  /// Tokens used (from implementer's API response).
  final int tokensUsed;

  /// How long the API call took (milliseconds).
  final double latencyMs;

  LLMInvocationOutput({
    required this.response,
    required this.tokensUsed,
    required this.latencyMs,
  });

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'response': response,
    'tokensUsed': tokensUsed,
    'latencyMs': latencyMs,
  };

  /// Deserialize from JSON.
  factory LLMInvocationOutput.fromJson(Map<String, dynamic> json) => LLMInvocationOutput(
    response: json['response'] as String,
    tokensUsed: json['tokensUsed'] as int,
    latencyMs: json['latencyMs'] as double,
  );
}

/// LLM feedback (what user thought of the response).
/// Service defines type, user provides values via feedback UI.
class LLMFeedback {
  /// User thinks response was too long/wordy.
  final bool tooVerbose;

  /// User thinks response was too short/incomplete.
  final bool tooTerse;

  /// User thinks response was accurate/correct.
  final bool accurate;

  /// If user corrected the response, the corrected text.
  final String? correctedResponse;

  LLMFeedback({
    required this.tooVerbose,
    required this.tooTerse,
    required this.accurate,
    this.correctedResponse,
  });

  /// Serialize to JSON (stored in Feedback.correctedData).
  Map<String, dynamic> toJson() => {
    'tooVerbose': tooVerbose,
    'tooTerse': tooTerse,
    'accurate': accurate,
    if (correctedResponse != null) 'correctedResponse': correctedResponse,
  };

  /// Deserialize from JSON.
  factory LLMFeedback.fromJson(Map<String, dynamic> json) => LLMFeedback(
    tooVerbose: json['tooVerbose'] as bool? ?? false,
    tooTerse: json['tooTerse'] as bool? ?? false,
    accurate: json['accurate'] as bool? ?? false,
    correctedResponse: json['correctedResponse'] as String?,
  );
}

/// LLM response from chatWithTools (includes tool calls, not just text).
/// Used by Coordinator for agentic workflows.
class LLMResponse {
  /// Request ID for logging and correlation.
  final String id;

  /// The LLM's text response or reasoning.
  final String? content;

  /// Tool calls the LLM wants to make (if any).
  final List<LLMToolCall> toolCalls;

  /// Tokens used by the LLM (for cost tracking and adaptation).
  final int tokensUsed;

  /// Whether the LLM indicated it wants to call tools.
  bool get wantsToolCall => toolCalls.isNotEmpty;

  LLMResponse({
    required this.id,
    this.content,
    List<LLMToolCall>? toolCalls,
    required this.tokensUsed,
  }) : toolCalls = toolCalls ?? [];
}

/// A tool call requested by the LLM.
class LLMToolCall {
  /// Unique ID for this tool call.
  final String id;

  /// Name of the tool to call (must match available tools).
  final String toolName;

  /// Arguments to pass to the tool (parsed JSON).
  final Map<String, dynamic> params;

  LLMToolCall({
    required this.id,
    required this.toolName,
    required this.params,
  });
}

/// Tool definition provided to LLM for available tools.
class LLMTool {
  /// Tool name (must match Coordinator's tools).
  final String name;

  /// Description of what the tool does (for LLM to understand).
  final String description;

  /// JSON schema of tool parameters.
  final Map<String, dynamic> parametersSchema;

  LLMTool({
    required this.name,
    required this.description,
    required this.parametersSchema,
  });

  /// Convert to JSON for Groq/Claude API.
  Map<String, dynamic> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parametersSchema,
    },
  };
}

/// Backward compatibility alias
/// @deprecated Use InferenceAdaptationData instead
typedef LLMAdaptationData = InferenceAdaptationData;
