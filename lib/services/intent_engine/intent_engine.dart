/// Intent Engine - Translates user utterances into structured tool invocations
///
/// Workflow:
/// 1. User speaks (Deepgram detects silence and signals turn complete)
/// 2. Full utterance sent to Intent Engine with conversation history and entities
/// 3. Single LLM call returns: conversational response + intent list
/// 4. Tool Executor receives intents and invokes them in order
/// 5. Failures/successes reported back to Trainer for learning
///
/// JSON Output Format:
/// {
///   "conversational_response": "string",
///   "intents": [
///     {
///       "tool": "string",
///       "slots": {"slotName": value, ...},
///       "reasoning": "string",
///       "slot_confidence": {"slotName": 0.0-1.0, ...},
///       "execution_order": int
///     }
///   ],
///   "turn_complete": true
/// }

export 'tool_registry.dart';

// Stub for IntentEngine implementation
// Tests define the interface via expected behavior
class IntentEngine {
  // TODO: Implement based on test requirements

  IntentEngine({
    required dynamic chatService,
    dynamic toolRegistry,
    dynamic executor,
    dynamic trainer,
  });

  Future<Map<String, dynamic>> classify({
    required String utterance,
    required List<Map<String, String>> history,
    required Map<String, dynamic> entities,
  }) async {
    // TODO: Implement
    throw UnimplementedError('Intent Engine not yet implemented');
  }
}
