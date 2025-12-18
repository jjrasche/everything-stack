import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack/services/intent_engine/intent_engine.dart';
import '../mocks/mock_llm_service.dart';

void main() {
  group('Intent Engine JSON Schema', () {
    late IntentEngine intentEngine;
    late MockLLMService mockLLMService;

    setUp(() {
      mockLLMService = MockLLMService();
      intentEngine = IntentEngine(chatService: mockLLMService);
    });

    test('classifies utterance and returns exact schema structure', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'Sure, I\'ll set a reminder.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {'target': 'mom', 'duration': '5m', 'message': null},
            'reasoning': 'Matched reminder keyword...',
            'slot_confidence': {
              'target': 0.95,
              'duration': 0.98,
              'message': 0.0
            },
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

      // Verify top-level keys exist
      expect(result, containsKey('conversational_response'));
      expect(result, containsKey('intents'));
      expect(result, containsKey('turn_complete'));

      // Verify conversational_response is string
      expect(result['conversational_response'], isA<String>());
      expect(result['conversational_response'], isNotEmpty);
    });

    test('intents list contains exactly the required fields per intent', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'Sure, I\'ll set a reminder.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {'target': 'mom', 'duration': '5m'},
            'reasoning': 'Matched reminder keyword...',
            'slot_confidence': {'target': 0.95, 'duration': 0.98},
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

      final intents = result['intents'] as List;
      expect(intents, isNotEmpty);

      final intent = intents.first as Map;

      // Exact schema validation
      expect(intent,
          containsKeys(['tool', 'slots', 'reasoning', 'slot_confidence', 'execution_order']));

      // Type validation
      expect(intent['tool'], isA<String>());
      expect(intent['slots'], isA<Map>());
      expect(intent['reasoning'], isA<String>());
      expect(intent['slot_confidence'], isA<Map<String, num>>());
      expect(intent['execution_order'], isA<int>());

      // No extra fields (strict schema)
      expect(intent.keys.length, equals(5),
          reason: 'Intent should have exactly 5 fields');
    });

    test('slot_confidence map has entry for every slot (filled or not)', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'Setting a reminder.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {'target': null, 'duration': '5m', 'message': null},
            'reasoning': 'Duration extracted from utterance.',
            'slot_confidence': {'target': 0.0, 'duration': 0.98, 'message': 0.0},
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

      final intent = result['intents'].first as Map;
      final slots = intent['slots'] as Map;
      final slotConfidence = intent['slot_confidence'] as Map;

      // Every slot must have a confidence entry
      slots.forEach((slotName, _) {
        expect(slotConfidence, containsKey(slotName),
            reason: 'Slot confidence missing for slot: $slotName');
      });
    });

    test('null intent returns empty intents array (not missing key)', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'I\'m doing well, thank you for asking!',
        'intents': [],
        'turn_complete': true
      };

      final result = await intentEngine.classify(
        utterance: 'how are you doing today',
        history: [],
        entities: {},
      );

      expect(result['intents'], isA<List>());
      expect(result['intents'], isEmpty);
      expect(result, containsKey('conversational_response'));
    });

    test('turn_complete is always present and boolean', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'Setting reminder.',
        'intents': [],
        'turn_complete': true
      };

      final result = await intentEngine.classify(
        utterance: 'reminder',
        history: [],
        entities: {},
      );

      expect(result, containsKey('turn_complete'));
      expect(result['turn_complete'], isA<bool>());
    });
  });
}
