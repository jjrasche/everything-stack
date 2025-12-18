import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack/services/intent_engine/intent_engine.dart';
import '../mocks/mock_llm_service.dart';

void main() {
  group('Slot Confidence Scoring', () {
    late IntentEngine intentEngine;
    late MockLLMService mockLLMService;

    setUp(() {
      mockLLMService = MockLLMService();
      intentEngine = IntentEngine(chatService: mockLLMService);
    });

    test('required slot with null value has confidence of 0.0', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'Who should I remind you to call?',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': null, // Required but missing
              'duration': '5m',
              'message': null
            },
            'reasoning': 'Duration extracted, but target contact not specified.',
            'slot_confidence': {
              'target': 0.0, // Must be 0 for missing required slot
              'duration': 0.98,
              'message': 0.0
            },
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
      final slotConfidence = intent['slot_confidence'] as Map<String, num>;
      final slots = intent['slots'] as Map;

      // For REMINDER, 'target' is required
      expect(slots['target'], isNull);
      expect(slotConfidence['target'], equals(0.0),
          reason: 'Required slot that is null must have 0.0 confidence');
    });

    test('required slot with present value has confidence > 0.8', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'I\'ll set a reminder to call your mom.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': 'mom',
              'duration': '5m',
              'message': null
            },
            'reasoning':
                'Target extracted from context (mom is in recent history), duration unambiguous.',
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

      final intent = result['intents'].first as Map;
      final slotConfidence = intent['slot_confidence'] as Map<String, num>;

      expect(slotConfidence['target'], greaterThan(0.8),
          reason: 'Filled required slot should have high confidence');
    });

    test('optional slot with null value has confidence < 0.5', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'Setting a 5-minute reminder for you.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': null,
              'duration': '5m',
              'message': null // Optional, not provided
            },
            'reasoning': 'Duration extracted from utterance.',
            'slot_confidence': {
              'target': 0.0,
              'duration': 0.95,
              'message': 0.0 // Low confidence for unfilled optional slot
            },
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
      final slotConfidence = intent['slot_confidence'] as Map<String, num>;

      // 'message' is optional and null
      expect(slotConfidence['message'], lessThan(0.5),
          reason: 'Unfilled optional slot should reflect lower confidence');
    });

    test('filled optional slot has higher confidence than unfilled optional', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'I\'ll remind you with that message.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': 'mom',
              'duration': '5m',
              'message': 'call back' // Optional, provided
            },
            'reasoning': 'All slots extracted successfully.',
            'slot_confidence': {
              'target': 0.95,
              'duration': 0.98,
              'message': 0.85 // Higher for filled optional
            },
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

      final intent = result['intents'].first as Map;
      final slotConfidence = intent['slot_confidence'] as Map<String, num>;

      expect(slotConfidence['message'], greaterThan(0.5),
          reason: 'Filled optional slot should have higher confidence');
    });

    test('ambiguous contact has confidence reflecting uncertainty', () async {
      final entities = {
        'david': ['David Smith', 'David Johnson', 'David Williams']
      };

      mockLLMService.mockResponse = {
        'conversational_response':
            'There are 3 people named David. Which one do you mean?',
        'intents': [
          {
            'tool': 'MESSAGE',
            'slots': {
              'target': 'david', // Ambiguous!
              'content': 'hello'
            },
            'reasoning':
                'Target "david" is ambiguous: 3 matches in entity list (David Smith, David Johnson, David Williams). Requires disambiguation.',
            'slot_confidence': {
              'target': 0.45, // Lower confidence due to ambiguity
              'content': 0.92
            },
            'execution_order': 1
          }
        ],
        'turn_complete': true
      };

      final result = await intentEngine.classify(
        utterance: 'send a message to david',
        history: [],
        entities: entities,
      );

      final intent = result['intents'].first as Map;
      final slotConfidence = intent['slot_confidence'] as Map<String, num>;
      final slots = intent['slots'] as Map;

      // Confidence should reflect ambiguity, not be 1.0
      expect(slotConfidence['target'], lessThan(0.9),
          reason: 'Ambiguous slot reference should have lower confidence');

      // Slot value is still returned (executor will need disambiguation)
      expect(slots['target'], equals('david'));

      // Reasoning should explain the ambiguity
      expect(intent['reasoning'], containsString('ambiguous'),
          reason: 'Reasoning must explain why confidence is lower');
    });

    test('clear entity match has confidence > 0.9', () async {
      final entities = {
        'mom': ['Mary Smith']
      };

      mockLLMService.mockResponse = {
        'conversational_response': 'I\'ll remind your mom.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': 'mom',
              'duration': '10m',
              'message': null
            },
            'reasoning': 'Target "mom" has single entity match (Mary Smith).',
            'slot_confidence': {
              'target': 0.98, // High confidence for unambiguous match
              'duration': 0.95,
              'message': 0.0
            },
            'execution_order': 1
          }
        ],
        'turn_complete': true
      };

      final result = await intentEngine.classify(
        utterance: 'remind mom in 10 minutes',
        history: [],
        entities: entities,
      );

      final intent = result['intents'].first as Map;
      final slotConfidence = intent['slot_confidence'] as Map<String, num>;

      expect(slotConfidence['target'], greaterThan(0.9),
          reason: 'Clear entity match should have high confidence');
    });

    test('partial slot fill has confidence reflecting partial coverage', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'What time should I set the alarm for?',
        'intents': [
          {
            'tool': 'ALARM',
            'slots': {
              'time': null, // Required but missing
            },
            'reasoning': 'Time slot is required but not specified in utterance.',
            'slot_confidence': {
              'time': 0.0, // Missing required slot
            },
            'execution_order': 1
          }
        ],
        'turn_complete': true
      };

      final result = await intentEngine.classify(
        utterance: 'set an alarm',
        history: [],
        entities: {},
      );

      final intent = result['intents'].first as Map;
      final slotConfidence = intent['slot_confidence'] as Map<String, num>;

      // Required slot missing
      expect(slotConfidence['time'], equals(0.0),
          reason: 'Required time slot missing should have 0 confidence');
    });

    test('confidence is numeric and bounded [0.0, 1.0]', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'Setting reminder.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': 'mom',
              'duration': '5m',
              'message': null
            },
            'reasoning': 'Standard reminder.',
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

      final intent = result['intents'].first as Map;
      final slotConfidence = intent['slot_confidence'] as Map<String, num>;

      // All confidence scores should be numeric and in range
      slotConfidence.forEach((slot, confidence) {
        expect(confidence, isA<num>(),
            reason: 'Confidence for $slot should be numeric');
        expect(confidence, greaterThanOrEqualTo(0.0),
            reason: 'Confidence cannot be negative');
        expect(confidence, lessThanOrEqualTo(1.0),
            reason: 'Confidence cannot exceed 1.0');
      });
    });
  });
}
