/// Standalone test to verify Dart echo server works (pure Dart, no Flutter)
import 'dart:io';
import 'package:test/test.dart';

void main() {
  HttpServer? server;

  test('Dart echo server works', () async {
    // Start server
    server = await HttpServer.bind('localhost', 8888);
    print('✅ Server started on ws://localhost:8888');

    // Handle connections
    server!.listen((HttpRequest request) {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        WebSocketTransformer.upgrade(request).then((WebSocket socket) {
          socket.listen((message) {
            socket.add(message); // Echo back
          });
        });
      }
    });

    // Give server time to start
    await Future.delayed(const Duration(milliseconds: 200));

    // Connect client
    final client = await WebSocket.connect('ws://localhost:8888');
    print('✅ Client connected');

    // Send message
    client.add('Hello!');

    // Receive echo
    final response = await client.first;
    expect(response, 'Hello!');
    print('✅ Echo received: $response');

    // Cleanup
    await client.close();
    await server!.close();
    print('✅ Server stopped');
  });
}
