/// # Rust WebSocket Transport
///
/// Transport implementation using Rust FFI (tungstenite).
/// Fixes Windows dart:io WebSocket bug (wss:// → https:// conversion).
///
/// ## Architecture
/// - Dart calls Rust FFI via flutter_rust_bridge
/// - Rust owns WebSocket connection (tungstenite + tokio)
/// - Dart gets handle (u64) to reference connection
/// - Receive stream via StreamController (polling for now)
///
/// ## Platforms
/// - Works on ALL native platforms: Windows, macOS, Linux, iOS, Android
/// - Web uses BrowserWebSocketTransport instead

import 'dart:async';
import 'dart:typed_data';

import '../nerve_exception.dart';
import 'transport.dart';
import '../../bridge/native.dart/api.dart' as rust;
import '../../bridge/native.dart/frb_generated.dart';

/// Rust-based WebSocket transport using tungstenite.
///
/// Fixes Windows dart:io bug where wss:// URLs are converted to https://.
class RustWebSocketTransport implements Transport {
  static int _idCounter = 0;
  static Completer<void>? _initCompleter;

  @override
  final String id;

  @override
  final TransportConfig config;

  BigInt? _handle;
  TransportState _state = TransportState.disconnected;

  final _stateController = StreamController<TransportState>.broadcast();
  final _receivedController = StreamController<Uint8List>.broadcast();

  Timer? _receivePoller;

  RustWebSocketTransport({required this.config, String? id})
      : id = id ?? 'rust-transport-${++_idCounter}';

  @override
  TransportState get state => _state;

  @override
  Stream<TransportState> get stateChanges => _stateController.stream;

  @override
  Stream<Uint8List> get received => _receivedController.stream;

  /// Ensure RustLib is initialized exactly once per process.
  ///
  /// Uses Completer pattern to handle concurrent initialization attempts.
  static Future<void> _ensureRustInitialized() async {
    if (_initCompleter == null) {
      _initCompleter = Completer<void>();
      try {
        await RustLib.init();
        _initCompleter!.complete();
      } catch (e) {
        _initCompleter = null; // Allow retry on failure
        rethrow;
      }
    }
    return _initCompleter!.future;
  }

  @override
  Future<void> connect() async {
    if (_state == TransportState.connected) {
      return; // Already connected
    }

    _setState(TransportState.connecting);

    try {
      // Ensure Rust FFI bridge is initialized (once per process)
      await _ensureRustInitialized();

      final url = config.url;
      final headers = config.headers?.entries.map((e) => (e.key, e.value)).toList() ?? [];

      print('🦀 [RustWebSocketTransport] Connecting to: $url');

      // Call Rust FFI to connect
      _handle = await rust.websocketConnect(url: url, headers: headers);

      // TODO: Setup receive stream (need to implement polling or callback)
      // For now, just mark as connected

      _setState(TransportState.connected);
      print('✅ [RustWebSocketTransport] Connected (handle: $_handle)');
    } catch (e) {
      _setState(TransportState.disconnected);
      throw ConnectionFailedException('Failed to connect: $e', e);
    }
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_state != TransportState.connected || _handle == null) {
      throw ConnectionLostException('Not connected: $_state');
    }

    try {
      await rust.websocketSend(handle: _handle!, data: data);
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

    if (_handle != null) {
      try {
        await rust.websocketClose(handle: _handle!);
      } catch (e) {
        print('⚠️ [RustWebSocketTransport] Close error: $e');
      }
    }

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
    _receivePoller?.cancel();
    if (_handle != null) {
      rust.websocketDispose(handle: _handle!);
    }
    _stateController.close();
    _receivedController.close();
  }
}

/// Factory for creating [RustWebSocketTransport] instances.
class RustWebSocketTransportFactory implements TransportFactory {
  @override
  Transport create(TransportConfig config) =>
      RustWebSocketTransport(config: config);
}

/// Create platform-specific transport factory (Rust implementation).
TransportFactory createPlatformTransportFactory() =>
    RustWebSocketTransportFactory();
