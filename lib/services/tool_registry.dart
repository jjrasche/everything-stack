/// Tool handler function type
typedef ToolHandler = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> params);

class ToolRegistry {
  final Map<String, ToolDefinition> _tools = {};
  final Map<String, ToolHandler> _handlers = {};

  /// Register a tool with its definition and handler
  void register(ToolDefinition tool, ToolHandler handler) {
    _tools[tool.name] = tool;
    _handlers[tool.name] = handler;
  }

  /// Get all tools in a namespace
  List<ToolDefinition> getToolsInNamespace(String namespace) {
    return _tools.values.where((tool) => tool.namespace == namespace).toList();
  }

  /// Get tool definition by name
  ToolDefinition? getDefinition(String name) => _tools[name];

  /// Get tool function by name
  ToolHandler? getTool(String name) => _handlers[name];

  /// Get all tool definitions
  List<ToolDefinition> getAllTools() => _tools.values.toList();

  /// Get all namespace names
  List<String> getAllNamespaces() {
    return _tools.values.map((tool) => tool.namespace).toSet().toList();
  }
}

/// Tool definition (MCP-style schema)
class ToolDefinition {
  /// Full tool name: "task.create", "timer.set"
  final String name;

  /// Namespace: "task", "timer"
  final String namespace;

  /// Human-readable description for LLM
  final String description;

  /// JSON Schema for parameters
  final Map<String, dynamic> parameters;

  ToolDefinition({
    required this.name,
    required this.namespace,
    required this.description,
    required this.parameters,
  });

  /// Convert to LLMTool for LLM service
  Map<String, dynamic> toLLMTool() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}
