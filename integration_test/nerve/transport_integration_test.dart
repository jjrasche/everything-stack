/// # Transport Integration Tests
///
/// Tests Transport layer against real echo server using factory pattern.
/// NO MOCKS - real network calls.
///
/// Run with:
///   flutter test integration_test/nerve/transport_integration_test.dart -d chrome
///
/// Note: Only runs on web platform (BrowserWebSocketTransport uses dart:html)

@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:everything_stack_template/nerve/transport/transport.dart';
import 'package:everything_stack_template/nerve/transport/transport_factory.dart';
import 'package:everything_stack_template/nerve/nerve_exception.dart';

/// Local echo server (test/nerve/echo_server).
/// Start with: cd test/nerve/echo_server && npm start
///
/// Falls back to public echo server if local not available.
const localEchoHost = 'localhost';
const localEchoPort = 8080;
const localEchoTls = false;

/// Public fallback echo server.
const publicEchoHost = 'echo.websocket.events';
const publicEchoPort = 443;
const publicEchoTls = true;

// Use local server by default (for CI with controllable server)
const echoServerHost = localEchoHost;
const echoServerPort = localEchoPort;
const echoServerTls = localEchoTls;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Skip on native platforms - tests use browser WebSocket
  if (!kIsWeb) {
    test('skipped on native', () {
      // Transport tests only run on web
    });
    return;
  }

  group('Transport Integration Tests', () {
    late Transport transport;
    late TransportFactory factory;

    setUp(() {
      factory = createTransportFactory();
      transport = factory.create(TransportConfig(
        host: echoServerHost,
        port: echoServerPort,
        useTls: echoServerTls,
        path: '/echo',
      ));
    });

    tearDown(() async {
      await transport.close();
      transport.dispose();
    });

    group('Connection', () {
      testWidgets('connects to echo server', (tester) async {
        // Track state changes
        final states = <TransportState>[];
        transport.stateChanges.listen(states.add);

        expect(transport.state, TransportState.disconnected);

        await transport.connect();
        await Future.delayed(Duration(milliseconds: 100));

        expect(transport.state, TransportState.connected);
        expect(states, contains(TransportState.connecting));
        expect(states, contains(TransportState.connected));
      });

      testWidgets('connect is idempotent', (tester) async {
        await transport.connect();
        final stateAfterFirst = transport.state;

        await transport.connect(); // Should not throw

        expect(transport.state, stateAfterFirst);
      });

      testWidgets('fails with invalid host', (tester) async {
        final badTransport = factory.create(TransportConfig(
          host: 'invalid.host.that.does.not.exist.example',
          port: 443,
          useTls: true,
          connectTimeout: Duration(seconds: 5),
        ));

        await expectLater(
          () => badTransport.connect(),
          throwsA(anyOf(
            isA<ConnectionFailedException>(),
            isA<TimeoutException>(),
          )),
        );

        expect(badTransport.state, TransportState.disconnected);
        badTransport.dispose();
      });
    });

    group('Send/Receive', () {
      testWidgets('sends and receives text message', (tester) async {
        await transport.connect();

        final received = <Uint8List>[];
        transport.received.listen(received.add);

        // Send text message (converted to bytes)
        final message = 'Hello, Echo Server!';
        final bytes = Uint8List.fromList(message.codeUnits);
        await transport.send(bytes);

        // Wait for echo
        await Future.delayed(Duration(milliseconds: 500));

        expect(received, isNotEmpty);
        final echoedMessage = String.fromCharCodes(received.first);
        expect(echoedMessage, message);
      });

      testWidgets('sends and receives binary message', (tester) async {
        await transport.connect();

        final received = <Uint8List>[];
        transport.received.listen(received.add);

        // Send binary data
        final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD]);
        await transport.send(bytes);

        // Wait for echo
        await Future.delayed(Duration(milliseconds: 500));

        expect(received, isNotEmpty);
        expect(received.first, bytes);
      });

      testWidgets('sends multiple messages in sequence', (tester) async {
        await transport.connect();

        final received = <Uint8List>[];
        transport.received.listen(received.add);

        // Send 3 messages
        for (int i = 0; i < 3; i++) {
          final message = 'Message $i';
          await transport.send(Uint8List.fromList(message.codeUnits));
        }

        // Wait for echoes
        await Future.delayed(Duration(milliseconds: 1000));

        expect(received.length, 3);
        expect(String.fromCharCodes(received[0]), 'Message 0');
        expect(String.fromCharCodes(received[1]), 'Message 1');
        expect(String.fromCharCodes(received[2]), 'Message 2');
      });

      testWidgets('throws when sending without connection', (tester) async {
        expect(transport.state, TransportState.disconnected);

        await expectLater(
          () => transport.send(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<ConnectionLostException>()),
        );
      });
    });

    group('Disconnect', () {
      testWidgets('closes gracefully', (tester) async {
        await transport.connect();
        expect(transport.state, TransportState.connected);

        final states = <TransportState>[];
        transport.stateChanges.listen(states.add);

        await transport.close();
        await Future.delayed(Duration(milliseconds: 100));

        expect(transport.state, TransportState.disconnected);
        expect(states, contains(TransportState.disconnecting));
        expect(states, contains(TransportState.disconnected));
      });

      testWidgets('close is idempotent', (tester) async {
        await transport.connect();
        await transport.close();

        await transport.close(); // Should not throw
        await transport.close(); // Should not throw

        expect(transport.state, TransportState.disconnected);
      });

      testWidgets('can close without connecting', (tester) async {
        expect(transport.state, TransportState.disconnected);

        await transport.close(); // Should not throw

        expect(transport.state, TransportState.disconnected);
      });
    });

    group('Full-Duplex', () {
      testWidgets('can receive while sending', (tester) async {
        await transport.connect();

        final received = <Uint8List>[];
        transport.received.listen(received.add);

        // Send multiple messages rapidly (simulating audio streaming)
        final futures = <Future>[];
        for (int i = 0; i < 5; i++) {
          futures.add(
            transport.send(Uint8List.fromList('Chunk $i'.codeUnits)),
          );
        }
        await Future.wait(futures);

        // Wait for all echoes
        await Future.delayed(Duration(milliseconds: 1000));

        // All messages should be received
        expect(received.length, 5);
      });
    });

    // Tests using local echo server controllable endpoints
    // Only run these when local server is configured
    group('Controllable Server (Local Only)', () {
      testWidgets('handles rejected connection', (tester) async {
        final transport = factory.create(TransportConfig(
            host: echoServerHost,
            port: echoServerPort,
            useTls: echoServerTls,
            path: '/fail-connect',
            connectTimeout: Duration(seconds: 5),
          ),
        );

        await expectLater(
          () => transport.connect(),
          throwsA(isA<ConnectionFailedException>()),
        );

        expect(transport.state, TransportState.disconnected);
        transport.dispose();
      });

      testWidgets('handles server-initiated disconnect', (tester) async {
        final transport = factory.create(TransportConfig(
            host: echoServerHost,
            port: echoServerPort,
            useTls: echoServerTls,
            path: '/disconnect-after/3',
          ),
        );

        await transport.connect();

        Object? receivedError;
        transport.received.listen(
          (_) {},
          onError: (e) => receivedError = e,
        );

        // Send 3 messages - server will disconnect after
        for (int i = 0; i < 3; i++) {
          await transport.send(Uint8List.fromList([i]));
        }

        // Wait for disconnect
        await Future.delayed(Duration(milliseconds: 500));

        expect(receivedError, isA<ConnectionLostException>());
        transport.dispose();
      });

      testWidgets('handles slow echo with delay', (tester) async {
        final transport = factory.create(TransportConfig(
            host: echoServerHost,
            port: echoServerPort,
            useTls: echoServerTls,
            path: '/slow-echo/200', // 200ms delay
          ),
        );

        await transport.connect();

        final received = <Uint8List>[];
        transport.received.listen(received.add);

        final startTime = DateTime.now();
        await transport.send(Uint8List.fromList('test'.codeUnits));

        // Wait for slow echo
        await Future.delayed(Duration(milliseconds: 500));

        expect(received, isNotEmpty);
        final elapsed = DateTime.now().difference(startTime);
        expect(elapsed.inMilliseconds, greaterThanOrEqualTo(200));

        await transport.close();
        transport.dispose();
      });
    }, skip: echoServerHost != localEchoHost ? 'Local server not configured' : null);

    group('State Stream', () {
      testWidgets('state stream is broadcast', (tester) async {
        final states1 = <TransportState>[];
        final states2 = <TransportState>[];

        transport.stateChanges.listen(states1.add);
        transport.stateChanges.listen(states2.add);

        await transport.connect();
        await Future.delayed(Duration(milliseconds: 100));

        expect(states1, isNotEmpty);
        expect(states1, states2);
      });

      testWidgets('full lifecycle state changes', (tester) async {
        final states = <TransportState>[];
        transport.stateChanges.listen(states.add);

        await transport.connect();
        await Future.delayed(Duration(milliseconds: 100));
        await transport.close();
        await Future.delayed(Duration(milliseconds: 100));

        expect(states, [
          TransportState.connecting,
          TransportState.connected,
          TransportState.disconnecting,
          TransportState.disconnected,
        ]);
      });
    });
  });
}
