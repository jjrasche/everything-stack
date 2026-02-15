/// ## Why not used on Windows
/// dart:io WebSocket on Windows converts wss:// to https:// during
/// HTTP upgrade handshake, causing TLS failures (Dart SDK bug).
/// Windows uses RustWebSocketTransport instead.

import 'dart:async';
import 'dart:io' show WebSocket, Platform;
import 'dart:typed_data';

import '../io_exception.dart';
import 'transport.dart';

/// Native WebSocket transport using dart:io.
///
/// Works on macOS, iOS, Android, Linux. BROKEN ON WINDOWS.
class NativeWebSocketTransport implements Transport {
  static int _idCounter = 0;

  @override
  final String id;

  @override
  final TransportConfig config;

  WebSocket? _socket;
  TransportState _state = TransportState.disconnected;

  final _stateController = StreamController<TransportState>.broadcast();
  final _receivedController = StreamController<Uint8List>.broadcast();

  StreamSubscription? _socketSubscription;

  NativeWebSocketTransport({required this.config, String? id})
      : id = id ?? 'native-transport-${++_idCounter}';

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

    // Warn on Windows
    if (Platform.isWindows) {
      print(
          '⚠️ [NativeWebSocketTransport] WARNING: dart:io WebSocket is BROKEN on Windows!');
      print(
          '   WSS connections will fail due to Dart SDK bug (wss:// → https:// conversion).');
      print('   Use web platform or wait for Rust FFI (Phase 2).');
    }

    _setState(TransportState.connecting);

    try {
      final url = config.url;
      print('🔗 [NativeWebSocketTransport] Connecting to: $url');

      // Connect with optional headers
      _socket = await WebSocket.connect(
        url,
        headers: config.headers,
      ).timeout(
        config.connectTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Connection timeout after ${config.connectTimeout.inSeconds}s',
          );
        },
      );

      _setupListeners();
      _setState(TransportState.connected);
      print('✅ [NativeWebSocketTransport] Connected');
    } catch (e) {
      _setState(TransportState.disconnected);
      if (e is NerveException) rethrow;
      throw ConnectionFailedException('Failed to connect: $e', e);
    }
  }

  void _setupListeners() {
    _socketSubscription = _socket!.listen(
      (data) {
        if (data is List<int>) {
          _receivedController.add(Uint8List.fromList(data));
        } else if (data is String) {
          // Convert string to bytes
          _receivedController.add(Uint8List.fromList(data.codeUnits));
        }
      },
      onError: (error) {
        _handleDisconnect('Connection error: $error');
      },
      onDone: () {
        _handleDisconnect('Connection closed');
      },
    );
  }

  void _handleDisconnect(String reason) {
    if (_state == TransportState.disconnected ||
        _state == TransportState.disconnecting) {
      return;
    }

    print('🔌 [NativeWebSocketTransport] Disconnected: $reason');
    _setState(TransportState.disconnected);
    _receivedController.addError(ConnectionLostException(reason));
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_state != TransportState.connected || _socket == null) {
      throw ConnectionLostException('Not connected: $_state');
    }

    try {
      _socket!.add(data);
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

    await _socketSubscription?.cancel();
    await _socket?.close();
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
    _socketSubscription?.cancel();
    _socket?.close();
    _stateController.close();
    _receivedController.close();
  }
}

/// Factory for creating [NativeWebSocketTransport] instances.
class NativeWebSocketTransportFactory implements TransportFactory {
  @override
  Transport create(TransportConfig config) =>
      NativeWebSocketTransport(config: config);
}

/// Create platform-specific transport factory (native implementation).
TransportFactory createPlatformTransportFactory() =>
    NativeWebSocketTransportFactory();
