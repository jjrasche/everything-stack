/// # Transport Factory
///
/// Platform-aware factory for creating Transport instances.
/// Uses conditional imports to select the appropriate implementation:
/// - Web: [BrowserWebSocketTransport] using browser WebSocket API
/// - Native: [RustWebSocketTransport] using Rust tungstenite (fixes Windows bug)
///
/// ## Phase 2 Complete
/// Native platforms now use Rust FFI transport which fixes Windows wss:// bug.
///
/// ## Usage
/// ```dart
/// final factory = createTransportFactory();
/// final transport = factory.create(config);
/// await transport.connect();
/// ```

import 'transport.dart';

// Conditional import: Rust on native, browser WebSocket on web
import 'rust_websocket_transport.dart' if (dart.library.html) 'web_websocket_transport.dart'
    as platform;

/// Create a platform-appropriate [TransportFactory].
///
/// Returns:
/// - [BrowserWebSocketTransportFactory] on web platform
/// - [RustWebSocketTransportFactory] on native platforms (Windows, macOS, iOS, Android, Linux)
TransportFactory createTransportFactory() {
  return platform.createPlatformTransportFactory();
}
