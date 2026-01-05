/// # LLM Implementer Interface
///
/// Dumb API wrapper for LLM providers (Groq, Claude, etc.).
/// No state management, no training logic. Just calls API and returns results.
/// Service holds metadata about call (tokensUsed, latencyMs) in properties.

import '../types/message.dart';
import '../types/llm_types.dart';
import '../../core/implementer.dart';

abstract class LLMImplementer implements Implementer {
  /// Hard token limit for this implementer (e.g., Groq 8K, Claude 200K).
  /// Service uses this to constrain preferredResponseLength from adaptation state.
  int get maxTokensLimit;

  /// Call the LLM with typed messages and adaptation parameters.
  ///
  /// Parameters:
  /// - [messages] Typed conversation messages to send to LLM
  /// - [temperature] Creativity level (0.0-2.0)
  /// - [systemPrompt] Optional system prompt override
  ///
  /// Returns: LLMInvocationOutput with response, tokens, and latency
  /// No side effects: Returns typed output directly
  Future<LLMInvocationOutput> chat({
    required List<Message> messages,
    required double temperature,
    String? systemPrompt,
  });
}
