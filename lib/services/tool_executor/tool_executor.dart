/// Tool Executor - Orchestrates tool invocation with validation and error handling
///
/// Real responsibilities:
/// 1. Validate tools exist in registry
/// 2. Validate required slots are present
/// 3. Validate slot types match schema
/// 4. Invoke actual tool implementations
/// 5. Wrap outcomes and report to Trainer
///
/// Tool implementations themselves are mocked (don't do real actions)

import 'package:everything_stack_template/services/intent_engine/tool_registry.dart';
import 'package:everything_stack_template/services/intent_engine/intent_engine.dart';
import 'slot_type_validator.dart';

export 'slot_type_validator.dart';
export 'package:everything_stack_template/services/intent_engine/intent_engine.dart' show Intent;

enum ExecutionFailureType {
  requiredSlotMissing,    // Required slot is null
  slotTypeMismatch,       // Slot value doesn't match type
  slotValidationError,    // Generic slot validation failure
  invalidSlotFormat,      // Slot format invalid (e.g., duration "abc")
  toolNotFound,           // Tool not in registry
  toolExecutionError,     // Tool.invoke() threw exception
  toolReturnedFailure,    // Tool.invoke() returned failure
  ambiguousEntity,        // Contact has multiple matches
  entityNotFound,         // Contact doesn't exist in system
  unknown,
}

enum ExecutionStatus {
  success,
  failed,
  skipped,
}

class ExecutionFailure {
  final ExecutionFailureType type;
  final String message;
  final String? slotName;
  final double? slotConfidence;
  final String? originalUtterance;
  final Map<String, dynamic>? attemptedSlots;
  final List<String>? ambiguousValues;

  ExecutionFailure({
    required this.type,
    required this.message,
    this.slotName,
    this.slotConfidence,
    this.originalUtterance,
    this.attemptedSlots,
    this.ambiguousValues,
  });

  String get typeString => type.toString().split('.').last;
}

class ToolResult {
  final bool success;
  final String? message;
  final Map<String, dynamic>? metadata;

  ToolResult({
    required this.success,
    this.message,
    this.metadata,
  });
}

abstract class Tool {
  /// Tool name (e.g., 'REMINDER', 'MESSAGE')
  String get name;

  /// Invoke this tool with filled and validated slots
  /// Returns success or failure
  /// Handles semantic validation: does contact exist, is time valid, etc
  Future<ToolResult> invoke(Map<String, dynamic> slots);
}

// Intent is defined in intent_engine.dart and exported above

class ExecutionResult {
  final ExecutionStatus status;
  final String? message;
  final ExecutionFailure? failure;
  final ToolResult? toolResult;

  ExecutionResult({
    required this.status,
    this.message,
    this.failure,
    this.toolResult,
  });
}

abstract class Trainer {
  void recordSuccess({
    required String tool,
    required Map<String, dynamic> slotsUsed,
    required String reasoning,
    Map<String, dynamic>? metadata,
  });

  void recordFailure({
    required String tool,
    required String failureType,
    required String message,
    String? slotAffected,
    double? slotConfidenceAtFailure,
  });
}

class ToolExecutor {
  final ToolRegistry toolRegistry;
  final Trainer trainer;
  final Map<String, Tool> toolImplementations;

  ToolExecutor({
    required this.toolRegistry,
    required this.trainer,
    required this.toolImplementations,
  });

  /// Execute a single intent
  /// Validates slots, invokes tool, reports outcome to Trainer
  Future<ExecutionResult> execute(Intent intent) async {
    // 1. Validate tool exists in registry
    if (!toolRegistry.hasToolNamed(intent.tool)) {
      final failure = ExecutionFailure(
        type: ExecutionFailureType.toolNotFound,
        message: 'Tool "${intent.tool}" not found in registry',
      );

      trainer.recordFailure(
        tool: intent.tool,
        failureType: failure.typeString,
        message: failure.message,
      );

      return ExecutionResult(
        status: ExecutionStatus.failed,
        failure: failure,
      );
    }

    final toolDef = toolRegistry.getToolByName(intent.tool)!;

    // 2. Validate required slots are present (non-null)
    for (final slotName in toolDef.slots.keys) {
      final slotDef = toolDef.slots[slotName]!;
      final isRequired = slotDef['required'] == true;
      final slotValue = intent.slots[slotName];

      if (isRequired && slotValue == null) {
        final confidence = intent.slotConfidence[slotName];
        final failure = ExecutionFailure(
          type: ExecutionFailureType.requiredSlotMissing,
          message: 'Required slot "$slotName" is null',
          slotName: slotName,
          slotConfidence: confidence != null ? confidence.toDouble() : 0.0,
        );

        trainer.recordFailure(
          tool: intent.tool,
          failureType: failure.typeString,
          message: failure.message,
          slotAffected: slotName,
          slotConfidenceAtFailure: failure.slotConfidence,
        );

        return ExecutionResult(
          status: ExecutionStatus.failed,
          failure: failure,
        );
      }
    }

    // 3. Validate slot types match schema
    final typeErrors = SlotTypeValidator.validateAll(
      slots: intent.slots,
      slotDefinitions: toolDef.slots,
    );

    if (typeErrors.isNotEmpty) {
      final firstError = typeErrors.first;
      final failure = ExecutionFailure(
        type: ExecutionFailureType.invalidSlotFormat,
        message: firstError.toString(),
        slotName: firstError.slotName,
      );

      trainer.recordFailure(
        tool: intent.tool,
        failureType: failure.typeString,
        message: failure.message,
        slotAffected: firstError.slotName,
      );

      return ExecutionResult(
        status: ExecutionStatus.failed,
        failure: failure,
      );
    }

    // 4. Get tool implementation
    final toolImpl = toolImplementations[intent.tool];
    if (toolImpl == null) {
      final failure = ExecutionFailure(
        type: ExecutionFailureType.toolNotFound,
        message: 'Tool implementation for "${intent.tool}" not registered',
      );

      trainer.recordFailure(
        tool: intent.tool,
        failureType: failure.typeString,
        message: failure.message,
      );

      return ExecutionResult(
        status: ExecutionStatus.failed,
        failure: failure,
      );
    }

    // 5. Invoke tool with validated slots
    ToolResult result;
    try {
      result = await toolImpl.invoke(intent.slots);
    } catch (e) {
      final failure = ExecutionFailure(
        type: ExecutionFailureType.toolExecutionError,
        message: 'Tool execution threw: $e',
      );

      trainer.recordFailure(
        tool: intent.tool,
        failureType: failure.typeString,
        message: failure.message,
      );

      return ExecutionResult(
        status: ExecutionStatus.failed,
        failure: failure,
      );
    }

    // 6. Wrap outcome and report to Trainer
    if (result.success) {
      trainer.recordSuccess(
        tool: intent.tool,
        slotsUsed: intent.slots,
        reasoning: intent.reasoning,
        metadata: result.metadata,
      );

      return ExecutionResult(
        status: ExecutionStatus.success,
        message: result.message ?? 'Tool executed successfully',
        toolResult: result,
      );
    } else {
      final failure = ExecutionFailure(
        type: ExecutionFailureType.toolReturnedFailure,
        message: result.message ?? 'Tool returned failure',
      );

      trainer.recordFailure(
        tool: intent.tool,
        failureType: failure.typeString,
        message: failure.message,
      );

      return ExecutionResult(
        status: ExecutionStatus.failed,
        failure: failure,
        toolResult: result,
      );
    }
  }

  /// Execute a list of intents in order
  /// Continues on failure - collects all results
  /// Allows partial success (first tool succeeds, second fails)
  Future<List<ExecutionResult>> executeAll(List<Intent> intents) async {
    final results = <ExecutionResult>[];

    for (final intent in intents) {
      final result = await execute(intent);
      results.add(result);
      // Continue regardless of success/failure - collect all results
    }

    return results;
  }
}
