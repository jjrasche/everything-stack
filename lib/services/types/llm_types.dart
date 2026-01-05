/// # LLM Service Type Definitions
///
/// Typed payloads for LLM service adaptation, invocations, and feedback.
/// Provides compile-time safety, IDE autocomplete, and self-documentation.

import 'message.dart';

/// Learned LLM preferences (per implementer, per user).
/// These are adaptable parameters that training adjusts.
class LLMAdaptationData {
  /// How "creative" vs "rigid" the LLM should be (0.0-2.0).
  /// Higher = more creative/risky, Lower = more factual/conservative.
  /// Note: Different implementations have different temperature semantics.
  final double temperature;

  /// User's preferred response length (tokens).
  /// Service uses this to constrain actual maxTokens based on implementer limits.
  /// Not the hard limit itself (Groq:8K, Claude:200K), but user preference within limit.
  final int preferredResponseLength;

  /// System prompt override (if user prefers specific system behavior).
  final String? systemPrompt;

  LLMAdaptationData({
    required this.temperature,
    required this.preferredResponseLength,
    this.systemPrompt,
  });

  /// Default adaptation state (untrained).
  factory LLMAdaptationData.defaults() => LLMAdaptationData(
    temperature: 0.7,
    preferredResponseLength: 1024,
  );

  /// Deserialize from JSON.
  factory LLMAdaptationData.fromJson(Map<String, dynamic> json) => LLMAdaptationData(
    temperature: json['temperature'] as double? ?? 0.7,
    preferredResponseLength: json['preferredResponseLength'] as int? ?? 1024,
    systemPrompt: json['systemPrompt'] as String?,
  );

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'temperature': temperature,
    'preferredResponseLength': preferredResponseLength,
    if (systemPrompt != null) 'systemPrompt': systemPrompt,
  };
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
