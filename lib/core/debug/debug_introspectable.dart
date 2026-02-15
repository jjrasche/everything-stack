/// # DebugIntrospectable
///
/// Mixin for services/components that want to expose debug state and actions.
/// Components self-describe how they should be viewed and interacted with.
///
/// ## Why This Exists
/// - Components know their own internals best
/// - Centralized debug infrastructure doesn't need component-specific knowledge
/// - New components auto-integrate with debug tools by implementing this mixin
/// - AI agents can discover what's available without hardcoding
///
/// ## Usage
/// ```dart
/// class ChunkingService with Trainable, DebugIntrospectable {
///   @override
///   String get debugName => 'chunking';
///
///   @override
///   Map<String, dynamic> getDebugState() => {
///     'indexSize': index.size,
///     'isConsistent': isIndexConsistent(),
///   };
///
///   @override
///   Map<String, DebugAction> getDebugActions() => {
///     'rebuild': DebugAction(
///       description: 'Rebuild HNSW index from database',
///       handler: (params) async {
///         await rebuildIndexFromStorage();
///         return {'success': true, 'newSize': index.size};
///       },
///     ),
///   };
/// }
/// ```

/// Handler for debug actions.
/// Takes parameters map, returns result map.
typedef DebugActionHandler = Future<Map<String, dynamic>> Function(
    Map<String, String> params);

/// Describes a debug action that can be invoked on a component.
class DebugAction {
  /// Human-readable description of what this action does.
  final String description;

  /// The handler that executes this action.
  final DebugActionHandler handler;

  /// Parameter descriptions (for discoverability).
  final Map<String, String> parameters;

  /// Whether this action modifies state (vs read-only).
  final bool mutates;

  const DebugAction({
    required this.description,
    required this.handler,
    this.parameters = const {},
    this.mutates = false,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'parameters': parameters,
        'mutates': mutates,
      };
}

/// Mixin for components that expose debug state and actions.
///
/// Implement this to make your component discoverable and controllable
/// via debug infrastructure (HTTP server, CLI, AI agents, etc.).
mixin DebugIntrospectable {
  /// Unique name for this component in debug output.
  /// Should be lowercase, no spaces (e.g., 'chunking', 'semantic_search').
  String get debugName;

  /// Current state snapshot for debugging.
  /// Called synchronously - don't do expensive operations here.
  /// For expensive state gathering, expose as a debug action instead.
  Map<String, dynamic> getDebugState();

  /// Actions that can be invoked on this component.
  /// Key is action name, value describes the action.
  /// Return empty map if no actions available.
  Map<String, DebugAction> getDebugActions() => {};
}
