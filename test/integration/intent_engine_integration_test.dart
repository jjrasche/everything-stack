import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack/services/intent_engine/intent_engine.dart';
import 'package:everything_stack/services/intent_engine/tool_registry.dart';
import 'package:everything_stack/services/llm_service.dart';
import '../mocks/mock_llm_service.dart';

void main() {
  group('IntentEngine Integration with Real ToolRegistry', () {
    late IntentEngine intentEngine;
    late ToolRegistry registry;
    late MockLLMService mockLLMService;
    late LLMService originalLLMService;

    setUp(() {
      // Save original LLMService
      originalLLMService = LLMService.instance;

      // Create mock LLMService
      mockLLMService = MockLLMService();
      LLMService.instance = mockLLMService;

      // Real ToolRegistry with actual tool definitions
      registry = ToolRegistry(tools: [
        ToolDefinition(
          name: 'REMINDER',
          description: 'Set a reminder for later',
          slots: {
            'target': {'type': 'contact', 'required': true},
            'duration': {'type': 'duration', 'required': true},
            'message': {'type': 'text', 'required': false},
          },
        ),
        ToolDefinition(
          name: 'MESSAGE',
          description: 'Send a message to a contact',
          slots: {
            'target': {'type': 'contact', 'required': true},
            'content': {'type': 'text', 'required': true},
          },
        ),
        ToolDefinition(
          name: 'ALARM',
          description: 'Set an alarm',
          slots: {
            'time': {'type': 'time', 'required': true},
          },
        ),
      ]);

      // IntentEngine with real registry, mock LLMService
      intentEngine = IntentEngine(toolRegistry: registry);
    });

    tearDown(() {
      // Restore original LLMService
      LLMService.instance = originalLLMService;
      mockLLMService.dispose();
    });

    test('classifies simple reminder intent successfully', () async {
      mockLLMService.setMockResponseFromMap({
        'conversational_response': 'I\'ll set a reminder for you.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': 'mom',
              'duration': '5m',
              'message': null,
            },
            'reasoning': 'User requested a reminder for mom in 5 minutes.',
            'slot_confidence': {
              'target': 0.95,
              'duration': 0.98,
              'message': 0.0,
            },
            'execution_order': 1,
          }
        ],
        'turn_complete': true,
      });

      final result = await intentEngine.classify(
        utterance: 'remind me to call mom in 5 minutes',
        history: [],
        entities: {},
      );

      expect(result['conversational_response'], isNotEmpty);
      expect(result['intents'], isNotEmpty);
      expect(result['turn_complete'], isTrue);

      final intent = result['intents'].first as Map;
      expect(intent['tool'], equals('REMINDER'));
      expect(intent['slots']['target'], equals('mom'));
      expect(intent['slots']['duration'], equals('5m'));
    });

    test('returns null intent for conversational utterance', () async {
      mockLLMService.setMockResponseFromMap({
        'conversational_response': 'I\'m doing well, thank you for asking!',
        'intents': [],
        'turn_complete': true,
      });

      final result = await intentEngine.classify(
        utterance: 'how are you doing today',
        history: [],
        entities: {},
      );

      expect(result['intents'], isEmpty);
      expect(result['conversational_response'], isNotEmpty);
    });

    test('makes single LLM call (bundled)', () async {
      mockLLMService.setMockResponseFromMap({
        'conversational_response': 'Got it.',
        'intents': [],
        'turn_complete': true,
      });

      await intentEngine.classify(
        utterance: 'test',
        history: [],
        entities: {},
      );

      expect(mockLLMService.callCount, equals(1),
          reason: 'Should make exactly one LLM call');
    });

    test('includes tool registry in system prompt', () async {
      mockLLMService.setMockResponseFromMap({
        'conversational_response': 'Got it.',
        'intents': [],
        'turn_complete': true,
      });

      await intentEngine.classify(
        utterance: 'test',
        history: [],
        entities: {},
      );

      final call = mockLLMService.callHistory.first;
      final systemPrompt = call['systemPrompt'] as String;

      // System prompt should contain tool definitions
      expect(systemPrompt, containsString('REMINDER'));
      expect(systemPrompt, containsString('MESSAGE'));
      expect(systemPrompt, containsString('ALARM'));
      expect(systemPrompt, containsString('Set a reminder'));
      expect(systemPrompt, containsString('Send a message'));
    });

    test('passes conversation history to LLM', () async {
      mockLLMService.setMockResponseFromMap({
        'conversational_response': 'Got it.',
        'intents': [],
        'turn_complete': true,
      });

      final history = [
        {'role': 'user', 'text': 'what time is it'},
        {'role': 'assistant', 'text': 'It is 3 PM'},
      ];

      await intentEngine.classify(
        utterance: 'remind me in 5 minutes',
        history: history,
        entities: {},
      );

      final call = mockLLMService.callHistory.first;
      expect(call['history_length'], equals(2),
          reason: 'History should be passed to LLM');
    });

    test('includes entity context in user message', () async {
      mockLLMService.setMockResponseFromMap({
        'conversational_response': 'Got it.',
        'intents': [],
        'turn_complete': true,
      });

      final entities = {
        'contacts': ['mom', 'dad', 'sister'],
      };

      await intentEngine.classify(
        utterance: 'send a message',
        history: [],
        entities: entities,
      );

      final call = mockLLMService.callHistory.first;
      final userMessage = call['userMessage'] as String;

      // Entity context should be in user message
      expect(userMessage, containsString('contacts'));
      expect(userMessage, containsString('mom'));
    });

    test('rejects intent with tool not in registry', () async {
      mockLLMService.setMockResponseFromMap({
        'conversational_response': 'Got it.',
        'intents': [
          {
            'tool': 'NONEXISTENT_TOOL',
            'slots': {},
            'reasoning': 'Unknown tool',
            'slot_confidence': {},
            'execution_order': 1,
          }
        ],
        'turn_complete': true,
      });

      expect(
        () => intentEngine.classify(
          utterance: 'do something',
          history: [],
          entities: {},
        ),
        throwsA(isA<UnknownToolException>()),
        reason: 'Should reject tool not in registry',
      );
    });

    test('classifies multi-tool intent', () async {
      mockLLMService.setMockResponseFromMap({
        'conversational_response': 'I\'ll remind you and send a message.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': 'mom',
              'duration': '5m',
              'message': null,
            },
            'reasoning': 'Set reminder.',
            'slot_confidence': {
              'target': 0.95,
              'duration': 0.98,
              'message': 0.0,
            },
            'execution_order': 1,
          },
          {
            'tool': 'MESSAGE',
            'slots': {
              'target': 'mom',
              'content': 'call me back',
            },
            'reasoning': 'Send message.',
            'slot_confidence': {
              'target': 0.95,
              'content': 0.9,
            },
            'execution_order': 2,
          }
        ],
        'turn_complete': true,
      });

      final result = await intentEngine.classify(
        utterance: 'remind me to call mom and tell her to call me back in 5 minutes',
        history: [],
        entities: {},
      );

      expect(result['intents'], hasLength(2));
      expect(result['intents'][0]['tool'], equals('REMINDER'));
      expect(result['intents'][1]['tool'], equals('MESSAGE'));
      expect(result['intents'][0]['execution_order'], equals(1));
      expect(result['intents'][1]['execution_order'], equals(2));
    });

    test('handles malformed JSON with regex extraction', () async {
      // Claude might return extra text before/after JSON
      mockLLMService.setMockResponse(
        'Here\'s the response:\n'
        '{\n'
        '  "conversational_response": "Got it.",\n'
        '  "intents": [],\n'
        '  "turn_complete": true\n'
        '}\n'
        'End of response.',
      );

      final result = await intentEngine.classify(
        utterance: 'test',
        history: [],
        entities: {},
      );

      expect(result['intents'], isEmpty);
      expect(result['turn_complete'], isTrue);
    });

    test('extracts intent with all required and optional fields', () async {
      mockLLMService.setMockResponseFromMap({
        'conversational_response': 'Setting up your reminder.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': 'mom',
              'duration': '10m',
              'message': 'please call me back',
            },
            'reasoning':
                'All slots provided: contact is mom, duration is 10 minutes, with message.',
            'slot_confidence': {
              'target': 0.98,
              'duration': 0.99,
              'message': 0.92,
            },
            'execution_order': 1,
          }
        ],
        'turn_complete': true,
      });

      final result = await intentEngine.classify(
        utterance: 'remind mom to call me back in 10 minutes with message',
        history: [],
        entities: {},
      );

      final intent = result['intents'].first as Map;
      expect(intent['slots']['message'], equals('please call me back'));
      expect(intent['slot_confidence']['message'], greaterThan(0.8));
    });

    test('validates slot confidence is numeric and bounded', () async {
      mockLLMService.setMockResponseFromMap({
        'conversational_response': 'Setting reminder.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': 'mom',
              'duration': '5m',
              'message': null,
            },
            'reasoning': 'Standard reminder.',
            'slot_confidence': {
              'target': 0.95,
              'duration': 0.98,
              'message': 0.0,
            },
            'execution_order': 1,
          }
        ],
        'turn_complete': true,
      });

      final result = await intentEngine.classify(
        utterance: 'remind mom in 5 minutes',
        history: [],
        entities: {},
      );

      final intent = result['intents'].first as Map;
      final slotConfidence = intent['slot_confidence'] as Map;

      slotConfidence.forEach((slot, confidence) {
        expect(confidence, isA<num>());
        expect(confidence, greaterThanOrEqualTo(0.0));
        expect(confidence, lessThanOrEqualTo(1.0));
      });
    });

    test('streams tokens and accumulates into complete JSON', () async {
      // Mock returns response character by character (token=1 char)
      final jsonResponse =
          '{"conversational_response":"Got it.","intents":[],"turn_complete":true}';
      mockLLMService.mockJsonResponse = jsonResponse;
      mockLLMService.tokenSize = 1; // One character per token

      final result = await intentEngine.classify(
        utterance: 'test',
        history: [],
        entities: {},
      );

      expect(result['intents'], isEmpty);
      expect(result['turn_complete'], isTrue);
    });
  });
}
