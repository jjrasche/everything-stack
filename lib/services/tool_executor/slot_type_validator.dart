/// SlotTypeValidator - Validates slot values match expected types
/// Two layers:
/// - ToolExecutor calls this for format/structure validation
/// - Tool.invoke() handles semantic validation (does contact exist, is time valid, etc)

class SlotTypeValidationError implements Exception {
  final String slotName;
  final String expectedType;
  final dynamic value;
  final String reason;

  SlotTypeValidationError({
    required this.slotName,
    required this.expectedType,
    required this.value,
    required this.reason,
  });

  @override
  String toString() =>
      'SlotTypeValidationError: Slot "$slotName" (type: $expectedType) failed validation. '
      'Value: $value. Reason: $reason';
}

class SlotTypeValidator {
  /// Validate a single slot value against its expected type
  /// Throws SlotTypeValidationError if validation fails
  static void validate({
    required String slotName,
    required dynamic value,
    required String expectedType,
  }) {
    // Null is allowed for optional slots
    if (value == null) {
      return;
    }

    switch (expectedType.toLowerCase()) {
      case 'contact':
        _validateContact(slotName, value);
        break;
      case 'duration':
        _validateDuration(slotName, value);
        break;
      case 'text':
        _validateText(slotName, value);
        break;
      case 'time':
        _validateTime(slotName, value);
        break;
      case 'number':
        _validateNumber(slotName, value);
        break;
      case 'boolean':
        _validateBoolean(slotName, value);
        break;
      default:
        // Unknown type - assume valid (tool will handle semantics)
        break;
    }
  }

  /// contact: Non-empty String
  /// Tool will check if it exists in entities
  static void _validateContact(String slotName, dynamic value) {
    if (value is! String) {
      throw SlotTypeValidationError(
        slotName: slotName,
        expectedType: 'contact',
        value: value,
        reason: 'Contact must be a String, got ${value.runtimeType}',
      );
    }

    if (value.isEmpty) {
      throw SlotTypeValidationError(
        slotName: slotName,
        expectedType: 'contact',
        value: value,
        reason: 'Contact cannot be empty',
      );
    }
  }

  /// duration: String matching pattern like "5m", "10s", "2h"
  /// Format: number followed by unit (s/m/h)
  static void _validateDuration(String slotName, dynamic value) {
    if (value is! String) {
      throw SlotTypeValidationError(
        slotName: slotName,
        expectedType: 'duration',
        value: value,
        reason: 'Duration must be a String, got ${value.runtimeType}',
      );
    }

    final regex = RegExp(r'^\d+[smh]$');
    if (!regex.hasMatch(value)) {
      throw SlotTypeValidationError(
        slotName: slotName,
        expectedType: 'duration',
        value: value,
        reason: 'Duration must match format like "5m", "10s", "2h". Got: $value',
      );
    }
  }

  /// text: Any non-empty String
  static void _validateText(String slotName, dynamic value) {
    if (value is! String) {
      throw SlotTypeValidationError(
        slotName: slotName,
        expectedType: 'text',
        value: value,
        reason: 'Text must be a String, got ${value.runtimeType}',
      );
    }

    if (value.isEmpty) {
      throw SlotTypeValidationError(
        slotName: slotName,
        expectedType: 'text',
        value: value,
        reason: 'Text cannot be empty',
      );
    }
  }

  /// time: DateTime or String in ISO format
  /// Tool will parse and validate if time is in future, etc.
  static void _validateTime(String slotName, dynamic value) {
    if (value is DateTime) {
      // DateTime is valid
      return;
    }

    if (value is String) {
      // Try to parse ISO format
      try {
        DateTime.parse(value);
        return; // Valid ISO format
      } catch (e) {
        throw SlotTypeValidationError(
          slotName: slotName,
          expectedType: 'time',
          value: value,
          reason: 'Time must be DateTime or ISO format string. Got: $value',
        );
      }
    }

    throw SlotTypeValidationError(
      slotName: slotName,
      expectedType: 'time',
      value: value,
      reason: 'Time must be DateTime or String, got ${value.runtimeType}',
    );
  }

  /// number: num (int or double)
  static void _validateNumber(String slotName, dynamic value) {
    if (value is! num) {
      throw SlotTypeValidationError(
        slotName: slotName,
        expectedType: 'number',
        value: value,
        reason: 'Number must be num (int or double), got ${value.runtimeType}',
      );
    }
  }

  /// boolean: bool
  static void _validateBoolean(String slotName, dynamic value) {
    if (value is! bool) {
      throw SlotTypeValidationError(
        slotName: slotName,
        expectedType: 'boolean',
        value: value,
        reason: 'Boolean must be bool, got ${value.runtimeType}',
      );
    }
  }

  /// Validate all slots in a map against their expected types from tool definition
  static List<SlotTypeValidationError> validateAll({
    required Map<String, dynamic> slots,
    required Map<String, Map<String, dynamic>> slotDefinitions,
  }) {
    final errors = <SlotTypeValidationError>[];

    for (final slotName in slotDefinitions.keys) {
      final slotDef = slotDefinitions[slotName]!;
      final slotValue = slots[slotName];
      final slotType = slotDef['type'] as String;

      try {
        validate(
          slotName: slotName,
          value: slotValue,
          expectedType: slotType,
        );
      } on SlotTypeValidationError catch (e) {
        errors.add(e);
      }
    }

    return errors;
  }
}
