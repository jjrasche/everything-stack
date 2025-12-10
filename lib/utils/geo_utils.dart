/// Geospatial utilities shared across location-aware services and patterns.

import 'package:geolocator/geolocator.dart' as geo;

/// Calculate great-circle distance between two geographic points.
/// Uses geolocator's tested implementation internally.
/// Returns distance in kilometers.
double haversineDistance(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  // Use geolocator's distanceBetween which returns meters
  final distanceMeters = geo.Geolocator.distanceBetween(lat1, lon1, lat2, lon2);

  // Convert to kilometers for consistency with our API
  return distanceMeters / 1000.0;
}
