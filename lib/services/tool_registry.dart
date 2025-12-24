/// # ToolRegistry
///
/// ## What it does
/// Registry for in-app tool handlers. Replaces MCPServerRegistry.
/// Provides MCP-style discovery (schemas) but executes tools via Dart functions, not HTTP.
///
/// ## Flow
/// 1. At bootstrap, register each tool with definition + handler
/// 2. ContextManager discovers tools via getToolsInNamespace()
/// 3. ToolExecutor calls handlers directly (no HTTP)
///
/// ## Usage
/// ```dart
/// final registry = ToolRegistry();
///
/// // Register a tool
/// registry.register(
///   ToolDefinition(
///     name: 'task.create',
///     namespace: 'task',
///     description: 'Create a new task',
///     parameters: {
///       'type': 'object',
///       'properties': {
///         'title': {'type': 'string'},
///         'priority': {'type': 'string', 'enum': ['low', 'medium', 'high']},
///       },
///       'required': ['title'],
///     },
///   ),
///   (params) async {
///     final task = Task(title: params['title']);
///     if (params['priority'] != null) task.priority = params['priority'];
///     await taskRepo.save(task);
///     return {'id': task.uuid, 'status': 'created'};
///   },
/// );
///
/// // Discover tools in namespace
/// final taskTools = registry.getToolsInNamespace('task');
///
/// // Get handler for execution
/// final handler = registry.getHandler('task.create');
/// final result = await handler({'title': 'Buy milk'});
/// ```

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

  /// Get tool handler by name
  ToolHandler? getHandler(String name) => _handlers[name];

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
