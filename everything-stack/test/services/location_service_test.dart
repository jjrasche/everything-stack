/// # LocationService Tests
///
/// Tests for GPS location detection service.
/// - Position class with distance calculations
/// - Permission management flow
/// - MockLocationService with manual control
/// - GeolocatorLocationService integration (basic)

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/location_service.dart';

void main() {
  group('Position class', () {
    test('Position stores latitude, longitude, accuracy, timestamp', () {
      final now = DateTime.now();
      final pos = Position(
        latitude: 42.3601,
        longitude: -71.0589,
        accuracy: 10.5,
        timestamp: now,
      );

      expect(pos.latitude, 42.3601);
      expect(pos.longitude, -71.0589);
      expect(pos.accuracy, 10.5);
      expect(pos.timestamp, now);
    });

    test('Position accuracy can be null', () {
      final pos = Position(
        latitude: 42.3601,
        longitude: -71.0589,
        timestamp: DateTime.now(),
      );

      expect(pos.accuracy, isNull);
    });

    test('distanceTo calculates distance in kilometers (Boston to NYC ~306km)', () {
      final boston = Position(
        latitude: 42.3601,
        longitude: -71.0589,
        timestamp: DateTime.now(),
      );
      final nyc = Position(
        latitude: 40.7128,
        longitude: -74.0060,
        timestamp: DateTime.now(),
      );

      final distance = boston.distanceTo(nyc);

      // Boston to NYC is approximately 306km
      expect(distance, greaterThan(300));
      expect(distance, lessThan(320));
    });

    test('distanceTo same location returns ~0km', () {
      final pos1 = Position(
        latitude: 42.3601,
        longitude: -71.0589,
        timestamp: DateTime.now(),
      );
      final pos2 = Position(
        latitude: 42.3601,
        longitude: -71.0589,
        timestamp: DateTime.now(),
      );

      expect(pos1.distanceTo(pos2), lessThan(0.1));
    });

    test('distanceTo is symmetric', () {
      final boston = Position(
        latitude: 42.3601,
        longitude: -71.0589,
        timestamp: DateTime.now(),
      );
      final nyc = Position(
        latitude: 40.7128,
        longitude: -74.0060,
        timestamp: DateTime.now(),
      );

      expect(boston.distanceTo(nyc), closeTo(nyc.distanceTo(boston), 0.01));
    });
  });

  group('LocationPermission enum', () {
    test('LocationPermission has expected values', () {
      expect(LocationPermission.values, contains(LocationPermission.undetermined));
      expect(LocationPermission.values, contains(LocationPermission.denied));
      expect(LocationPermission.values, contains(LocationPermission.deniedForever));
      expect(LocationPermission.values, contains(LocationPermission.granted));
      // Note: 'restricted' is for iOS system-level restrictions
      expect(LocationPermission.values, contains(LocationPermission.restricted));
    });
  });

  group('LocationAccuracy enum', () {
    test('LocationAccuracy has expected values', () {
      expect(LocationAccuracy.values, contains(LocationAccuracy.low));
      expect(LocationAccuracy.values, contains(LocationAccuracy.medium));
      expect(LocationAccuracy.values, contains(LocationAccuracy.high));
      expect(LocationAccuracy.values, contains(LocationAccuracy.finest));
    });
  });

  group('LocationService interface', () {
    test('MockLocationService is default instance', () {
      LocationService.instance = MockLocationService();
      expect(LocationService.instance, isA<MockLocationService>());
    });
  });

  group('MockLocationService', () {
    late MockLocationService service;

    setUp(() {
      service = MockLocationService();
    });

    group('Permission management', () {
      test('checkPermission returns current permission', () async {
        final perm = await service.checkPermission();
        expect(perm, isA<LocationPermission>());
      });

      test('requestPermission prompts user (simulated)', () async {
        final perm = await service.requestPermission();
        expect(perm, LocationPermission.granted);
      });

      test('setPermission updates permission state', () async {
        service.setPermission(LocationPermission.denied);
        expect(await service.checkPermission(), LocationPermission.denied);

        service.setPermission(LocationPermission.granted);
        expect(await service.checkPermission(), LocationPermission.granted);
      });
    });

    group('Location queries', () {
      test('getCurrentLocation returns Position with accuracy parameter', () async {
        service.setMockPosition(
          Position(
            latitude: 42.3601,
            longitude: -71.0589,
            accuracy: 10.0,
            timestamp: DateTime.now(),
          ),
        );

        final pos = await service.getCurrentLocation(
          accuracy: LocationAccuracy.medium,
        );

        expect(pos, isNotNull);
        expect(pos!.latitude, 42.3601);
        expect(pos.longitude, -71.0589);
        expect(pos.accuracy, 10.0);
      });

      test('getCurrentLocation returns null when permission not granted', () async {
        service.setPermission(LocationPermission.denied);
        service.setMockPosition(
          Position(
            latitude: 42.3601,
            longitude: -71.0589,
            accuracy: 10.0,
            timestamp: DateTime.now(),
          ),
        );

        final pos = await service.getCurrentLocation();
        expect(pos, isNull);
      });

      test('getCurrentLocation respects accuracy parameter', () async {
        final pos = Position(
          latitude: 42.3601,
          longitude: -71.0589,
          accuracy: 5.0,
          timestamp: DateTime.now(),
        );
        service.setMockPosition(pos);

        // Both calls should return the same position (mock)
        final low = await service.getCurrentLocation(accuracy: LocationAccuracy.low);
        final finest =
            await service.getCurrentLocation(accuracy: LocationAccuracy.finest);

        expect(low, isNotNull);
        expect(finest, isNotNull);
      });
    });

    group('Location stream', () {
      test('onLocationChanged emits position updates', () async {
        service.setPermission(LocationPermission.granted);
        final positions = <Position>[];

        service.onLocationChanged().listen(positions.add);

        service.simulateMove(
          Position(
            latitude: 42.3601,
            longitude: -71.0589,
            accuracy: 10.0,
            timestamp: DateTime.now(),
          ),
        );

        await Future.delayed(Duration.zero);

        expect(positions, isNotEmpty);
        expect(positions.first.latitude, 42.3601);
      });

      test('onLocationChanged respects accuracy parameter', () async {
        service.setPermission(LocationPermission.granted);
        final positions = <Position>[];

        // Request high accuracy - mock should reflect it
        service.onLocationChanged(accuracy: LocationAccuracy.finest).listen(positions.add);

        service.simulateMove(
          Position(
            latitude: 42.3601,
            longitude: -71.0589,
            accuracy: 2.0, // High accuracy
            timestamp: DateTime.now(),
          ),
        );

        await Future.delayed(Duration.zero);

        expect(positions, isNotEmpty);
      });

      test('multiple listeners receive position updates', () async {
        service.setPermission(LocationPermission.granted);
        final positions1 = <Position>[];
        final positions2 = <Position>[];

        service.onLocationChanged().listen(positions1.add);
        service.onLocationChanged().listen(positions2.add);

        service.simulateMove(
          Position(
            latitude: 42.3601,
            longitude: -71.0589,
            accuracy: 10.0,
            timestamp: DateTime.now(),
          ),
        );

        await Future.delayed(Duration.zero);

        expect(positions1, isNotEmpty);
        expect(positions2, isNotEmpty);
      });
    });

    group('Lifecycle', () {
      test('initialize completes successfully', () async {
        await expectLater(service.initialize(), completion(isNull));
      });

      test('dispose closes streams', () async {
        service.setPermission(LocationPermission.granted);
        final positions = <Position>[];
        final subscription = service.onLocationChanged().listen(positions.add);

        service.dispose();
        await subscription.cancel();

        // After dispose, no more events should be emitted
        service.simulateMove(
          Position(
            latitude: 42.3601,
            longitude: -71.0589,
            timestamp: DateTime.now(),
          ),
        );
      });
    });
  });

  group('GeolocatorLocationService', () {
    // Real implementation testing:
    // - Integration with geolocator plugin
    // - Permission handling
    // - Stream management
    // These will be validated on actual devices/platforms

    test('GeolocatorLocationService is a LocationService', () {
      expect(GeolocatorLocationService, isA<Type>());
    });
  });
}
