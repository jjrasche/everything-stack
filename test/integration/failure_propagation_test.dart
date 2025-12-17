import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack/services/intent_engine/intent_engine.dart';
import 'package:everything_stack/services/tool_executor/tool_executor.dart';
import '../mocks/mock_chat_service.dart';
import '../mocks/mock_tool_executor.dart';
import '../mocks/mock_trainer.dart';

void main() {
  group('Failure Propagation to Trainer', () {
    late IntentEngine intentEngine;
    late MockChatService mockChatService;
    late MockToolExecutor mockExecutor;
    late MockTrainer mockTrainer;

    setUp(() {
      mockChatService = MockChatService();
      mockExecutor = MockToolExecutor();
      mockTrainer = MockTrainer();
      intentEngine = IntentEngine(
        chatService: mockChatService,
        executor: mockExecutor,
        trainer: mockTrainer,
      );
    });

    test('tool execution failure returns error signal to Trainer', () async {
      mockChatService.mockResponse = {
        'conversational_response': 'Setting a reminder...',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': 'mom',
              'duration': '5m',
              'message': null
            },
            'reasoning': 'Standard reminder request.',
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

      // Executor will fail when trying to create reminder
      mockExecutor.setFailure('REMINDER', ExecutionFailure(
        type: ExecutionFailureType.entityNotFound,
        message: 'Contact "mom" not found in system',
      ));

      final result = await intentEngine.classify(
        utterance: 'remind me to call mom in 5 minutes',
        history: [],
        entities: {},
      );

      // Intent Engine produces the intent
      expect(result['intents'], isNotEmpty);

      // Executor attempts to run it
      final executionResult = await mockExecutor.execute(result['intents']);
      expect(executionResult.status, equals(ExecutionStatus.failed));

      // Failure signal reaches Trainer
      expect(mockTrainer.lastFailureSignal, isNotNull,
          reason: 'Failure should be reported to Trainer');
      expect(mockTrainer.lastFailureSignal['tool'], equals('REMINDER'));
      expect(mockTrainer.lastFailureSignal['message'],
          equals('Contact "mom" not found in system'));
    });

    test('trainer receives complete failure context for learning', () async {
      mockChatService.mockResponse = {
        'conversational_response': 'Sending a message...',
        'intents': [
          {
            'tool': 'MESSAGE',
            'slots': {
              'target': 'david',
              'content': 'hello'
            },
            'reasoning': 'Simple message request.',
            'slot_confidence': {
              'target': 0.45, // Low confidence due to ambiguity
              'content': 0.92
            },
            'execution_order': 1
          }
        ],
        'turn_complete': true
      };

      mockExecutor.setFailure('MESSAGE', ExecutionFailure(
        type: ExecutionFailureType.ambiguousEntity,
        message: '3 contacts named "david" found',
        originalUtterance: 'send a message to david',
        attemptedSlots: {'target': 'david'},
      ));

      final result = await intentEngine.classify(
        utterance: 'send a message to david',
        history: [],
        entities: {
          'david': ['David A', 'David B', 'David C']
        },
      );

      // Simulate execution
      await mockExecutor.execute(result['intents']);

      // Trainer receives structured failure data
      final failure = mockTrainer.lastFailureSignal;
      expect(failure, containsKeys([
        'tool',
        'slot_affected',
        'failure_type',
        'original_utterance',
        'attempted_slots',
        'ambiguous_values',
        'timestamp',
      ]));

      // Trainer can learn from this
      expect(failure['failure_type'], equals('ambiguousEntity'));
      expect(failure['ambiguous_values'], equals(['David A', 'David B', 'David C']));
      expect(failure['original_utterance'], equals('send a message to david'));
    });

    test('trainer receives slot-specific failure information', () async {
      mockChatService.mockResponse = {
        'conversational_response': 'Setting reminder...',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': null,
              'duration': '5m',
              'message': null
            },
            'reasoning': 'Target slot missing.',
            'slot_confidence': {
              'target': 0.0,
              'duration': 0.95,
              'message': 0.0
            },
            'execution_order': 1
          }
        ],
        'turn_complete': true
      };

      mockExecutor.setFailure('REMINDER', ExecutionFailure(
        type: ExecutionFailureType.requiredSlotMissing,
        message: 'Required slot "target" is null',
        slotName: 'target',
        slotConfidence: 0.0,
      ));

      final result = await intentEngine.classify(
        utterance: 'remind me in 5 minutes',
        history: [],
        entities: {},
      );

      await mockExecutor.execute(result['intents']);

      final failure = mockTrainer.lastFailureSignal;
      expect(failure['failure_type'], equals('requiredSlotMissing'));
      expect(failure['slot_affected'], equals('target'));
      expect(failure['slot_confidence_at_failure'], equals(0.0));
    });

    test('trainer tracks failure by failure type for pattern learning', () async {
      mockChatService.mockResponse = {
        'conversational_response': 'Got it.',
        'intents': [
          {
            'tool': 'MESSAGE',
            'slots': {'target': 'unknown_person', 'content': 'hello'},
            'reasoning': 'Standard message.',
            'slot_confidence': {'target': 0.3, 'content': 0.9}
          }
        ],
        'turn_complete': true
      };

      mockExecutor.setFailure('MESSAGE', ExecutionFailure(
        type: ExecutionFailureType.entityNotFound,
        message: 'Entity not found',
      ));

      final result = await intentEngine.classify(
        utterance: 'message unknown person',
        history: [],
        entities: {},
      );

      await mockExecutor.execute(result['intents']);

      final failure = mockTrainer.lastFailureSignal;
      expect(failure['failure_type'], equals('entityNotFound'));

      // Trainer can learn that low confidence (0.3) + entityNotFound = pattern
      expect(failure['slot_confidence_at_failure'], lessThan(0.5));
    });

    test('successful execution also reaches trainer (positive signal)', () async {
      mockChatService.mockResponse = {
        'conversational_response': 'I\'ll set a reminder.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': 'mom',
              'duration': '5m',
              'message': null
            },
            'reasoning': 'Clear reminder request.',
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

      mockExecutor.setSuccess(ExecutionSuccess(
        tool: 'REMINDER',
        slotsUsed: {'target': 'mom', 'duration': '5m'},
      ));

      final result = await intentEngine.classify(
        utterance: 'remind me to call mom in 5 minutes',
        history: [],
        entities: {},
      );

      final executionResult = await mockExecutor.execute(result['intents']);

      // Trainer records success
      mockTrainer.recordSuccess(
        utterance: 'remind me to call mom in 5 minutes',
        intent: result['intents'].first,
        executionResult: executionResult,
      );

      // Trainer has success data for learning positive patterns
      expect(mockTrainer.lastSuccess, isNotNull);
      expect(mockTrainer.lastSuccess['tool'], equals('REMINDER'));
      expect(mockTrainer.lastSuccess['slotsUsed'],
          equals({'target': 'mom', 'duration': '5m'}));
    });

    test('trainer records both confidence scores and execution outcomes', () async {
      mockChatService.mockResponse = {
        'conversational_response': 'Got it.',
        'intents': [
          {
            'tool': 'REMINDER',
            'slots': {
              'target': 'mom',
              'duration': '5m',
              'message': null
            },
            'reasoning': 'Test.',
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

      mockExecutor.setSuccess(ExecutionSuccess(tool: 'REMINDER'));

      final result = await intentEngine.classify(
        utterance: 'remind me to call mom in 5 minutes',
        history: [],
        entities: {},
      );

      final intent = result['intents'].first as Map;
      final slotConfidence = intent['slot_confidence'] as Map;

      await mockExecutor.execute(result['intents']);

      mockTrainer.recordSuccess(
        utterance: 'remind me to call mom in 5 minutes',
        intent: intent,
        executionResult: ExecutionSuccess(tool: 'REMINDER'),
      );

      // Trainer learns the correlation
      final success = mockTrainer.lastSuccess;
      expect(success['slot_confidence_at_execution'], equals(slotConfidence));
      expect(success['execution_status'], equals('success'));
    });

    test('trainer logs failed intent classification (null intent case)', () async {
      mockChatService.mockResponse = {
        'conversational_response': 'I don\'t understand what you\'re asking.',
        'intents': [],
        'turn_complete': true
      };

      final result = await intentEngine.classify(
        utterance: 'something unmappable',
        history: [],
        entities: {},
      );

      // Intent is null
      expect(result['intents'], isEmpty);

      // Trainer logs this as a null intent (conversational fallback)
      mockTrainer.recordNullIntent(
        utterance: 'something unmappable',
        conversationalResponse: result['conversational_response'],
      );

      expect(mockTrainer.lastNullIntent, isNotNull);
      expect(mockTrainer.lastNullIntent['utterance'], equals('something unmappable'));
    });
  });
}
