/// Tool Registry - Static definition of available tools and their slots
/// Injected into Intent Engine prompts at initialization

class ToolDefinition {
  /// Tool name (e.g., 'REMINDER', 'MESSAGE', 'ALARM')
  final String name;

  /// Human-readable description for LLM
  final String description;

  /// Slot definitions: {slotName: {type, required}}
  /// Example: {'target': {'type': 'contact', 'required': true}}
  final Map<String, Map<String, dynamic>> slots;

  ToolDefinition({
    required this.name,
    required this.description,
    required this.slots,
  });
}

class ToolRegistry {
  /// All available tools
  final List<ToolDefinition> tools;

  /// Index by tool name for quick lookup
  late final Map<String, ToolDefinition> _toolsByName;

  ToolRegistry({required this.tools}) {
    _toolsByName = {for (var tool in tools) tool.name: tool};
  }

  /// Check if a tool exists in the registry
  bool hasToolNamed(String name) {
    return _toolsByName.containsKey(name);
  }

  /// Get tool definition by name
  ToolDefinition? getToolByName(String name) {
    return _toolsByName[name];
  }

  /// Get all tool names
  List<String> getAllToolNames() {
    return tools.map((t) => t.name).toList();
  }

  /// Format registry for prompt injection (natural language)
  String formatForPrompt() {
    final buffer = StringBuffer();
    buffer.writeln('Available tools:');
    buffer.writeln();

    for (var i = 0; i < tools.length; i++) {
      final tool = tools[i];
      buffer.writeln('${i + 1}. ${tool.name} - ${tool.description}');

      for (final slotName in tool.slots.keys) {
        final slotDef = tool.slots[slotName]!;
        final type = slotDef['type'] ?? 'unknown';
        final required = slotDef['required'] == true ? 'required' : 'optional';
        buffer.writeln('   - $slotName ($type, $required)');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Validate that tool and slots match registry definition
  /// Returns null if valid, or error message if invalid
  String? validateIntentAgainstRegistry(Map<String, dynamic> intent) {
    final toolName = intent['tool'] as String?;
    if (toolName == null) {
      return 'Intent missing tool name';
    }

    if (!hasToolNamed(toolName)) {
      return 'Tool "$toolName" not found in registry';
    }

    final toolDef = getToolByName(toolName)!;
    final slots = intent['slots'] as Map?;
    if (slots == null) {
      return 'Intent missing slots object';
    }

    // Check for slots in intent that aren't in registry
    for (final slotName in slots.keys) {
      if (!toolDef.slots.containsKey(slotName)) {
        return 'Slot "$slotName" not defined for tool "$toolName"';
      }
    }

    return null; // Valid
  }
}

/// Exception thrown when intent references unknown tool
class UnknownToolException implements Exception {
  final String toolName;
  final String message;

  UnknownToolException(this.toolName, this.message);

  @override
  String toString() => 'UnknownToolException: $message';
}

/// Exception thrown when intent has slots not in registry
class SlotDefinitionMismatchException implements Exception {
  final String toolName;
  final String slotName;
  final String message;

  SlotDefinitionMismatchException(this.toolName, this.slotName, this.message);

  @override
  String toString() => 'SlotDefinitionMismatchException: $message';
}
