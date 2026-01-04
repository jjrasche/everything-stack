/// Web WebSocket connection using HtmlWebSocketChannel
///
/// This provides the real WebSocket implementation for web platform
/// using dart:html. Note: Web browsers don't support custom headers
/// on WebSocket connections, so the headers parameter is ignored.
library;

import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connect to a WebSocket (web platform - headers not supported)
///
/// Note: The [headers] parameter is ignored on web as browsers don't allow
/// custom headers on WebSocket connections. Authentication must be passed
/// via URL parameters or other mechanisms.
WebSocketChannel connectWebSocket(Uri uri, {Map<String, dynamic>? headers}) {
  // Web doesn't support custom WebSocket headers - ignore headers param
  return HtmlWebSocketChannel.connect(uri);
}
