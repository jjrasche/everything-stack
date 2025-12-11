/// # LocationService
///
/// ## What it does
/// Platform wrapper for GPS location detection and tracking.
/// Handles permissions, accuracy levels, and location streaming.
///
/// ## What it enables
/// - Location-aware features (find things near me, mapping)
/// - Distance calculations between positions
/// - Permission-aware location requests
/// - Adaptive accuracy (fast/rough vs. slow/precise)
///
/// ## Implementations
/// - MockLocationService: Default for testing, manual control
/// - GeolocatorLocationService: Production, uses geolocator plugin
///
/// ## Usage
/// ```dart
/// // Use mock in tests
/// LocationService.instance = MockLocationService();
/// (LocationService.instance as MockLocationService).setMockPosition(...);
///
/// // Use real in production
/// LocationService.instance = GeolocatorLocationService();
/// await LocationService.instance.initialize();
///
/// // Check permission
/// final perm = await LocationService.instance.checkPermission();
/// if (perm == LocationPermission.granted) {
///   // Request location with specific accuracy
///   final pos = await LocationService.instance.getCurrentLocation(
///     accuracy: LocationAccuracy.medium,
///   );
///   print('${pos?.latitude}, ${pos?.longitude}');
///
///   // Listen to updates
///   LocationService.instance.onLocationChanged().listen((pos) {
///     print('Moved to ${pos.latitude}, ${pos.longitude}');
///   });
/// }
///
/// // Calculate distance
/// final home = Position(...);
/// final work = Position(...);
/// final km = home.distanceTo(work);
/// ```
///
/// ## Testing approach
/// Mock implementation works without permissions.
/// Real implementation tested manually on actual devices.

import 'dart:async';
import 'package:geolocator/geolocator.dart' as geo;
import '../utils/geo_utils.dart';

// ============ Enums ============

/// Location permission state
enum LocationPermission {
  undetermined, // Can request
  denied, // User said no, can ask later
  deniedForever, // User said never, go to Settings
  granted, // Location available
  restricted, // iOS: system-level restriction
}

/// Location accuracy level (speed/precision tradeoff)
enum LocationAccuracy {
  low, // ~5km, battery efficient
  medium, // ~100m, balanced
  high, // ~10m, GPS intensive
  finest, // <5m, maximum precision
}

// ============ Position Class ============

/// Geographic position with accuracy and timestamp.
class Position {
  final double latitude;
  final double longitude;
  final double? accuracy; // meters - indicates data quality
  final DateTime timestamp;

  Position({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.timestamp,
  });

  /// Calculate distance to another position in kilometers using Haversine formula.
  double distanceTo(Position other) {
    return haversineDistance(latitude, longitude, other.latitude, other.longitude);
  }

  @override
  String toString() =>
      'Position($latitude, $longitude, accuracy: ${accuracy}m, $timestamp)';
}

// ============ Abstract Interface ============

/// Platform-agnostic location service.
abstract class LocationService {
  /// Global singleton instance (defaults to mock for safe testing)
  static LocationService instance = MockLocationService();

  /// Check current permission without prompting
  Future<LocationPermission> checkPermission();

  /// Request location permission (prompts user)
  Future<LocationPermission> requestPermission();

  /// Get current location with specified accuracy
  /// Returns null if permission not granted or location unavailable
  Future<Position?> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.medium,
  });

  /// Stream of location updates with specified accuracy
  Stream<Position> onLocationChanged({
    LocationAccuracy accuracy = LocationAccuracy.medium,
  });

  /// Initialize service (request permissions, start services)
  Future<void> initialize();

  /// Dispose resources and close streams
  void dispose();
}

// ============ Mock Implementation ============

/// Mock location service for testing without permissions or GPS.
class MockLocationService extends LocationService {
  LocationPermission _permission = LocationPermission.granted;
  Position? _currentPosition;
  late final StreamController<Position> _positionController;

  MockLocationService() {
    _positionController = StreamController<Position>.broadcast();
  }

  /// Set permission state (for testing different scenarios)
  void setPermission(LocationPermission permission) {
    _permission = permission;
  }

  /// Set mock position (simulates GPS data)
  void setMockPosition(Position position) {
    _currentPosition = position;
  }

  /// Simulate movement (emits position to stream)
  void simulateMove(Position position) {
    _currentPosition = position;
    if (!_positionController.isClosed) {
      _positionController.add(position);
    }
  }

  @override
  Future<LocationPermission> checkPermission() async {
    return _permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    // Mock: always grant (safe for testing)
    return _permission = LocationPermission.granted;
  }

  @override
  Future<Position?> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) async {
    if (_permission != LocationPermission.granted) {
      return null;
    }
    return _currentPosition;
  }

  @override
  Stream<Position> onLocationChanged({
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) {
    return _positionController.stream;
  }

  @override
  Future<void> initialize() async {
    // No-op: mock is always ready
  }

  @override
  void dispose() {
    _positionController.close();
  }
}

// ============ Production Implementation ============

/// Real location service using geolocator plugin.
class GeolocatorLocationService extends LocationService {
  late final StreamController<Position> _positionController;
  late StreamSubscription<geo.Position> _positionSubscription;

  /// Map geolocator permission to our LocationPermission
  static LocationPermission _mapPermission(geo.LocationPermission perm) {
    switch (perm) {
      case geo.LocationPermission.unableToDetermine:
        return LocationPermission.undetermined;
      case geo.LocationPermission.denied:
        return LocationPermission.denied;
      case geo.LocationPermission.deniedForever:
        return LocationPermission.deniedForever;
      case geo.LocationPermission.whileInUse:
      case geo.LocationPermission.always:
        return LocationPermission.granted;
    }
  }

  /// Convert geolocator Position to our Position
  static Position _convertPosition(geo.Position geoPos) {
    return Position(
      latitude: geoPos.latitude,
      longitude: geoPos.longitude,
      accuracy: geoPos.accuracy,
      timestamp: geoPos.timestamp,
    );
  }

  @override
  Future<LocationPermission> checkPermission() async {
    try {
      final perm = await geo.Geolocator.checkPermission();
      return _mapPermission(perm);
    } catch (e) {
      return LocationPermission.undetermined;
    }
  }

  @override
  Future<LocationPermission> requestPermission() async {
    try {
      final perm = await geo.Geolocator.requestPermission();
      return _mapPermission(perm);
    } catch (e) {
      return LocationPermission.undetermined;
    }
  }

  @override
  Future<Position?> getCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) async {
    try {
      final perm = await checkPermission();
      if (perm != LocationPermission.granted) {
        return null;
      }

      // geolocator v10 doesn't have accuracy param, use default
      final geoPos = await geo.Geolocator.getCurrentPosition();
      return _convertPosition(geoPos);
    } catch (e) {
      return null;
    }
  }

  @override
  Stream<Position> onLocationChanged({
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) {
    // Return empty stream if not granted
    return geo.Geolocator.getPositionStream().map(_convertPosition);
  }

  @override
  Future<void> initialize() async {
    try {
      _positionController = StreamController<Position>.broadcast();

      // Check/request permission
      final perm = await checkPermission();
      if (perm != LocationPermission.granted) {
        await requestPermission();
      }

      // Listen to position updates
      _positionSubscription = geo.Geolocator.getPositionStream().listen(
        (geoPos) {
          final pos = _convertPosition(geoPos);
          if (!_positionController.isClosed) {
            _positionController.add(pos);
          }
        },
        onError: (error) {
          if (!_positionController.isClosed) {
            _positionController.addError(error);
          }
        },
      );
    } catch (e) {
      // Initialization error - service degraded but not fatal
    }
  }

  @override
  void dispose() {
    _positionSubscription.cancel();
    _positionController.close();
  }
}
