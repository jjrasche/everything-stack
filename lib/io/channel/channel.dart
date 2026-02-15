
import 'dart:async';
import 'dart:typed_data';

import '../io_exception.dart';
import '../protocol/protocol.dart';
import 'retry_policy.dart';

/// Channel state.
enum ChannelState {
  /// Not connected.
  disconnected,

  /// Connection in progress.
  connecting,

  /// Connected and ready.
  connected,

  /// Reconnecting after connection loss.
  reconnecting,

  /// Failed after exhausting retries.
  failed,

  /// Disconnecting.
  disconnecting,
}

/// Configuration for a Channel.
class ChannelConfig {
  /// The endpoint URL (e.g., 'wss://api.deepgram.com:443/v2/listen').
  final String endpoint;

  /// Retry policy for reconnection.
  final RetryPolicy retryPolicy;

  /// Connection timeout.
  final Duration connectTimeout;

  /// Whether to auto-reconnect on connection loss.
  final bool autoReconnect;

  const ChannelConfig({
    required this.endpoint,
    this.retryPolicy = const RetryPolicy(),
    this.connectTimeout = const Duration(seconds: 30),
    this.autoReconnect = true,
  });

  @override
  String toString() => 'ChannelConfig($endpoint)';
}

/// Abstract interface for application-level channel.
abstract class Channel {
  /// Unique identifier for this channel.
  String get id;

  /// Configuration for this channel.
  ChannelConfig get config;

  /// Current connection state.
  ChannelState get state;

  /// Stream of state changes.
  Stream<ChannelState> get stateChanges;

  /// The underlying protocol (for direct access if needed).
  Protocol get protocol;

  /// Establish connection with retry logic.
  ///
  /// Throws:
  /// - [ConnectionFailedException] if all retries exhausted
  Future<void> connect();

  /// Send a text message.
  ///
  /// Throws:
  /// - [ConnectionLostException] if not connected
  Future<void> sendText(String text);

  /// Send a binary message.
  ///
  /// Throws:
  /// - [ConnectionLostException] if not connected
  Future<void> sendBinary(Uint8List data);

  /// Stream of received messages.
  Stream<Message> get messages;

  /// Disconnect cleanly (no auto-reconnect).
  Future<void> disconnect();

  /// Dispose of resources (stream controllers, subscriptions).
  ///
  /// Should be called after [disconnect()] when the channel is no longer needed.
  /// Idempotent - safe to call multiple times.
  void dispose();
}

/// Standard implementation of [Channel].
class ChannelImpl implements Channel {
  static int _idCounter = 0;

  @override
  final String id;

  @override
  final ChannelConfig config;

  @override
  final Protocol protocol;

  ChannelState _state = ChannelState.disconnected;
  final _stateController = StreamController<ChannelState>.broadcast();

  int _reconnectAttempt = 0;
  bool _intentionalDisconnect = false;
  StreamSubscription<Message>? _protocolSubscription;

  final _messageController = StreamController<Message>.broadcast();

  ChannelImpl({
    required this.config,
    required this.protocol,
    String? id,
  }) : id = id ?? 'channel-${++_idCounter}';

  @override
  ChannelState get state => _state;

  @override
  Stream<ChannelState> get stateChanges => _stateController.stream;

  @override
  Stream<Message> get messages => _messageController.stream;

  @override
  Future<void> connect() async {
    if (_state == ChannelState.connected) {
      return; // Already connected
    }

    _intentionalDisconnect = false;
    _reconnectAttempt = 0;

    await _attemptConnect();
  }

  Future<void> _attemptConnect() async {
    _setState(ChannelState.connecting);

    try {
      // Connect transport first
      await protocol.transport.connect();

      // Initialize protocol
      await protocol.initialize();

      // Setup message forwarding
      _setupMessageForwarding();

      _setState(ChannelState.connected);
      _reconnectAttempt = 0;
    } catch (e) {
      if (!config.retryPolicy.shouldRetry(_reconnectAttempt)) {
        _setState(ChannelState.failed);
        if (e is NerveException) rethrow;
        throw ConnectionFailedException(
            'Connection failed after ${_reconnectAttempt + 1} attempts', e);
      }

      // Schedule retry
      final delay = config.retryPolicy.delayForAttempt(_reconnectAttempt);
      _reconnectAttempt++;
      _setState(ChannelState.reconnecting);

      await Future.delayed(delay);

      if (!_intentionalDisconnect) {
        await _attemptConnect();
      }
    }
  }

  void _setupMessageForwarding() {
    _protocolSubscription?.cancel();
    _protocolSubscription = protocol.messages.listen(
      (message) {
        _messageController.add(message);
      },
      onError: (error) {
        if (error is ConnectionLostException) {
          _handleConnectionLost(error);
        } else {
          _messageController.addError(error);
        }
      },
      onDone: () {
        if (!_intentionalDisconnect && config.autoReconnect) {
          _handleConnectionLost(
              ConnectionLostException('Protocol stream closed'));
        }
      },
    );
  }

  void _handleConnectionLost(ConnectionLostException error) {
    if (_intentionalDisconnect) return;
    if (_state == ChannelState.failed) return;

    if (config.autoReconnect &&
        config.retryPolicy.shouldRetry(_reconnectAttempt)) {
      _attemptReconnect();
    } else {
      _setState(ChannelState.failed);
      _messageController.addError(error);
    }
  }

  Future<void> _attemptReconnect() async {
    final delay = config.retryPolicy.delayForAttempt(_reconnectAttempt);
    _reconnectAttempt++;
    _setState(ChannelState.reconnecting);

    await Future.delayed(delay);

    if (!_intentionalDisconnect) {
      await _attemptConnect();
    }
  }

  @override
  Future<void> sendText(String text) async {
    _checkConnected();
    await protocol.sendText(text);
  }

  @override
  Future<void> sendBinary(Uint8List data) async {
    _checkConnected();
    await protocol.sendBinary(data);
  }

  @override
  Future<void> disconnect() async {
    if (_state == ChannelState.disconnected) {
      return;
    }

    _intentionalDisconnect = true;
    _setState(ChannelState.disconnecting);

    await _protocolSubscription?.cancel();
    await protocol.close();
    await protocol.transport.close();

    _setState(ChannelState.disconnected);
  }

  void _checkConnected() {
    if (_state != ChannelState.connected) {
      throw ConnectionLostException('Channel not connected: $_state');
    }
  }

  void _setState(ChannelState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// Clean up resources.
  void dispose() {
    _intentionalDisconnect = true;
    _protocolSubscription?.cancel();
    _stateController.close();
    _messageController.close();
  }
}

/// Factory for creating Channel instances.
abstract class ChannelFactory {
  /// Create a new Channel for the given configuration and protocol.
  Channel create(ChannelConfig config, Protocol protocol);
}

/// Concrete factory for creating [ChannelImpl] instances.
class ChannelImplFactory implements ChannelFactory {
  @override
  Channel create(ChannelConfig config, Protocol protocol) {
    return ChannelImpl(config: config, protocol: protocol);
  }
}

/// Create a platform-appropriate [ChannelFactory].
///
/// Currently returns [ChannelImplFactory] for all platforms.
/// Future: May return different implementations for specialized retry strategies.
ChannelFactory createChannelFactory() {
  return ChannelImplFactory();
}
