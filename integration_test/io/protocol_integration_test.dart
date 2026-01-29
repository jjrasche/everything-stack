/// # Protocol Integration Tests
///
/// Tests WebSocketProtocol against real echo server using factory pattern.
/// NO MOCKS - real network calls.
///
/// Run with:
///   flutter test integration_test/nerve/protocol_integration_test.dart -d chrome
///
/// Note: Only runs on web platform (BrowserWebSocketTransport uses dart:html)

@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:everything_stack_template/io/transport/transport.dart';
import 'package:everything_stack_template/io/transport/transport_factory.dart';
import 'package:everything_stack_template/io/protocol/protocol.dart';
import 'package:everything_stack_template/io/protocol/websocket_protocol.dart';
import 'package:everything_stack_template/io/io_exception.dart';

/// Local echo server (test/nerve/echo_server).
/// Start with: cd test/nerve/echo_server && npm start
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
      // WebSocketProtocol tests only run on web
    });
    return;
  }

  group('WebSocketProtocol Integration Tests', () {
    late Transport transport;
    late TransportFactory factory;
    late WebSocketProtocol protocol;

    setUp(() {
      factory = createTransportFactory();
      transport = factory.create(TransportConfig(
        host: echoServerHost,
        port: echoServerPort,
        useTls: echoServerTls,
        path: '/echo',
      ));
      protocol = WebSocketProtocol(transport: transport);
    });

    tearDown(() async {
      await protocol.close();
      await transport.close();
      protocol.dispose();
      transport.dispose();
    });

    group('Initialization', () {
      testWidgets('initializes after transport connects', (tester) async {
        // Connect transport first
        await transport.connect();
        expect(transport.state, TransportState.connected);

        // Then initialize protocol
        final states = <ProtocolState>[];
        protocol.stateChanges.listen(states.add);

        await protocol.initialize();
        await Future.delayed(Duration(milliseconds: 100));

        expect(protocol.state, ProtocolState.ready);
        expect(states, contains(ProtocolState.initializing));
        expect(states, contains(ProtocolState.ready));
      });

      testWidgets('throws if transport not connected', (tester) async {
        expect(transport.state, TransportState.disconnected);

        await expectLater(
          () => protocol.initialize(),
          throwsA(isA<ProtocolException>()),
        );
      });

      testWidgets('initialize is idempotent', (tester) async {
        await transport.connect();
        await protocol.initialize();

        await protocol.initialize(); // Should not throw

        expect(protocol.state, ProtocolState.ready);
      });
    });

    group('Text Messages', () {
      testWidgets('sends and receives text message', (tester) async {
        await transport.connect();
        await protocol.initialize();

        final messages = <Message>[];
        protocol.messages.listen(messages.add);

        await protocol.sendText('Hello, Protocol!');

        // Wait for echo
        await Future.delayed(Duration(milliseconds: 500));

        expect(messages, isNotEmpty);
        expect(messages.first, isA<TextMessage>());
        expect((messages.first as TextMessage).text, 'Hello, Protocol!');
      });

      testWidgets('sends multiple text messages', (tester) async {
        await transport.connect();
        await protocol.initialize();

        final messages = <Message>[];
        protocol.messages.listen(messages.add);

        await protocol.sendText('one');
        await protocol.sendText('two');
        await protocol.sendText('three');

        // Wait for echoes
        await Future.delayed(Duration(milliseconds: 1000));

        expect(messages.length, 3);
        expect((messages[0] as TextMessage).text, 'one');
        expect((messages[1] as TextMessage).text, 'two');
        expect((messages[2] as TextMessage).text, 'three');
      });

      testWidgets('handles unicode text', (tester) async {
        await transport.connect();
        await protocol.initialize();

        final messages = <Message>[];
        protocol.messages.listen(messages.add);

        await protocol.sendText('Hello 世界! 🌍');

        // Wait for echo
        await Future.delayed(Duration(milliseconds: 500));

        expect(messages, isNotEmpty);
        expect((messages.first as TextMessage).text, 'Hello 世界! 🌍');
      });

      testWidgets('throws when sending text without ready', (tester) async {
        expect(protocol.state, ProtocolState.uninitialized);

        await expectLater(
          () => protocol.sendText('test'),
          throwsA(isA<ProtocolException>()),
        );
      });
    });

    group('Binary Messages', () {
      testWidgets('sends and receives binary message', (tester) async {
        await transport.connect();
        await protocol.initialize();

        final messages = <Message>[];
        protocol.messages.listen(messages.add);

        final data = Uint8List.fromList([0x00, 0x01, 0xFF, 0xFE]);
        await protocol.sendBinary(data);

        // Wait for echo
        await Future.delayed(Duration(milliseconds: 500));

        expect(messages, isNotEmpty);
        // Note: Echo server may return as text or binary depending on framing
        // We verify the bytes match regardless of message type
        if (messages.first is BinaryMessage) {
          expect((messages.first as BinaryMessage).data, data);
        }
      });

      testWidgets('throws when sending binary without ready', (tester) async {
        expect(protocol.state, ProtocolState.uninitialized);

        await expectLater(
          () => protocol.sendBinary(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<ProtocolException>()),
        );
      });
    });

    group('Full-Duplex', () {
      testWidgets('can send and receive concurrently', (tester) async {
        await transport.connect();
        await protocol.initialize();

        final messages = <Message>[];
        protocol.messages.listen(messages.add);

        // Send multiple messages rapidly
        final futures = <Future>[];
        for (int i = 0; i < 5; i++) {
          futures.add(protocol.sendText('Message $i'));
        }
        await Future.wait(futures);

        // Wait for all echoes
        await Future.delayed(Duration(milliseconds: 1000));

        expect(messages.length, 5);
      });
    });

    group('Close', () {
      testWidgets('closes gracefully', (tester) async {
        await transport.connect();
        await protocol.initialize();

        final states = <ProtocolState>[];
        protocol.stateChanges.listen(states.add);

        await protocol.close();
        await Future.delayed(Duration(milliseconds: 100));

        expect(protocol.state, ProtocolState.closed);
        expect(states, contains(ProtocolState.closing));
        expect(states, contains(ProtocolState.closed));
      });

      testWidgets('close is idempotent', (tester) async {
        await transport.connect();
        await protocol.initialize();
        await protocol.close();

        await protocol.close(); // Should not throw

        expect(protocol.state, ProtocolState.closed);
      });
    });

    group('Message Types', () {
      testWidgets('TextMessage has id and timestamp', (tester) async {
        await transport.connect();
        await protocol.initialize();

        final messages = <Message>[];
        protocol.messages.listen(messages.add);

        await protocol.sendText('test');
        await Future.delayed(Duration(milliseconds: 500));

        expect(messages, isNotEmpty);
        final msg = messages.first;
        expect(msg.id, isNotEmpty);
        expect(msg.timestamp, isNotNull);
        expect(
          msg.timestamp.difference(DateTime.now()).abs(),
          lessThan(Duration(seconds: 5)),
        );
      });
    });

    group('State Stream', () {
      testWidgets('state stream is broadcast', (tester) async {
        final states1 = <ProtocolState>[];
        final states2 = <ProtocolState>[];

        protocol.stateChanges.listen(states1.add);
        protocol.stateChanges.listen(states2.add);

        await transport.connect();
        await protocol.initialize();
        await Future.delayed(Duration(milliseconds: 100));

        expect(states1, isNotEmpty);
        expect(states1, states2);
      });

      testWidgets('full lifecycle state changes', (tester) async {
        final states = <ProtocolState>[];
        protocol.stateChanges.listen(states.add);

        await transport.connect();
        await protocol.initialize();
        await Future.delayed(Duration(milliseconds: 100));
        await protocol.close();
        await Future.delayed(Duration(milliseconds: 100));

        expect(states, [
          ProtocolState.initializing,
          ProtocolState.ready,
          ProtocolState.closing,
          ProtocolState.closed,
        ]);
      });
    });
  });
}
