/// Quick test to verify Dart echo server works
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';
import 'dart_echo_server.dart';

void main() {
  test('Dart echo server - basic echo', () async {
    // Start server
    final started = await startDartEchoServer();
    expect(started, true, reason: 'Server should start');

    // Wait for server to be ready
    await Future.delayed(const Duration(milliseconds: 500));

    // Connect client
    final channel = IOWebSocketChannel.connect('ws://localhost:8080/echo');
    await channel.ready;

    // Send message
    channel.sink.add('Hello, echo!');

    // Receive echo
    final response = await channel.stream.first;
    expect(response, 'Hello, echo!');

    // Cleanup
    await channel.sink.close();
    await stopDartEchoServer();
  });

  test('Dart echo server - fail-connect endpoint', () async {
    final started = await startDartEchoServer();
    expect(started, true);

    await Future.delayed(const Duration(milliseconds: 500));

    // Connect to fail endpoint
    final channel = IOWebSocketChannel.connect('ws://localhost:8080/fail-connect');

    // Should close immediately
    await expectLater(
      channel.stream.first,
      throwsA(isA<Exception>()),
    );

    await stopDartEchoServer();
  });
}
