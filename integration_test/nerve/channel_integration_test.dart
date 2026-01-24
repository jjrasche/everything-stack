/// # Channel Integration Tests
///
/// Tests Channel against real echo server using factory pattern.
/// Uses minimal mocks ONLY for retry edge cases (can't control echo server to fail).
///
/// Run with:
///   flutter test integration_test/nerve/channel_integration_test.dart -d chrome
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
import 'package:everything_stack_template/nerve/protocol/protocol.dart';
import 'package:everything_stack_template/nerve/protocol/websocket_protocol.dart';
import 'package:everything_stack_template/nerve/channel/channel.dart';
import 'package:everything_stack_template/nerve/channel/retry_policy.dart';
import 'package:everything_stack_template/nerve/nerve_exception.dart';

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
      // Channel tests only run on web
    });
    return;
  }

  group('Channel Integration Tests - Real Echo Server', () {
    late Transport transport;
    late TransportFactory transportFactory;
    late WebSocketProtocol protocol;
    late Channel channel;
    late ChannelFactory channelFactory;

    setUp(() {
      transportFactory = createTransportFactory();
      transport = transportFactory.create(TransportConfig(
        host: echoServerHost,
        port: echoServerPort,
        useTls: echoServerTls,
        path: '/echo',
      ));
      protocol = WebSocketProtocol(transport: transport);
      final scheme = echoServerTls ? 'wss' : 'ws';
      channelFactory = createChannelFactory();
      channel = channelFactory.create(
        ChannelConfig(
          endpoint: '$scheme://$echoServerHost:$echoServerPort/echo',
          retryPolicy: RetryPolicy.none, // No retries for basic tests
        ),
        protocol,
      );
    });

    tearDown(() async {
      await channel.disconnect();
      channel.dispose();
      protocol.dispose();
      transport.dispose();
    });

    group('Connection', () {
      testWidgets('connects to echo server', (tester) async {
        final states = <ChannelState>[];
        channel.stateChanges.listen(states.add);

        expect(channel.state, ChannelState.disconnected);

        await channel.connect();
        await Future.delayed(Duration(milliseconds: 500));

        expect(channel.state, ChannelState.connected);
        expect(states, contains(ChannelState.connecting));
        expect(states, contains(ChannelState.connected));
      });

      testWidgets('connect is idempotent', (tester) async {
        await channel.connect();
        final stateAfter = channel.state;

        await channel.connect(); // Should not throw

        expect(channel.state, stateAfter);
      });
    });

    group('Send/Receive', () {
      testWidgets('sends and receives text message', (tester) async {
        await channel.connect();

        final messages = <Message>[];
        channel.messages.listen(messages.add);

        await channel.sendText('Hello from Channel!');

        // Wait for echo
        await Future.delayed(Duration(milliseconds: 500));

        expect(messages, isNotEmpty);
        expect((messages.first as TextMessage).text, 'Hello from Channel!');
      });

      testWidgets('sends and receives binary message', (tester) async {
        await channel.connect();

        final messages = <Message>[];
        channel.messages.listen(messages.add);

        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        await channel.sendBinary(data);

        // Wait for echo
        await Future.delayed(Duration(milliseconds: 500));

        expect(messages, isNotEmpty);
        // May come back as text (if valid UTF-8 attempted) or binary
      });

      testWidgets('sends multiple messages', (tester) async {
        await channel.connect();

        final messages = <Message>[];
        channel.messages.listen(messages.add);

        await channel.sendText('one');
        await channel.sendText('two');
        await channel.sendText('three');

        // Wait for echoes
        await Future.delayed(Duration(milliseconds: 1000));

        expect(messages.length, 3);
      });

      testWidgets('throws when sending without connection', (tester) async {
        expect(channel.state, ChannelState.disconnected);

        await expectLater(
          () => channel.sendText('test'),
          throwsA(isA<ConnectionLostException>()),
        );
      });
    });

    group('Disconnect', () {
      testWidgets('disconnects cleanly', (tester) async {
        await channel.connect();
        expect(channel.state, ChannelState.connected);

        final states = <ChannelState>[];
        channel.stateChanges.listen(states.add);

        await channel.disconnect();
        await Future.delayed(Duration(milliseconds: 100));

        expect(channel.state, ChannelState.disconnected);
        expect(states, contains(ChannelState.disconnecting));
        expect(states, contains(ChannelState.disconnected));
      });

      testWidgets('disconnect is idempotent', (tester) async {
        await channel.connect();
        await channel.disconnect();

        await channel.disconnect(); // Should not throw

        expect(channel.state, ChannelState.disconnected);
      });
    });

    group('Full-Duplex', () {
      testWidgets('can send and receive concurrently', (tester) async {
        await channel.connect();

        final messages = <Message>[];
        channel.messages.listen(messages.add);

        // Send multiple messages rapidly (simulating audio streaming)
        final futures = <Future>[];
        for (int i = 0; i < 5; i++) {
          futures.add(channel.sendText('Chunk $i'));
        }
        await Future.wait(futures);

        // Wait for all echoes
        await Future.delayed(Duration(milliseconds: 1000));

        expect(messages.length, 5);
      });
    });

    group('State Stream', () {
      testWidgets('emits full lifecycle states', (tester) async {
        final states = <ChannelState>[];
        channel.stateChanges.listen(states.add);

        await channel.connect();
        await Future.delayed(Duration(milliseconds: 100));
        await channel.disconnect();
        await Future.delayed(Duration(milliseconds: 100));

        expect(states, [
          ChannelState.connecting,
          ChannelState.connected,
          ChannelState.disconnecting,
          ChannelState.disconnected,
        ]);
      });
    });
  });

  // Retry tests use mocks because we can't control echo server to fail
  group('Channel Retry Tests - With Mocks', () {
    testWidgets('retries on failure then connects', (tester) async {
      // Mock transport that fails twice then succeeds
      final mockTransport = _RetryTestTransport(failCount: 2);
      final mockProtocol = _MockProtocolForRetry(transport: mockTransport);

      final channel = ChannelImpl(
        config: ChannelConfig(
          endpoint: 'wss://test.example.com',
          retryPolicy: RetryPolicy(
            maxAttempts: 3,
            initialDelay: Duration(milliseconds: 10),
            useJitter: false,
          ),
        ),
        protocol: mockProtocol,
      );

      final states = <ChannelState>[];
      channel.stateChanges.listen(states.add);

      await channel.connect();
      await Future.delayed(Duration(milliseconds: 100));

      expect(channel.state, ChannelState.connected);
      expect(mockTransport.connectAttempts, 3); // 2 fails + 1 success
      expect(states, contains(ChannelState.reconnecting));

      channel.dispose();
      mockProtocol.dispose();
      mockTransport.dispose();
    });

    testWidgets('fails after exhausting retries', (tester) async {
      // Mock transport that always fails
      final mockTransport = _AlwaysFailTransport();
      final mockProtocol = _MockProtocolForRetry(transport: mockTransport);

      final channel = ChannelImpl(
        config: ChannelConfig(
          endpoint: 'wss://test.example.com',
          retryPolicy: RetryPolicy(
            maxAttempts: 2,
            initialDelay: Duration(milliseconds: 10),
            useJitter: false,
          ),
        ),
        protocol: mockProtocol,
      );

      await expectLater(
        () => channel.connect(),
        throwsA(isA<ConnectionFailedException>()),
      );
      expect(channel.state, ChannelState.failed);

      channel.dispose();
      mockProtocol.dispose();
      mockTransport.dispose();
    });

    testWidgets('no retries with RetryPolicy.none', (tester) async {
      final mockTransport = _AlwaysFailTransport();
      final mockProtocol = _MockProtocolForRetry(transport: mockTransport);

      final channel = ChannelImpl(
        config: ChannelConfig(
          endpoint: 'wss://test.example.com',
          retryPolicy: RetryPolicy.none,
        ),
        protocol: mockProtocol,
      );

      await expectLater(
        () => channel.connect(),
        throwsA(isA<ConnectionFailedException>()),
      );
      expect(channel.state, ChannelState.failed);
      expect(mockTransport.connectAttempts, 1); // Only 1 attempt

      channel.dispose();
      mockProtocol.dispose();
      mockTransport.dispose();
    });
  });
}

// =============================================================================
// Minimal mocks for retry tests ONLY
// =============================================================================

/// Mock transport that fails N times then succeeds.
class _RetryTestTransport implements Transport {
  final int failCount;
  int connectAttempts = 0;

  TransportState _state = TransportState.disconnected;
  final _stateController = StreamController<TransportState>.broadcast();
  final _receivedController = StreamController<Uint8List>.broadcast();

  _RetryTestTransport({required this.failCount});

  @override
  String get id => 'retry-test-transport';

  @override
  TransportConfig get config => TransportConfig(host: 'test', port: 443);

  @override
  TransportState get state => _state;

  @override
  Stream<TransportState> get stateChanges => _stateController.stream;

  @override
  Stream<Uint8List> get received => _receivedController.stream;

  @override
  Future<void> connect() async {
    connectAttempts++;
    _state = TransportState.connecting;
    _stateController.add(_state);

    if (connectAttempts <= failCount) {
      _state = TransportState.disconnected;
      _stateController.add(_state);
      throw ConnectionFailedException('Attempt $connectAttempts failed');
    }

    _state = TransportState.connected;
    _stateController.add(_state);
  }

  @override
  Future<void> send(Uint8List data) async {}

  @override
  Future<void> close() async {
    _state = TransportState.disconnected;
    _stateController.add(_state);
  }

  void dispose() {
    _stateController.close();
    _receivedController.close();
  }
}

/// Mock transport that always fails.
class _AlwaysFailTransport implements Transport {
  int connectAttempts = 0;

  TransportState _state = TransportState.disconnected;
  final _stateController = StreamController<TransportState>.broadcast();
  final _receivedController = StreamController<Uint8List>.broadcast();

  @override
  String get id => 'always-fail-transport';

  @override
  TransportConfig get config => TransportConfig(host: 'test', port: 443);

  @override
  TransportState get state => _state;

  @override
  Stream<TransportState> get stateChanges => _stateController.stream;

  @override
  Stream<Uint8List> get received => _receivedController.stream;

  @override
  Future<void> connect() async {
    connectAttempts++;
    _state = TransportState.connecting;
    _stateController.add(_state);
    _state = TransportState.disconnected;
    _stateController.add(_state);
    throw ConnectionFailedException('Always fails');
  }

  @override
  Future<void> send(Uint8List data) async {}

  @override
  Future<void> close() async {
    _state = TransportState.disconnected;
    _stateController.add(_state);
  }

  void dispose() {
    _stateController.close();
    _receivedController.close();
  }
}

/// Minimal mock protocol for retry tests.
class _MockProtocolForRetry implements Protocol {
  @override
  final Transport transport;

  ProtocolState _state = ProtocolState.uninitialized;
  final _stateController = StreamController<ProtocolState>.broadcast();
  final _messageController = StreamController<Message>.broadcast();

  _MockProtocolForRetry({required this.transport});

  @override
  ProtocolState get state => _state;

  @override
  Stream<ProtocolState> get stateChanges => _stateController.stream;

  @override
  Stream<Message> get messages => _messageController.stream;

  @override
  Future<void> initialize() async {
    _state = ProtocolState.initializing;
    _stateController.add(_state);
    _state = ProtocolState.ready;
    _stateController.add(_state);
  }

  @override
  Future<void> sendText(String text) async {}

  @override
  Future<void> sendBinary(Uint8List data) async {}

  @override
  Future<void> close() async {
    _state = ProtocolState.closing;
    _stateController.add(_state);
    _state = ProtocolState.closed;
    _stateController.add(_state);
  }

  void dispose() {
    _stateController.close();
    _messageController.close();
  }
}
