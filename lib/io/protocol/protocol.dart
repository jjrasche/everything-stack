/// # Protocol Layer
///
/// The Protocol layer handles message-level communication on top of Transport.
/// It provides framing, serialization, and protocol-specific handshakes.
///
/// ## Responsibilities
/// - Message framing (text vs binary)
/// - Protocol-specific initialization (beyond transport connect)
/// - Unified message stream for higher layers
///
/// ## NOT Responsibilities (handled by Transport)
/// - Raw byte transmission
/// - Connection establishment
/// - TLS/SSL
///
/// ## NOT Responsibilities (handled by Channel)
/// - Retry logic
/// - Application-level keepalives
/// - State management across reconnects

import 'dart:async';
import 'dart:typed_data';

import '../io_exception.dart';
import '../transport/transport.dart';

/// A message that can be sent/received over a Protocol.
abstract class Message {
  /// Unique identifier for this message (for correlation/debugging).
  String get id;

  /// When this message was created.
  DateTime get timestamp;
}

/// A text message (e.g., JSON, plain text).
class TextMessage implements Message {
  @override
  final String id;

  @override
  final DateTime timestamp;

  /// The text content.
  final String text;

  TextMessage(
    this.text, {
    String? id,
    DateTime? timestamp,
  })  : id = id ?? _generateId(),
        timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'TextMessage($id, ${text.length} chars)';

  static int _counter = 0;
  static String _generateId() => 'msg-${++_counter}';
}

/// A binary message (e.g., audio data, images).
class BinaryMessage implements Message {
  @override
  final String id;

  @override
  final DateTime timestamp;

  /// The binary content.
  final Uint8List data;

  BinaryMessage(
    this.data, {
    String? id,
    DateTime? timestamp,
  })  : id = id ?? _generateId(),
        timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'BinaryMessage($id, ${data.length} bytes)';

  static int _counter = 0;
  static String _generateId() => 'msg-${++_counter}';
}

/// Protocol state.
enum ProtocolState {
  /// Not initialized.
  uninitialized,

  /// Initializing (handshake in progress).
  initializing,

  /// Ready for send/receive.
  ready,

  /// Closing.
  closing,

  /// Closed.
  closed,
}

/// Abstract interface for message-level protocol.
///
/// Implementations:
/// - [WebSocketProtocol] - WebSocket text/binary framing
abstract class Protocol {
  /// The underlying transport.
  Transport get transport;

  /// Current protocol state.
  ProtocolState get state;

  /// Stream of state changes.
  Stream<ProtocolState> get stateChanges;

  /// Initialize the protocol (perform any handshakes).
  ///
  /// Transport must be connected before calling this.
  ///
  /// Throws:
  /// - [ProtocolException] if handshake fails
  Future<void> initialize();

  /// Send a text message.
  ///
  /// Throws:
  /// - [ProtocolException] if not ready
  /// - [ConnectionLostException] if transport disconnects
  Future<void> sendText(String text);

  /// Send a binary message.
  ///
  /// Throws:
  /// - [ProtocolException] if not ready
  /// - [ConnectionLostException] if transport disconnects
  Future<void> sendBinary(Uint8List data);

  /// Stream of received messages (text or binary).
  ///
  /// This stream:
  /// - Emits [TextMessage] or [BinaryMessage] as they arrive
  /// - Emits errors on protocol errors
  /// - Closes when protocol is closed
  Stream<Message> get messages;

  /// Close the protocol gracefully.
  ///
  /// May send protocol-specific close frames.
  /// Idempotent - safe to call multiple times.
  Future<void> close();

  /// Dispose of resources (stream controllers, subscriptions).
  ///
  /// Should be called after [close()] when the protocol is no longer needed.
  /// Idempotent - safe to call multiple times.
  void dispose();
}

/// Factory for creating Protocol instances.
abstract class ProtocolFactory {
  /// Create a new Protocol for the given transport.
  Protocol create(Transport transport);
}
