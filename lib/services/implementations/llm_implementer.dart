import '../types/message.dart';
import '../types/llm_types.dart';
import '../../core/implementer.dart' show Implementer;

abstract class LLMImplementer implements Implementer {
  /// Hard token limit for this implementer (e.g., Groq 8K, Claude 200K).
  /// Service uses this to constrain preferredResponseLength from adaptation state.
  int get maxTokensLimit;

  /// Available models for this implementer.
  /// Used by ModelSelector to know which models can be selected.
  /// Returns list of model identifiers (e.g., ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant'])
  List<String> get availableModels;

  /// Call the LLM with typed messages and adaptation parameters.
  ///
  /// Parameters:
  /// - [messages] Typed conversation messages to send to LLM
  /// - [temperature] Creativity level (0.0-2.0)
  /// - [topP] Nucleus sampling threshold (0.0-1.0)
  /// - [frequencyPenalty] Penalize frequent tokens (-2.0 to 2.0)
  /// - [presencePenalty] Penalize any repeated tokens (-2.0 to 2.0)
  /// - [maxTokens] Maximum tokens to generate
  ///
  /// Returns: LLMInvocationOutput with response, tokens, and latency
  /// No side effects: Returns typed output directly
  Future<LLMInvocationOutput> chat({
    required List<Message> messages,
    required double temperature,
    required double topP,
    required double frequencyPenalty,
    required double presencePenalty,
    required int maxTokens,
  });

  /// Call LLM with tools available (for agentic workflows).
  ///
  /// Parameters:
  /// - [model] Which model to use (e.g., 'llama-3.3-70b-versatile')
  /// - [messages] Conversation (as Maps, not Message objects, for raw API pass-through)
  /// - [tools] Tools available to the LLM
  /// - [temperature] Creativity level
  /// - [maxTokens] Optional hard token limit (implementer-specific)
  ///
  /// Returns: LLMResponse with text content and optional tool calls
  /// For agentic loops: If wantsToolCall is true, execute tools and call again
  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  });

  /// Stream tokens from LLM via SSE for real-time output.
  ///
  /// Parameters:
  /// - [model] Which model to use
  /// - [messages] Conversation (as Maps for raw API pass-through)
  /// - [temperature] Creativity level
  /// - [maxTokens] Optional hard token limit
  ///
  /// Yields individual token strings as they arrive from the API.
  /// Completes when the stream ends or an error occurs.
  Stream<String> chatStream({
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    int? maxTokens,
  });
}
