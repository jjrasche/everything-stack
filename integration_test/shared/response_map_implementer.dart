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

    print('🔍 [ResponseMapLLMImplementer] Looking up utterance: "$utterance"');
    print('🔍 [ResponseMapLLMImplementer] Available responses: ${responses.keys.toList()}');

    // Lookup in response map
    final response = responses[utterance];
    if (response != null) {
      print('✅ [ResponseMapLLMImplementer] Found response with ${response.toolCalls.length} tool calls');
      return response;
    }

    // Default response if not found
    print('⚠️ [ResponseMapLLMImplementer] No match found, returning default');
    return LLMResponse(
      id: 'mock_${DateTime.now().millisecondsSinceEpoch}',
      content: 'Mock LLM response (no match found)',
      toolCalls: [],
      tokensUsed: 10,
    );
  }
}
