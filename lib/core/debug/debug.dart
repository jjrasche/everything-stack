/// # Debug Infrastructure
///
/// Core abstractions for component introspection and debug actions.
///
/// ## Architecture
/// ```
/// ┌─────────────────────┐
/// │   DebugRegistry     │  ← Central registry (singleton)
/// └─────────┬───────────┘
///           │ collects
///           ▼
/// ┌─────────────────────┐
/// │ DebugIntrospectable │  ← Mixin for components
/// │  - getDebugState()  │
/// │  - getDebugActions()│
/// └─────────────────────┘
///           │
///           ▼
/// ┌─────────────────────┐
/// │    DebugServer      │  ← HTTP transport (optional)
/// │   (services/debug)  │
/// └─────────────────────┘
/// ```
///
/// ## Usage Pattern
/// 1. Component implements DebugIntrospectable
/// 2. Bootstrap registers component with DebugRegistry
/// 3. DebugServer (or other transport) exposes registry via HTTP/WebSocket/etc.
/// 4. AI agents, CLI tools, tests can query and invoke actions

export 'debug_introspectable.dart';
export 'debug_registry.dart';
