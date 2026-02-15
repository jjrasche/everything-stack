/// ## Why Rust FFI instead of dart:io
/// dart:io WebSocket on Windows converts wss:// to https:// during HTTP upgrade,
/// breaking TLS. Rust tungstenite handles this correctly on all native platforms.

import 'dart:async';
import 'dart:typed_data';

import '../io_exception.dart';
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
  /// Handles double-initialization gracefully (multiple test groups in single process).
  static Future<void> _ensureRustInitialized() async {
    if (_initCompleter == null) {
      _initCompleter = Completer<void>();
      try {
        await RustLib.init();
        _initCompleter!.complete();
      } catch (e) {
        // If already initialized, treat as success (consolidated test runner)
        if (e.toString().contains('Should not initialize flutter_rust_bridge twice') ||
            e is StateError && e.message.contains('initialize')) {
          print('ℹ️ [RustWebSocketTransport] Rust bridge already initialized, continuing');
          _initCompleter!.complete();
        } else {
          _initCompleter = null; // Allow retry on other failures
          rethrow;
        }
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
      final headers =
          config.headers?.entries.map((e) => (e.key, e.value)).toList() ?? [];
      final subprotocols = config.subprotocols ?? [];

      print('🦀 [RustWebSocketTransport] Connecting to: $url');
      if (subprotocols.isNotEmpty) {
        print(
            '🦀 [RustWebSocketTransport] Subprotocols: ${subprotocols.join(", ")}');
      }

      _handle = await rust.websocketConnect(
          url: url, headers: headers, subprotocols: subprotocols);

      try {
        await rust.websocketStartReceive(handle: _handle!);
        print('🦀 [RustWebSocketTransport] Receive stream started');

        _startReceivePolling();
      } catch (e) {
        print('⚠️ [RustWebSocketTransport] Could not start receive: $e');
        // Continue anyway - send will still work
      }

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

    _receivePoller?.cancel();

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

  /// Start polling for received messages from Rust queue.
  ///
  /// Polls every 50ms for new messages and pushes them to the received stream.
  /// Detects connection closure via poll errors and transitions to disconnected.
  void _startReceivePolling() {
    _receivePoller?.cancel();
    _receivePoller =
        Timer.periodic(const Duration(milliseconds: 50), (_) async {
      if (_state != TransportState.connected || _handle == null) {
        _receivePoller?.cancel();
        return;
      }

      try {
        final messages = await rust.websocketPollReceive(handle: _handle!);
        for (final msg in messages) {
          _receivedController.add(msg);
        }
      } catch (e) {
        // Poll error indicates connection closed (server-initiated or network failure)
        print('🦀 [RustWebSocketTransport] Poll error: $e');

        // Detect "connection not found" or similar errors indicating closed connection
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('not found') ||
            errorStr.contains('closed') ||
            errorStr.contains('eof') ||
            errorStr.contains('connection')) {
          _receivePoller?.cancel();
          _setState(TransportState.disconnected);
          _receivedController.addError(ConnectionLostException(
            'Connection closed by server',
            e,
          ));
        }
      }
    });
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
