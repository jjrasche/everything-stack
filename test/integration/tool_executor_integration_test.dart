import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/tool_executor/tool_executor.dart';
import 'package:everything_stack_template/services/tool_executor/mock_tools.dart';
import 'package:everything_stack_template/services/intent_engine/tool_registry.dart';
import 'package:everything_stack_template/services/intent_engine/intent_engine.dart';
import '../mocks/mock_trainer.dart';

void main() {
  group('ToolExecutor with Real ToolRegistry', () {
    late ToolRegistry registry;
    late ToolExecutor executor;
    late MockTrainer trainer;

    setUp(() {
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

      trainer = MockTrainer();

      // Real ToolExecutor with mock tool implementations
      executor = ToolExecutor(
        toolRegistry: registry,
        trainer: trainer,
        toolImplementations: createMockTools(),
      );
    });

    test('executes intent with valid slots without throwing', () async {
      final intent = Intent(
        tool: 'REMINDER',
        slots: {
          'target': 'mom',
          'duration': '5m',
          'message': null,
        },
        reasoning: 'User requested reminder for mom.',
        slotConfidence: {'target': 0.95, 'duration': 0.98, 'message': 0.0},
        executionOrder: 1,
      );

      final result = await executor.execute(intent);

      expect(result.status, equals(ExecutionStatus.success));
      expect(result.failure, isNull);
      expect(result.toolResult, isNotNull);
      expect(result.toolResult!.success, isTrue);
    });

    test('rejects intent with unknown tool', () async {
      final intent = Intent(
        tool: 'NONEXISTENT_TOOL',
        slots: {},
        reasoning: 'Unknown tool',
        slotConfidence: {},
        executionOrder: 1,
      );

      final result = await executor.execute(intent);

      expect(result.status, equals(ExecutionStatus.failed));
      expect(result.failure, isNotNull);
      expect(result.failure!.type, equals(ExecutionFailureType.toolNotFound));
      expect(trainer.lastFailureSignal, isNotNull);
    });

    test('rejects intent with missing required slot', () async {
      final intent = Intent(
        tool: 'REMINDER',
        slots: {
          'target': null, // Required slot missing!
          'duration': '5m',
          'message': null,
        },
        reasoning: 'Missing target.',
        slotConfidence: {'target': 0.0, 'duration': 0.98, 'message': 0.0},
        executionOrder: 1,
      );

      final result = await executor.execute(intent);

      expect(result.status, equals(ExecutionStatus.failed));
      expect(result.failure, isNotNull);
      expect(result.failure!.type, equals(ExecutionFailureType.requiredSlotMissing));
      expect(result.failure!.slotName, equals('target'));
      expect(trainer.lastFailureSignal, isNotNull);
      expect(trainer.lastFailureSignal!['slot_affected'], equals('target'));
    });

    test('rejects intent with invalid slot type (duration malformed)', () async {
      final intent = Intent(
        tool: 'REMINDER',
        slots: {
          'target': 'mom',
          'duration': 'abc', // Invalid duration format!
          'message': null,
        },
        reasoning: 'Invalid duration format.',
        slotConfidence: {'target': 0.95, 'duration': 0.5, 'message': 0.0},
        executionOrder: 1,
      );

      final result = await executor.execute(intent);

      expect(result.status, equals(ExecutionStatus.failed));
      expect(result.failure, isNotNull);
      expect(result.failure!.type, equals(ExecutionFailureType.invalidSlotFormat));
      expect(trainer.lastFailureSignal, isNotNull);
    });

    test('rejects intent with wrong type for contact slot (number instead of string)',
        () async {
      final intent = Intent(
        tool: 'MESSAGE',
        slots: {
          'target': 123, // Wrong type! Should be string
          'content': 'hello',
        },
        reasoning: 'Wrong type for contact.',
        slotConfidence: {'target': 0.5, 'content': 0.9},
        executionOrder: 1,
      );

      final result = await executor.execute(intent);

      expect(result.status, equals(ExecutionStatus.failed));
      expect(result.failure, isNotNull);
      expect(result.failure!.type, equals(ExecutionFailureType.invalidSlotFormat));
    });

    test('accepts optional slots as null', () async {
      final intent = Intent(
        tool: 'REMINDER',
        slots: {
          'target': 'mom',
          'duration': '5m',
          'message': null, // Optional slot, null is OK
        },
        reasoning: 'Valid with optional null.',
        slotConfidence: {'target': 0.95, 'duration': 0.98, 'message': 0.0},
        executionOrder: 1,
      );

      final result = await executor.execute(intent);

      expect(result.status, equals(ExecutionStatus.success));
      expect(trainer.lastSuccess, isNotNull);
    });

    test('reports successful execution to Trainer with full context', () async {
      final intent = Intent(
        tool: 'REMINDER',
        slots: {
          'target': 'mom',
          'duration': '5m',
          'message': null,
        },
        reasoning: 'User requested reminder.',
        slotConfidence: {'target': 0.95, 'duration': 0.98, 'message': 0.0},
        executionOrder: 1,
      );

      await executor.execute(intent);

      expect(trainer.lastSuccess, isNotNull);
      expect(trainer.lastSuccess!['tool'], equals('REMINDER'));
      expect(trainer.lastSuccess!['slotsUsed'], equals(intent.slots));
      expect(trainer.lastSuccess!['reasoning'], equals(intent.reasoning));
      expect(trainer.lastSuccess!['execution_status'], equals('success'));
    });

    test('reports failure to Trainer with failure type and details', () async {
      final intent = Intent(
        tool: 'REMINDER',
        slots: {
          'target': null,
          'duration': '5m',
          'message': null,
        },
        reasoning: 'Missing target.',
        slotConfidence: {'target': 0.0, 'duration': 0.98, 'message': 0.0},
        executionOrder: 1,
      );

      await executor.execute(intent);

      expect(trainer.lastFailureSignal, isNotNull);
      expect(trainer.lastFailureSignal!['tool'], equals('REMINDER'));
      expect(trainer.lastFailureSignal!['failure_type'],
          equals('requiredSlotMissing'));
      expect(trainer.lastFailureSignal!['slot_affected'], equals('target'));
      expect(trainer.lastFailureSignal!['slot_confidence_at_failure'], equals(0.0));
    });

    test('executes multiple intents in order, continues on failure', () async {
      final intents = [
        Intent(
          tool: 'REMINDER',
          slots: {
            'target': 'mom',
            'duration': '5m',
            'message': null,
          },
          reasoning: 'First: valid reminder.',
          slotConfidence: {'target': 0.95, 'duration': 0.98, 'message': 0.0},
          executionOrder: 1,
        ),
        Intent(
          tool: 'MESSAGE',
          slots: {
            'target': null, // Invalid - required slot missing
            'content': 'hello',
          },
          reasoning: 'Second: missing target.',
          slotConfidence: {'target': 0.0, 'content': 0.9},
          executionOrder: 2,
        ),
        Intent(
          tool: 'ALARM',
          slots: {
            'time': '2025-12-18T10:00:00Z',
          },
          reasoning: 'Third: valid alarm.',
          slotConfidence: {'time': 0.95},
          executionOrder: 3,
        ),
      ];

      final results = await executor.executeAll(intents);

      // Should have 3 results, not stop at first failure
      expect(results.length, equals(3));

      // First should succeed
      expect(results[0].status, equals(ExecutionStatus.success));

      // Second should fail
      expect(results[1].status, equals(ExecutionStatus.failed));
      expect(results[1].failure!.type, equals(ExecutionFailureType.requiredSlotMissing));

      // Third should succeed despite second failing
      expect(results[2].status, equals(ExecutionStatus.success));

      // All outcomes should be in Trainer history
      expect(trainer.successHistory.length, equals(2)); // First and third
      expect(trainer.failureHistory.length, equals(1)); // Second
    });

    test('validates intent slot format matches duration regex', () async {
      // Valid durations
      final validDurations = ['5m', '10s', '2h', '1m'];
      for (final duration in validDurations) {
        final intent = Intent(
          tool: 'REMINDER',
          slots: {
            'target': 'mom',
            'duration': duration,
            'message': null,
          },
          reasoning: 'Test duration: $duration',
          slotConfidence: {'target': 0.95, 'duration': 0.98, 'message': 0.0},
          executionOrder: 1,
        );

        final result = await executor.execute(intent);
        expect(result.status, equals(ExecutionStatus.success),
            reason: 'Duration $duration should be valid');
      }
    });

    test('rejects invalid duration formats', () async {
      final invalidDurations = ['5', '5m30s', 'abc', '5x', 'm5'];
      for (final duration in invalidDurations) {
        final intent = Intent(
          tool: 'REMINDER',
          slots: {
            'target': 'mom',
            'duration': duration,
            'message': null,
          },
          reasoning: 'Test invalid duration: $duration',
          slotConfidence: {'target': 0.95, 'duration': 0.5, 'message': 0.0},
          executionOrder: 1,
        );

        final result = await executor.execute(intent);
        expect(result.status, equals(ExecutionStatus.failed),
            reason: 'Duration $duration should be invalid');
      }
    });

    test('handles tool that returns failure gracefully', () async {
      final intent = Intent(
        tool: 'MESSAGE',
        slots: {
          'target': 'unknown_person', // MockMessageTool will fail for this
          'content': 'hello',
        },
        reasoning: 'Send to non-existent contact.',
        slotConfidence: {'target': 0.3, 'content': 0.9},
        executionOrder: 1,
      );

      final result = await executor.execute(intent);

      expect(result.status, equals(ExecutionStatus.failed));
      expect(result.failure!.type, equals(ExecutionFailureType.toolReturnedFailure));
      expect(result.failure!.message, contains('not found'));

      // Trainer should receive the failure signal
      expect(trainer.lastFailureSignal, isNotNull);
      expect(trainer.lastFailureSignal!['failure_type'],
          equals('toolReturnedFailure'));
    });
  });
}
