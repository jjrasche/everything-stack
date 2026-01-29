/// # IO System
///
/// Cross-platform communication layer for ALL digital communication.
/// Currently implements WebSocket with a three-layer architecture:
///
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │  CHANNEL - Retry logic, state management, connection events    │
/// ├─────────────────────────────────────────────────────────────────┤
/// │  PROTOCOL - Message framing (text vs binary), handshakes       │
/// ├─────────────────────────────────────────────────────────────────┤
/// │  TRANSPORT - Raw bytes over network (WebSocket, FFI)           │
/// └─────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Usage
///
/// ```dart
/// import 'package:everything_stack_template/io/io.dart';
///
/// // Create transport using factory
/// final transportFactory = createTransportFactory();
/// final transport = transportFactory.create(TransportConfig(
///   host: 'api.deepgram.com',
///   port: 443,
///   useTls: true,
///   path: '/v2/listen',
///   queryParams: {'model': 'nova-3', 'encoding': 'linear16'},
/// ));
///
/// // Create protocol
/// final protocol = WebSocketProtocol(transport: transport);
///
/// // Create channel using factory
/// final channelFactory = createChannelFactory();
/// final channel = channelFactory.create(
///   ChannelConfig(
///     endpoint: 'wss://api.deepgram.com:443/v2/listen',
///     retryPolicy: RetryPolicy.defaultPolicy,
///   ),
///   protocol,
/// );
///
/// // Connect and use
/// await channel.connect();
/// channel.messages.listen((message) {
///   if (message is TextMessage) {
///     print('Received: ${message.text}');
///   }
/// });
/// await channel.sendBinary(audioBytes);
/// ```
///
/// ## Platform Support
/// - Web: Browser WebSocket API (dart:html)
/// - Native: Rust FFI (Phase 2, not yet implemented)
library io;

// Exceptions
export 'io_exception.dart';

// Transport layer
export 'transport/transport.dart';
export 'transport/transport_factory.dart';
// Platform-specific transports are conditionally imported via transport_factory.dart:
// - Web: BrowserWebSocketTransport (browser WebSocket API)
// - Native: NativeWebSocketTransport (dart:io WebSocket - broken on Windows)

// Protocol layer
export 'protocol/protocol.dart';
export 'protocol/websocket_protocol.dart';

// Channel layer
export 'channel/channel.dart';
export 'channel/retry_policy.dart';
