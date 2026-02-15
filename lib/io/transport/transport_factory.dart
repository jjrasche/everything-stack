
import 'transport.dart';

// Conditional import: Rust on native, browser WebSocket on web
import 'rust_websocket_transport.dart'
    if (dart.library.html) 'web_websocket_transport.dart' as platform;

/// Create a platform-appropriate [TransportFactory].
///
/// Returns:
/// - [BrowserWebSocketTransportFactory] on web platform
/// - [RustWebSocketTransportFactory] on native platforms (Windows, macOS, iOS, Android, Linux)
TransportFactory createTransportFactory() {
  return platform.createPlatformTransportFactory();
}
