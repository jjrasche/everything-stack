/// WebSocket factory stub - default for non-io/non-html platforms
///
/// This stub throws an error if called on an unsupported platform.
library;

import 'package:web_socket_channel/web_socket_channel.dart';

/// Create a WebSocket channel (stub - throws on unsupported platforms)
WebSocketChannel createWebSocketChannel(Uri uri, {Map<String, dynamic>? headers}) {
  throw UnsupportedError('WebSocket not supported on this platform');
}
