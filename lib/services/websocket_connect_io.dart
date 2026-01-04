/// Native WebSocket connection using IOWebSocketChannel
///
/// This provides the real WebSocket implementation for native platforms
/// (Android, iOS, macOS, Windows, Linux) using dart:io.
library;

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connect to a WebSocket with optional headers (native platforms)
WebSocketChannel connectWebSocket(Uri uri, {Map<String, dynamic>? headers}) {
  return IOWebSocketChannel.connect(uri, headers: headers);
}
