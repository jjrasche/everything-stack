/// WebSocket factory for native platforms (Android, iOS, macOS, Windows, Linux)
///
/// Uses IOWebSocketChannel from dart:io for native WebSocket connections.
library;

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Create a WebSocket channel using dart:io (native platforms)
WebSocketChannel createWebSocketChannel(Uri uri, {Map<String, dynamic>? headers}) {
  return IOWebSocketChannel.connect(
    uri,
    headers: headers,
  );
}
