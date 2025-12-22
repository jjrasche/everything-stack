/// # MCPServerRegistry
///
/// ## What it does
/// Maps tool names to MCP servers.
/// Handles routing: "task.create" → task-server endpoint.
///
/// ## Usage
/// ```dart
/// final registry = MCPServerRegistry();
/// registry.register('task', MCPServer(
///   name: 'task-server',
///   endpoint: 'http://localhost:3000',
/// ));
///
/// final server = registry.findServer('task.create'); // Returns task-server
/// ```

class MCPServerRegistry {
  final Map<String, MCPServer> _servers = {};

  /// Register a server for a namespace
  void register(String namespace, MCPServer server) {
    _servers[namespace] = server;
  }

  /// Find server that implements a tool
  MCPServer? findServer(String toolName) {
    // Extract namespace from tool name (e.g., "task.create" → "task")
    final parts = toolName.split('.');
    if (parts.isEmpty) return null;

    final namespace = parts.first;
    return _servers[namespace];
  }

  /// Get all registered servers
  List<MCPServer> get servers => _servers.values.toList();

  /// Check if a namespace is registered
  bool hasNamespace(String namespace) => _servers.containsKey(namespace);

  /// Clear all registrations
  void clear() => _servers.clear();
}

/// Represents an MCP server
class MCPServer {
  final String name;
  final String endpoint;
  final Map<String, dynamic> metadata;

  MCPServer({
    required this.name,
    required this.endpoint,
    this.metadata = const {},
  });

  /// Get full URL for a path
  String url(String path) {
    final cleanEndpoint = endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$cleanEndpoint$cleanPath';
  }

  @override
  String toString() => 'MCPServer($name @ $endpoint)';
}
