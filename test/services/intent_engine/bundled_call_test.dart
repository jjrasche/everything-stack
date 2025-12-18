import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack/services/intent_engine/intent_engine.dart';
import '../mocks/mock_llm_service.dart';

void main() {
  group('Intent Engine Bundled LLM Call', () {
    late IntentEngine intentEngine;
    late MockLLMService mockLLMService;

    setUp(() {
      mockLLMService = MockLLMService();
      intentEngine = IntentEngine(chatService: mockLLMService);
    });

    test('makes single LLM call returning conversational response and intents', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'Sure, I\'ll set a reminder.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {'target': 'mom', 'duration': '5m', 'message': null},
            'reasoning': 'Matched reminder keyword...',
            'slot_confidence': {'target': 0.95, 'duration': 0.98, 'message': 0.0},
            'execution_order': 1
          }
        ],
        'turn_complete': true
      };

      final result = await intentEngine.classify(
        utterance: 'remind me to call mom in 5 minutes',
        history: [],
        entities: {},
      );

      // Verify single call was made
      expect(mockLLMService.callCount, equals(1),
          reason: 'Should make exactly one LLM call');

      // Verify both response and intents are in the result
      expect(result['conversational_response'], isNotEmpty);
      expect(result['intents'], isNotEmpty);
    });

    test('bundles conversation history in single call', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'I\'ll set that reminder for you.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {'target': null, 'duration': '5m', 'message': null},
            'reasoning': 'Duration extracted.',
            'slot_confidence': {'target': 0.0, 'duration': 0.95, 'message': 0.0},
            'execution_order': 1
          }
        ],
        'turn_complete': true
      };

      final history = [
        {'role': 'user', 'text': 'what time is it'},
        {'role': 'assistant', 'text': 'It is 3 PM'},
      ];

      final result = await intentEngine.classify(
        utterance: 'remind me in 5 minutes',
        history: history,
        entities: {},
      );

      // Verify history was included in the single call
      final callPrompt = mockLLMService.lastPrompt;
      expect(callPrompt, containsString('what time is it'));
      expect(callPrompt, containsString('It is 3 PM'));
      expect(mockLLMService.callCount, equals(1),
          reason: 'Should bundle history in single call, not make additional calls');
    });

    test('includes tool registry in prompt during single call', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'Got it.',
        'intents': [],
        'turn_complete': true
      };

      await intentEngine.classify(
        utterance: 'test',
        history: [],
        entities: {},
      );

      // Verify registry was injected into the single call
      final prompt = mockLLMService.lastPrompt;
      expect(prompt, containsString('REMINDER'),
          reason: 'Tool registry should be in prompt');
      expect(prompt, containsString('MESSAGE'),
          reason: 'Tool registry should be in prompt');
      expect(prompt, containsString('ALARM'),
          reason: 'Tool registry should be in prompt');
      expect(mockLLMService.callCount, equals(1));
    });

    test('does not make follow-up calls for slot clarification', () async {
      // Intent Engine returns slots as-is or null
      // No additional inference calls for clarification
      mockLLMService.mockResponse = {
        'conversational_response': 'Who should I remind you to call?',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {'target': null, 'duration': '5m', 'message': null},
            'reasoning': 'Target slot is required but not provided.',
            'slot_confidence': {'target': 0.0, 'duration': 0.95, 'message': 0.0},
            'execution_order': 1
          }
        ],
        'turn_complete': true
      };

      final result = await intentEngine.classify(
        utterance: 'remind me in 5 minutes',
        history: [],
        entities: {},
      );

      // Should have asked in conversational response, not made extra calls
      expect(result['conversational_response'], containsString('Who'));
      expect(mockLLMService.callCount, equals(1),
          reason: 'Should not make follow-up inference calls');
    });

    test('response and intents come from same LLM call', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'Setting reminder with your message.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {'target': 'mom', 'duration': '5m', 'message': 'call back'},
            'reasoning': 'All slots extracted.',
            'slot_confidence': {'target': 0.95, 'duration': 0.98, 'message': 0.85},
            'execution_order': 1
          }
        ],
        'turn_complete': true
      };

      final result = await intentEngine.classify(
        utterance: 'remind me to call mom and tell her to call back in 5 minutes',
        history: [],
        entities: {},
      );

      // Both pieces present from same call
      expect(result['conversational_response'], contains('reminder'));
      expect(result['intents'], isNotEmpty);
      expect(mockLLMService.callCount, equals(1),
          reason: 'Bundled call returns both conversational response and intent');
    });
  });
}
