/// # Register Media Tools
///
/// Registers all media tools with a ToolRegistry.
/// Follows the pattern of registerTaskTools and registerTimerTools.
///
/// ## Usage
/// ```dart
/// final registry = ToolRegistry();
/// final factory = MediaHandlerFactory(
///   mediaRepo: mediaRepo,
///   downloadRepo: downloadRepo,
///   channelRepo: channelRepo,
/// );
/// registerMediaTools(registry, factory);
/// ```

import '../../../services/tool_registry.dart';
import 'media_handler_factory.dart';

/// Register all media tools with the registry
void registerMediaTools(
  ToolRegistry registry,
  MediaHandlerFactory factory,
) {
  factory.registerTools(registry);
}
