/// # WebSocket Protocol
///
/// Protocol implementation for WebSocket text/binary framing.
///
/// ## How it Works
/// WebSocket already distinguishes text vs binary frames at the transport level.
/// This protocol layer:
/// - Converts Transport byte streams into typed [Message] objects
/// - Handles UTF-8 encoding/decoding for text messages
/// - Passes binary data through unchanged
///
/// ## No Handshake Required
/// Unlike some protocols (e.g., Phoenix Channels, Socket.IO), plain WebSocket
/// has no application-level handshake. The HTTP upgrade is handled by Transport.
/// [initialize] succeeds immediately if transport is connected.
///
/// ## Full-Duplex
/// Inherits full-duplex support from Transport. Send and receive operate
/// independently.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../nerve_exception.dart';
import '../transport/transport.dart';
import 'protocol.dart';

/// WebSocket protocol implementation.
///
/// Provides text/binary message framing over a connected [Transport].
class WebSocketProtocol implements Protocol {
  @override
  final Transport transport;

  ProtocolState _state = ProtocolState.uninitialized;
  final _stateController = StreamController<ProtocolState>.broadcast();
  final _messageController = StreamController<Message>.broadcast();

  StreamSubscription<Uint8List>? _transportSubscription;

  /// Message type prefix for text messages.
  /// WebSocket uses opcode 0x01 for text, but browser API converts to string.
  /// We use a prefix byte to distinguish in our Transport layer.
  static const int _textPrefix = 0x01;

  /// Message type prefix for binary messages.
  /// WebSocket uses opcode 0x02 for binary.
  static const int _binaryPrefix = 0x02;

  /// Whether to use prefix bytes for message type detection.
  ///
  /// If false, all messages are treated as binary by default.
  /// Set to true when working with mixed text/binary streams.
  final bool usePrefixFraming;

  /// If true, try to decode all messages as UTF-8 text first.
  /// Falls back to binary if decode fails.
  final bool preferTextMessages;

  WebSocketProtocol({
    required this.transport,
    this.usePrefixFraming = false,
    this.preferTextMessages = true,
  });

  @override
  ProtocolState get state => _state;

  @override
  Stream<ProtocolState> get stateChanges => _stateController.stream;

  @override
  Stream<Message> get messages => _messageController.stream;

  @override
  Future<void> initialize() async {
    if (_state == ProtocolState.ready) {
      return; // Already initialized
    }

    if (transport.state != TransportState.connected) {
      throw ProtocolException(
        'Transport must be connected before initializing protocol',
      );
    }

    _setState(ProtocolState.initializing);

    try {
      // No WebSocket-specific handshake needed.
      // HTTP upgrade already completed in Transport.connect().

      // Setup message forwarding from transport
      _setupMessageForwarding();

      _setState(ProtocolState.ready);
    } catch (e) {
      _setState(ProtocolState.uninitialized);
      if (e is NerveException) rethrow;
      throw ProtocolException('Protocol initialization failed: $e', e);
    }
  }

  void _setupMessageForwarding() {
    _transportSubscription?.cancel();
    _transportSubscription = transport.received.listen(
      (data) {
        _handleReceivedData(data);
      },
      onError: (error) {
        if (error is ConnectionLostException) {
          _messageController.addError(error);
        } else {
          _messageController.addError(
            ConnectionLostException('Transport error: $error', error),
          );
        }
      },
      onDone: () {
        // Transport closed unexpectedly
        if (_state == ProtocolState.ready) {
          _messageController.addError(
            ConnectionLostException('Transport stream closed'),
          );
        }
      },
    );
  }

  void _handleReceivedData(Uint8List data) {
    if (data.isEmpty) return;

    if (usePrefixFraming && data.length > 1) {
      // Use first byte as type indicator
      final prefix = data[0];
      final payload = Uint8List.sublistView(data, 1);

      if (prefix == _textPrefix) {
        try {
          final text = utf8.decode(payload);
          _messageController.add(TextMessage(text));
        } catch (e) {
          // Malformed UTF-8, treat as binary
          _messageController.add(BinaryMessage(payload));
        }
      } else {
        // Binary or unknown prefix - treat as binary
        _messageController.add(BinaryMessage(payload));
      }
    } else if (preferTextMessages) {
      // Try to decode as UTF-8 text
      try {
        final text = utf8.decode(data);
        _messageController.add(TextMessage(text));
      } catch (e) {
        // Not valid UTF-8, treat as binary
        _messageController.add(BinaryMessage(data));
      }
    } else {
      // Binary by default
      _messageController.add(BinaryMessage(data));
    }
  }

  @override
  Future<void> sendText(String text) async {
    _checkReady();

    try {
      final bytes = utf8.encode(text);

      if (usePrefixFraming) {
        // Prepend text prefix
        final prefixed = Uint8List(bytes.length + 1);
        prefixed[0] = _textPrefix;
        prefixed.setRange(1, prefixed.length, bytes);
        await transport.send(prefixed);
      } else {
        await transport.send(Uint8List.fromList(bytes));
      }
    } catch (e) {
      if (e is NerveException) rethrow;
      throw ConnectionLostException('Failed to send text: $e', e);
    }
  }

  @override
  Future<void> sendBinary(Uint8List data) async {
    _checkReady();

    try {
      if (usePrefixFraming) {
        // Prepend binary prefix
        final prefixed = Uint8List(data.length + 1);
        prefixed[0] = _binaryPrefix;
        prefixed.setRange(1, prefixed.length, data);
        await transport.send(prefixed);
      } else {
        await transport.send(data);
      }
    } catch (e) {
      if (e is NerveException) rethrow;
      throw ConnectionLostException('Failed to send binary: $e', e);
    }
  }

  @override
  Future<void> close() async {
    if (_state == ProtocolState.closed) {
      return;
    }

    _setState(ProtocolState.closing);

    await _transportSubscription?.cancel();

    _setState(ProtocolState.closed);
    _messageController.close();
  }

  void _checkReady() {
    if (_state != ProtocolState.ready) {
      throw ProtocolException('Protocol not ready: $_state');
    }
  }

  void _setState(ProtocolState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// Clean up resources.
  void dispose() {
    _transportSubscription?.cancel();
    _stateController.close();
    _messageController.close();
  }
}

/// Factory for creating [WebSocketProtocol] instances.
class WebSocketProtocolFactory implements ProtocolFactory {
  final bool usePrefixFraming;
  final bool preferTextMessages;

  const WebSocketProtocolFactory({
    this.usePrefixFraming = false,
    this.preferTextMessages = true,
  });

  @override
  Protocol create(Transport transport) => WebSocketProtocol(
        transport: transport,
        usePrefixFraming: usePrefixFraming,
        preferTextMessages: preferTextMessages,
      );
}
