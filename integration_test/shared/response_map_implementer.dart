/// # ResponseMapLLMImplementer
///
/// Generic mock LLM with zero conditionals - pure data lookup.
/// Takes a map of utterance → LLMResponse and returns the response for the given utterance.

import 'package:everything_stack_template/services/implementations/llm_implementer.dart';
import 'package:everything_stack_template/services/types/llm_types.dart';
import 'package:everything_stack_template/services/types/message.dart';

/// Generic mock LLM - zero conditionals, pure data lookup
class ResponseMapLLMImplementer implements LLMImplementer {
  final Map<String, LLMResponse> responses;

  ResponseMapLLMImplementer(this.responses);

  @override
  String get implementerName => 'response_map_mock';

  @override
  Set<String> get supportedPlatforms => {'android', 'ios', 'web', 'windows', 'macos', 'linux'};

  @override
  int get maxTokensLimit => 8192;

  @override
  List<String> get availableModels => const [
        'llama-3.3-70b-versatile',
        'llama-3.1-8b-instant',
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
    return LLMInvocationOutput(
      response: 'Mock response',
      tokensUsed: 10,
      latencyMs: 50,
    );
  }

  @override
  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    // Extract last user message
    final lastUserMsg = messages.lastWhere(
      (msg) => msg['role'] == 'user',
      orElse: () => <String, dynamic>{'content': ''},
    );
    final utterance = (lastUserMsg['content'] as String?) ?? '';

    // Lookup in response map
    final response = responses[utterance];
    if (response != null) {
      return response;
    }

    // Default response if not found
    return LLMResponse(
      id: 'mock_${DateTime.now().millisecondsSinceEpoch}',
      content: 'Mock LLM response (no match found)',
      toolCalls: [],
      tokensUsed: 10,
    );
  }
}
