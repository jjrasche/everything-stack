/// # Transport Factory
///
/// Platform-aware factory for creating Transport instances.
/// Uses conditional imports to select the appropriate implementation:
/// - Web: [BrowserWebSocketTransport] using browser WebSocket API
/// - Native: [NativeWebSocketTransport] using dart:io WebSocket (broken on Windows)
///
/// ## Usage
/// ```dart
/// final factory = createTransportFactory();
/// final transport = factory.create(config);
/// await transport.connect();
/// ```

import 'transport.dart';

// Conditional import: native by default, browser WebSocket if dart:html available
import 'native_websocket_transport.dart' if (dart.library.html) 'web_websocket_transport.dart'
    as platform;

/// Create a platform-appropriate [TransportFactory].
///
/// Returns:
/// - [BrowserWebSocketTransportFactory] on web platform
/// - [NativeWebSocketTransportFactory] on native platforms (broken on Windows)
TransportFactory createTransportFactory() {
  return platform.createPlatformTransportFactory();
}
