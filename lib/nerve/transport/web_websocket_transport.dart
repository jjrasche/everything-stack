/// # Browser WebSocket Transport
///
/// Browser WebSocket implementation of [Transport].
/// Uses dart:html WebSocket API directly for full-duplex communication.
///
/// ## Why Not dart:io WebSocket?
/// dart:io WebSocket has a bug on Windows where it converts wss:// to https://
/// during HTTP upgrade handshake, breaking TLS WebSocket connections.
/// Browser WebSocket API works correctly on all platforms.
///
/// ## Full-Duplex Support
/// Browser WebSocket is inherently full-duplex. The [received] stream
/// operates independently of [send] calls via WebSocket.onMessage events.

import 'dart:async';
import 'dart:typed_data';
import 'dart:html' as html;

import '../nerve_exception.dart';
import 'transport.dart';

/// Browser WebSocket implementation of [Transport].
class BrowserWebSocketTransport implements Transport {
  static int _idCounter = 0;

  @override
  final String id;

  @override
  final TransportConfig config;

  html.WebSocket? _socket;
  TransportState _state = TransportState.disconnected;

  final _stateController = StreamController<TransportState>.broadcast();
  final _receivedController = StreamController<Uint8List>.broadcast();

  StreamSubscription? _messageSubscription;
  StreamSubscription? _closeSubscription;
  StreamSubscription? _errorSubscription;

  BrowserWebSocketTransport({required this.config, String? id})
      : id = id ?? 'browser-websocket-${++_idCounter}';

  @override
  TransportState get state => _state;

  @override
  Stream<TransportState> get stateChanges => _stateController.stream;

  @override
  Stream<Uint8List> get received => _receivedController.stream;

  @override
  Future<void> connect() async {
    if (_state == TransportState.connected) {
      return; // Already connected
    }

    _setState(TransportState.connecting);

    try {
      final completer = Completer<void>();

      // Build URL from config
      final url = config.url;

      // Browser WebSocket doesn't support custom headers directly.
      // Headers like Authorization must be passed via query params or protocols.
      // For Deepgram, the API key goes in query params (handled by TransportConfig).
      _socket = html.WebSocket(url);
      _socket!.binaryType = 'arraybuffer';

      // Setup event handlers
      _socket!.onOpen.first.then((_) {
        if (!completer.isCompleted) {
          _setState(TransportState.connected);
          _setupListeners();
          completer.complete();
        }
      });

      _socket!.onError.first.then((event) {
        if (!completer.isCompleted) {
          _setState(TransportState.disconnected);
          completer.completeError(
            ConnectionFailedException('WebSocket connection failed'),
          );
        }
      });

      _socket!.onClose.first.then((event) {
        if (!completer.isCompleted) {
          _setState(TransportState.disconnected);
          completer.completeError(
            ConnectionFailedException(
              'WebSocket closed during connect: ${event.code} ${event.reason}',
            ),
          );
        }
      });

      // Wait for connection with timeout
      await completer.future.timeout(
        config.connectTimeout,
        onTimeout: () {
          _socket?.close();
          _socket = null;
          _setState(TransportState.disconnected);
          throw TimeoutException(
            'Connection timeout after ${config.connectTimeout.inSeconds}s',
          );
        },
      );
    } catch (e) {
      _setState(TransportState.disconnected);
      if (e is NerveException) rethrow;
      throw ConnectionFailedException('Failed to connect: $e', e);
    }
  }

  void _setupListeners() {
    // Message handler - convert to Uint8List
    _messageSubscription = _socket!.onMessage.listen((event) {
      final data = event.data;
      if (data is html.Blob) {
        // Convert Blob to Uint8List
        final reader = html.FileReader();
        reader.readAsArrayBuffer(data);
        reader.onLoadEnd.first.then((_) {
          final result = reader.result as ByteBuffer;
          _receivedController.add(Uint8List.view(result));
        });
      } else if (data is ByteBuffer) {
        _receivedController.add(Uint8List.view(data));
      } else if (data is String) {
        // Convert string to bytes (UTF-8)
        _receivedController.add(Uint8List.fromList(data.codeUnits));
      }
    });

    // Close handler
    _closeSubscription = _socket!.onClose.listen((event) {
      _handleDisconnect('Connection closed: ${event.code} ${event.reason}');
    });

    // Error handler
    _errorSubscription = _socket!.onError.listen((event) {
      _handleDisconnect('Connection error');
    });
  }

  void _handleDisconnect(String reason) {
    if (_state == TransportState.disconnected ||
        _state == TransportState.disconnecting) {
      return;
    }

    _setState(TransportState.disconnected);
    _receivedController.addError(ConnectionLostException(reason));
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_state != TransportState.connected || _socket == null) {
      throw ConnectionLostException('Not connected: $_state');
    }

    try {
      // Send as binary (ArrayBuffer)
      _socket!.sendByteBuffer(data.buffer);
    } catch (e) {
      throw ConnectionLostException('Send failed: $e', e);
    }
  }

  @override
  Future<void> close() async {
    if (_state == TransportState.disconnected) {
      return;
    }

    _setState(TransportState.disconnecting);

    await _messageSubscription?.cancel();
    await _closeSubscription?.cancel();
    await _errorSubscription?.cancel();

    _socket?.close();
    _socket = null;

    _setState(TransportState.disconnected);
  }

  void _setState(TransportState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// Clean up resources.
  void dispose() {
    _messageSubscription?.cancel();
    _closeSubscription?.cancel();
    _errorSubscription?.cancel();
    _socket?.close();
    _stateController.close();
    _receivedController.close();
  }
}

/// Factory for creating [BrowserWebSocketTransport] instances.
class BrowserWebSocketTransportFactory implements TransportFactory {
  @override
  Transport create(TransportConfig config) =>
      BrowserWebSocketTransport(config: config);
}

/// Create platform-specific transport factory (web implementation).
TransportFactory createPlatformTransportFactory() =>
    BrowserWebSocketTransportFactory();
