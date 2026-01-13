/// Mock Groq Implementer - returns canned LLM response for testing
///
/// Implements LLMImplementer interface but returns hardcoded responses
/// instead of hitting the real Groq API. Used in CI mode integration tests.

import 'package:everything_stack_template/services/implementations/llm_implementer.dart';
import 'package:everything_stack_template/services/types/message.dart';
import 'package:everything_stack_template/services/types/llm_types.dart';

class MockGroqImplementer implements LLMImplementer {
  @override
  String get implementerName => 'groq';

  @override
  int get maxTokensLimit => 8192;

  @override
  Future<LLMInvocationOutput> chat({
    required List<Message> messages,
    required double temperature,
    String? systemPrompt,
  }) async {
    print('🤖 MockGroqImplementer.chat(): Returning canned response (no API call)');
    return LLMInvocationOutput(
      response: 'This is a mock response from Groq implementer.',
      tokensUsed: 42,
      latencyMs: 100,
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
    print('🤖 MockGroqImplementer.chatWithTools(): Returning canned response (no API call)');
    return LLMResponse(
      id: 'mock_response_${DateTime.now().millisecondsSinceEpoch}',
      content: 'This is a mock LLM response generated without calling any external API.',
      toolCalls: [],
      tokensUsed: 42,
    );
  }
}
