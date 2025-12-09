/// # ConnectivityService
///
/// ## What it does
/// Platform wrapper for network connectivity state detection.
/// Detects offline/cellular/wifi/ethernet and streams changes.
///
/// ## What it enables
/// - SyncService: sync when online, blob sync only on WiFi
/// - UI: show offline indicator
/// - Adaptive behavior based on connection type
///
/// ## Implementations
/// - MockConnectivityService: Default for testing, manual state control
/// - ConnectivityPlusService: Production, uses connectivity_plus plugin
///
/// ## Usage
/// ```dart
/// // Use mock in tests
/// ConnectivityService.instance = MockConnectivityService();
/// (ConnectivityService.instance as MockConnectivityService).simulate(ConnectivityState.wifi);
///
/// // Use real in production
/// ConnectivityService.instance = ConnectivityPlusService();
/// await ConnectivityService.instance.initialize();
///
/// // Check state
/// if (ConnectivityService.instance.isOnline) { ... }
/// if (ConnectivityService.instance.isWifi) { syncBlobs(); }
///
/// // Listen to changes
/// ConnectivityService.instance.onConnectivityChanged.listen((state) {
///   print('Connection changed to $state');
/// });
/// ```
///
/// ## Testing approach
/// Test interface contracts and mock implementation.
/// Real implementation tested manually on actual platforms.

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

// ============ Enum and Exception ============

/// Network connectivity state
enum ConnectivityState {
  offline, // No network connection
  cellular, // Mobile data connection
  wifi, // WiFi connection
  ethernet, // Wired connection
}

/// Connectivity service error
class ConnectivityServiceException implements Exception {
  final String message;
  final Object? cause;

  ConnectivityServiceException(this.message, [this.cause]);

  @override
  String toString() {
    return 'ConnectivityServiceException: $message${cause != null ? '\nCaused by: $cause' : ''}';
  }
}

// ============ Abstract Interface ============

/// Platform-agnostic connectivity detection service.
abstract class ConnectivityService {
  /// Global singleton instance (defaults to mock for safe testing)
  static ConnectivityService instance = MockConnectivityService();

  /// Current online state (true if connected to any network)
  bool get isOnline;

  /// True if connected via WiFi or Ethernet (suitable for blob sync)
  /// False if cellular, offline, or unknown
  bool get isWifi;

  /// Current connectivity state (offline, cellular, wifi, ethernet)
  ConnectivityState get state;

  /// Stream of connectivity state changes
  Stream<ConnectivityState> get onConnectivityChanged;

  /// Initialize service and check current connectivity
  /// Must be called before using the service in production
  Future<void> initialize();

  /// Dispose resources and close streams
  void dispose();
}

// ============ Mock Implementation ============

/// Mock connectivity service for testing.
/// Provides deterministic, controllable connectivity state without platform dependencies.
class MockConnectivityService extends ConnectivityService {
  ConnectivityState _state = ConnectivityState.wifi;
  late final StreamController<ConnectivityState> _stateController;

  MockConnectivityService() {
    _stateController = StreamController<ConnectivityState>.broadcast();
  }

  /// Simulate a connectivity state change
  void simulate(ConnectivityState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  @override
  bool get isOnline => _state != ConnectivityState.offline;

  @override
  bool get isWifi =>
      _state == ConnectivityState.wifi || _state == ConnectivityState.ethernet;

  @override
  ConnectivityState get state => _state;

  @override
  Stream<ConnectivityState> get onConnectivityChanged =>
      _stateController.stream;

  @override
  Future<void> initialize() async {
    // No-op for mock: already initialized with default state
  }

  @override
  void dispose() {
    _stateController.close();
  }
}

// ============ Production Implementation ============

/// Real connectivity service using connectivity_plus plugin.
/// Detects actual network type and monitors for changes.
class ConnectivityPlusService extends ConnectivityService {
  final Connectivity _connectivity;
  late final StreamController<ConnectivityState> _stateController;
  late ConnectivityState _currentState;
  late StreamSubscription<ConnectivityResult> _subscription;

  ConnectivityPlusService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  /// Map connectivity_plus result to ConnectivityState
  static ConnectivityState _mapResult(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.none:
        return ConnectivityState.offline;
      case ConnectivityResult.mobile:
        return ConnectivityState.cellular;
      case ConnectivityResult.wifi:
        return ConnectivityState.wifi;
      case ConnectivityResult.ethernet:
        return ConnectivityState.ethernet;
      case ConnectivityResult.bluetooth:
      case ConnectivityResult.vpn:
      case ConnectivityResult.other:
        // Conservative: treat unknown/bluetooth/vpn as cellular
        return ConnectivityState.cellular;
    }
  }

  @override
  Future<void> initialize() async {
    try {
      _stateController = StreamController<ConnectivityState>.broadcast();

      // Get initial connectivity state
      final result = await _connectivity.checkConnectivity();
      _currentState = _mapResult(result);

      // Listen for changes
      _subscription = _connectivity.onConnectivityChanged.listen(
        (ConnectivityResult result) {
          final newState = _mapResult(result);
          if (newState != _currentState) {
            _currentState = newState;
            _stateController.add(newState);
          }
        },
        onError: (error) {
          _stateController.addError(
            ConnectivityServiceException('Stream error', error),
          );
        },
      );
    } catch (e) {
      throw ConnectivityServiceException(
        'Failed to initialize ConnectivityPlusService',
        e,
      );
    }
  }

  @override
  bool get isOnline => _currentState != ConnectivityState.offline;

  @override
  bool get isWifi =>
      _currentState == ConnectivityState.wifi ||
      _currentState == ConnectivityState.ethernet;

  @override
  ConnectivityState get state => _currentState;

  @override
  Stream<ConnectivityState> get onConnectivityChanged =>
      _stateController.stream;

  @override
  void dispose() {
    _subscription.cancel();
    _stateController.close();
  }
}
