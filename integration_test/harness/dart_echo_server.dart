/// # Dart WebSocket Echo Server
///
/// Pure Dart implementation - no Node.js dependency.
/// Works on ALL platforms (Android, iOS, web, desktop, CI).
///
/// ## How It Works
///
/// Integration tests run in Dart VM on HOST machine, even when testing
/// web/mobile builds. The app under test runs in browser/emulator, but
/// the test harness (including this server) runs on the host.
///
/// ## Endpoints
///
/// - ws://localhost:8080/echo - Simple echo (text/binary)
/// - ws://localhost:8080/fail-connect - Immediate rejection
/// - ws://localhost:8080/disconnect-after/N - Disconnect after N messages
/// - ws://localhost:8080/slow-echo/MS - Echo with MS millisecond delay

import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';

/// Global reference to echo server
HttpServer? _echoServer;

/// Starts the WebSocket echo server.
///
/// Returns true if server started successfully, false if fallback needed.
Future<bool> startDartEchoServer() async {
  if (_echoServer != null) {
    debugPrint('⚠️ Echo server already running');
    return true;
  }

  try {
    debugPrint('🚀 Starting Dart echo server...');

    // Bind to localhost:8080
    _echoServer = await HttpServer.bind('localhost', 8080);
    debugPrint('✅ Echo server listening on ws://localhost:8080');

    // Handle incoming connections
    _echoServer!.listen((HttpRequest request) {
      final path = request.uri.path;

      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('WebSocket upgrade required')
          ..close();
        return;
      }

      // Reject /fail-connect before WebSocket upgrade
      if (path == '/fail-connect') {
        debugPrint('[echo-server] Rejecting connection: /fail-connect');
        request.response
          ..statusCode = HttpStatus.forbidden
          ..write('Connection rejected')
          ..close();
        return;
      }

      // Upgrade to WebSocket
      WebSocketTransformer.upgrade(request).then((WebSocket socket) {
        _handleWebSocket(socket, path);
      }).catchError((error) {
        debugPrint('[echo-server] WebSocket upgrade failed: $error');
      });
    });

    return true;
  } catch (e) {
    debugPrint('⚠️ Could not start Dart echo server: $e');
    debugPrint('   Tests will use fallback configuration');
    _echoServer = null;
    return false;
  }
}

/// Handles WebSocket connection based on endpoint path
void _handleWebSocket(WebSocket socket, String path) {
  debugPrint('[echo-server] Client connected: $path');

  // Parse disconnect-after endpoint
  final disconnectMatch = RegExp(r'/disconnect-after/(\d+)').firstMatch(path);
  int? disconnectAfter = disconnectMatch != null
      ? int.tryParse(disconnectMatch.group(1)!)
      : null;
  int messageCount = 0;

  // Parse slow-echo endpoint
  final slowMatch = RegExp(r'/slow-echo/(\d+)').firstMatch(path);
  int? delayMs = slowMatch != null
      ? int.tryParse(slowMatch.group(1)!)
      : null;

  socket.listen(
    (message) {
      messageCount++;

      // Check disconnect condition
      if (disconnectAfter != null && messageCount >= disconnectAfter) {
        debugPrint('[echo-server] Disconnect after $messageCount messages');
        // Use goingAway (1001) to trigger ConnectionLostException in transport
        socket.close(WebSocketStatus.goingAway, 'Reached message limit');
        return;
      }

      // Echo with optional delay
      if (delayMs != null) {
        Future.delayed(Duration(milliseconds: delayMs), () {
          if (socket.readyState == WebSocket.open) {
            socket.add(message);
          }
        });
      } else {
        socket.add(message);
      }
    },
    onDone: () {
      debugPrint('[echo-server] Client disconnected');
    },
    onError: (error) {
      debugPrint('[echo-server] Error: $error');
      socket.close(WebSocketStatus.internalServerError, 'Server error');
    },
  );
}

/// Stops the echo server if it's running.
Future<void> stopDartEchoServer() async {
  if (_echoServer == null) {
    return;
  }

  try {
    debugPrint('🛑 Stopping Dart echo server...');
    await _echoServer!.close();
    debugPrint('✅ Echo server stopped');
  } catch (e) {
    debugPrint('⚠️ Error stopping echo server: $e');
  } finally {
    _echoServer = null;
  }
}

/// Returns true if echo server is currently running.
bool isDartEchoServerRunning() {
  return _echoServer != null;
}
