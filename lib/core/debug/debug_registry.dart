/// # DebugRegistry
///
/// Central registry for all debug-introspectable components.
/// Transport-agnostic - can be used by HTTP server, CLI, tests, AI agents.
///
/// ## How It Works
/// 1. Components implement DebugIntrospectable mixin
/// 2. Bootstrap registers them with DebugRegistry
/// 3. Debug tools query registry for state/actions
/// 4. Transport layers (HTTP, WebSocket) expose registry via their protocol
///
/// ## Usage
/// ```dart
/// // In bootstrap:
/// final registry = DebugRegistry.instance;
/// registry.register(chunkingService);
/// registry.register(semanticSearchService);
///
/// // Anywhere:
/// final state = registry.getAllState();  // Full snapshot
/// final result = await registry.invokeAction('chunking', 'rebuild', {});
/// ```

import 'debug_introspectable.dart';

class DebugRegistry {
  static final DebugRegistry instance = DebugRegistry._();
  DebugRegistry._();

  final Map<String, DebugIntrospectable> _components = {};

  /// Register a component for debug introspection.
  void register(DebugIntrospectable component) {
    _components[component.debugName] = component;
  }

  /// Unregister a component.
  void unregister(String debugName) {
    _components.remove(debugName);
  }

  /// Get list of registered component names.
  List<String> get componentNames => _components.keys.toList();

  /// Get state for a specific component.
  Map<String, dynamic>? getState(String componentName) {
    final component = _components[componentName];
    if (component == null) return null;

    try {
      return component.getDebugState();
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Get state for all registered components.
  Map<String, dynamic> getAllState() {
    final result = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'components': componentNames,
    };

    for (final entry in _components.entries) {
      try {
        result[entry.key] = entry.value.getDebugState();
      } catch (e) {
        result[entry.key] = {'error': e.toString()};
      }
    }

    return result;
  }

  /// Get available actions for a component.
  Map<String, dynamic>? getActions(String componentName) {
    final component = _components[componentName];
    if (component == null) return null;

    final actions = component.getDebugActions();
    return actions.map((name, action) => MapEntry(name, action.toJson()));
  }

  /// Get all available actions across all components.
  Map<String, Map<String, dynamic>> getAllActions() {
    final result = <String, Map<String, dynamic>>{};

    for (final entry in _components.entries) {
      final actions = entry.value.getDebugActions();
      if (actions.isNotEmpty) {
        result[entry.key] = actions.map(
          (name, action) => MapEntry(name, action.toJson()),
        );
      }
    }

    return result;
  }

  /// Invoke an action on a component.
  ///
  /// Returns null if component or action not found.
  /// Returns error map if action throws.
  Future<Map<String, dynamic>?> invokeAction(
    String componentName,
    String actionName,
    Map<String, String> params,
  ) async {
    final component = _components[componentName];
    if (component == null) {
      return {'error': 'Component not found: $componentName'};
    }

    final actions = component.getDebugActions();
    final action = actions[actionName];
    if (action == null) {
      return {
        'error': 'Action not found: $actionName',
        'available': actions.keys.toList(),
      };
    }

    try {
      return await action.handler(params);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Clear all registrations (for testing).
  void clear() {
    _components.clear();
  }
}
