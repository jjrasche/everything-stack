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

// Communication patterns
export 'channel/channel.dart';
export 'channel/retry_policy.dart';
export 'patterns/subscription.dart';
export 'patterns/request_response.dart';
export 'request_response/http_request_response.dart';
