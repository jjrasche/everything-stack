import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack/services/intent_engine/intent_engine.dart';
import 'package:everything_stack/services/intent_engine/tool_registry.dart';
import '../mocks/mock_llm_service.dart';

void main() {
  group('Tool Registry Validation', () {
    late IntentEngine intentEngine;
    late MockLLMService mockLLMService;
    late ToolRegistry registry;

    setUp(() {
      mockLLMService = MockLLMService();
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
      intentEngine = IntentEngine(
        chatService: mockLLMService,
        toolRegistry: registry,
      );
    });

    test('fails fast if intent returns tool not in registry', () async {
      // Simulate Claude returning a tool that doesn't exist
      mockLLMService.mockResponse = {
        'conversational_response': 'Setting reminder...',
        'intents': [
          {
            'tool': 'NONEXISTENT_TOOL', // Not in registry!
            'slots': {},
            'reasoning': 'Some reason',
            'slot_confidence': {},
            'execution_order': 1
          }
        ],
        'turn_complete': true
      };

      // Should throw or return invalid state
      expect(
        () => intentEngine.classify(
          utterance: 'do something',
          history: [],
          entities: {},
        ),
        throwsA(isA<UnknownToolException>()),
        reason: 'Intent references tool not in registry - broken state',
      );
    });

    test('validates all tools in intent list are in registry before execution', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'Setting up both...',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {'target': 'mom', 'duration': '5m', 'message': null},
            'reasoning': 'First intent valid',
            'slot_confidence': {'target': 0.95, 'duration': 0.98, 'message': 0.0},
            'execution_order': 1
          },
          {
            'tool': 'INVALID_TOOL', // Invalid in position 2
            'slots': {},
            'reasoning': 'Second intent invalid',
            'slot_confidence': {},
            'execution_order': 2
          }
        ],
        'turn_complete': true
      };

      // Should detect invalid tool even though first intent is valid
      expect(
        () => intentEngine.classify(
          utterance: 'remind and do invalid thing',
          history: [],
          entities: {},
        ),
        throwsA(isA<UnknownToolException>()),
        reason: 'Should validate all tools in list, not just first',
      );
    });

    test('registry injection includes all tools in LLM prompt', () async {
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

      final prompt = mockLLMService.lastPrompt;

      // All tool names present
      expect(prompt, containsString('REMINDER'));
      expect(prompt, containsString('MESSAGE'));
      expect(prompt, containsString('ALARM'));

      // All descriptions present
      expect(prompt, containsString('Set a reminder'));
      expect(prompt, containsString('Send a message'));
      expect(prompt, containsString('Set an alarm'));

      // All slot definitions present
      expect(prompt, containsString('target'));
      expect(prompt, containsString('duration'));
      expect(prompt, containsString('message'));
      expect(prompt, containsString('content'));
      expect(prompt, containsString('time'));
    });

    test('registry includes required/optional slot metadata in prompt', () async {
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

      final prompt = mockLLMService.lastPrompt;

      // Metadata about slot requirements should be in prompt
      expect(prompt, containsString('required'),
          reason: 'Prompt should indicate which slots are required');
      expect(prompt, containsString('optional'),
          reason: 'Prompt should indicate which slots are optional');
    });

    test('handles empty tool registry gracefully', () async {
      final emptyRegistry = ToolRegistry(tools: []);
      final emptyEngine = IntentEngine(
        chatService: mockLLMService,
        toolRegistry: emptyRegistry,
      );

      mockLLMService.mockResponse = {
        'conversational_response': 'I don\'t have any tools available.',
        'intents': [],
        'turn_complete': true
      };

      final result = await emptyEngine.classify(
        utterance: 'do something',
        history: [],
        entities: {},
      );

      // Should return conversational response without intents
      expect(result['intents'], isEmpty);
      expect(result['conversational_response'], isNotEmpty);
    });

    test('raises error if tool in intent has mismatched slot definitions', () async {
      mockLLMService.mockResponse = {
        'conversational_response': 'Setting reminder.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': 'mom',
              'duration': '5m',
              'message': null,
              'unknown_slot': 'value' // Not in registry definition!
            },
            'reasoning': 'Has extra slot',
            'slot_confidence': {
              'target': 0.95,
              'duration': 0.98,
              'message': 0.0,
              'unknown_slot': 0.5
            },
            'execution_order': 1
          }
        ],
        'turn_complete': true
      };

      expect(
        () => intentEngine.classify(
          utterance: 'test',
          history: [],
          entities: {},
        ),
        throwsA(isA<SlotDefinitionMismatchException>()),
        reason: 'Intent contains slots not defined in tool registry',
      );
    });
  });
}
