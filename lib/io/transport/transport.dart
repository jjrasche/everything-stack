/// # Transport Layer
///
/// The Transport layer handles raw byte-level communication over network connections.
/// It provides a platform-agnostic interface that can be implemented using:
/// - Browser WebSocket API (web)
/// - Rust FFI with tungstenite (native platforms)
///
/// ## Responsibilities
/// - Establish and maintain connections
/// - Send/receive raw bytes (full-duplex)
/// - Report connection state changes
/// - Handle graceful and abrupt disconnection
///
/// ## NOT Responsibilities (handled by Protocol layer)
/// - Message framing
/// - Text vs binary distinction
/// - Protocol-specific handshakes
///
/// ## Full-Duplex Requirement
/// Transport MUST support simultaneous send and receive. The [received] stream
/// operates independently of [send] calls. This is critical for protocols like
/// WebSocket where audio can be sent while transcripts are received.

import 'dart:async';
import 'dart:typed_data';

import '../io_exception.dart';

/// Connection state for a Transport.
enum TransportState {
  /// Not connected, ready to connect.
  disconnected,

  /// Connection attempt in progress.
  connecting,

  /// Connected and ready for send/receive.
  connected,

  /// Disconnection in progress.
  disconnecting,
}

/// Configuration for establishing a Transport connection.
class TransportConfig {
  /// Target hostname (e.g., 'api.deepgram.com').
  final String host;

  /// Target port (e.g., 443 for WSS).
  final int port;

  /// Whether to use TLS/SSL.
  final bool useTls;

  /// Maximum time to wait for connection.
  final Duration connectTimeout;

  /// Optional HTTP headers for upgrade request (WebSocket).
  final Map<String, String>? headers;

  /// Optional URL path (e.g., '/v2/listen').
  final String? path;

  /// Optional query parameters.
  final Map<String, String>? queryParams;

  /// Optional WebSocket subprotocols (for Sec-WebSocket-Protocol header).
  /// Example: ['token', 'api_key'] for Deepgram authentication.
  final List<String>? subprotocols;

  const TransportConfig({
    required this.host,
    required this.port,
    this.useTls = true,
    this.connectTimeout = const Duration(seconds: 30),
    this.headers,
    this.path,
    this.queryParams,
    this.subprotocols,
  });

  /// Construct full URL for this config.
  String get url {
    final scheme = useTls ? 'wss' : 'ws';
    final defaultPort = useTls ? 443 : 80;
    // Only include port if non-default (Deepgram rejects wss://host:443/path format)
    final portPart = (port == defaultPort) ? '' : ':$port';
    final pathPart = path ?? '';
    final queryPart = queryParams?.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&') ??
        '';
    final queryString = queryPart.isNotEmpty ? '?$queryPart' : '';
    return '$scheme://$host$portPart$pathPart$queryString';
  }

  @override
  String toString() => 'TransportConfig($url)';
}

/// Abstract interface for byte-level transport.
///
/// Implementations:
/// - [WebTransport] - Browser WebSocket API
/// - [NativeTransport] - Rust FFI (Phase 2)
abstract class Transport {
  /// Unique identifier for this transport instance.
  String get id;

  /// Current connection state.
  TransportState get state;

  /// Stream of state changes (for monitoring/logging).
  Stream<TransportState> get stateChanges;

  /// Configuration used for this transport.
  TransportConfig get config;

  /// Establish connection to the configured endpoint.
  ///
  /// Throws:
  /// - [ConnectionFailedException] if connection cannot be established
  /// - [TimeoutException] if connection exceeds [TransportConfig.connectTimeout]
  Future<void> connect();

  /// Send raw bytes over the connection.
  ///
  /// Throws:
  /// - [ConnectionLostException] if not connected
  Future<void> send(Uint8List data);

  /// Stream of received bytes (full-duplex, independent of send).
  ///
  /// This stream:
  /// - Emits data as it arrives
  /// - Emits error on connection loss ([ConnectionLostException])
  /// - Closes when transport is closed
  Stream<Uint8List> get received;

  /// Close the connection gracefully.
  ///
  /// Idempotent - safe to call multiple times.
  Future<void> close();

  /// Dispose of resources (stream controllers, subscriptions).
  ///
  /// Should be called after [close()] when the transport is no longer needed.
  /// Idempotent - safe to call multiple times.
  void dispose();
}

/// Factory for creating Transport instances.
abstract class TransportFactory {
  /// Create a new Transport for the given configuration.
  Transport create(TransportConfig config);
}
