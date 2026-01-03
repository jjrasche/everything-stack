/// WebSocket factory for web platform
///
/// Uses HtmlWebSocketChannel from dart:html for browser WebSocket connections.
/// Note: Web WebSockets don't support custom headers in the initial handshake.
/// For APIs requiring auth headers, the token must be passed in the URL or
/// as a subprotocol.
library;

import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Create a WebSocket channel using dart:html (web platform)
///
/// Note: The [headers] parameter is ignored on web as browsers don't allow
/// custom headers on WebSocket connections. For Deepgram, authentication
/// must be handled differently on web (e.g., using a proxy or query params).
WebSocketChannel createWebSocketChannel(Uri uri, {Map<String, dynamic>? headers}) {
  // Web doesn't support custom headers on WebSocket
  // Deepgram requires the token in the URL for web
  return HtmlWebSocketChannel.connect(uri);
}
