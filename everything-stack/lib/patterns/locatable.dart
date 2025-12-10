/// # Locatable
/// 
/// ## What it does
/// Adds geographic coordinates to entities. Enables location-aware
/// features like proximity search and mapping.
/// 
/// ## What it enables
/// - "Find things near me"
/// - Map visualization of entities
/// - Distance-based sorting and filtering
/// - Geofencing and location triggers
/// 
/// ## Schema addition
/// ```dart
/// double? latitude;
/// double? longitude;
/// String? locationName; // Human-readable
/// ```
/// 
/// ## Usage
/// ```dart
/// class Tool extends BaseEntity with Locatable {
///   String name;
/// }
/// 
/// // Set location
/// tool.setLocation(42.3601, -71.0589, name: 'Boston');
/// 
/// // Find nearby
/// final nearbyTools = await toolRepo.findNear(
///   latitude: myLat,
///   longitude: myLng,
///   radiusKm: 5,
/// );
/// 
/// // Get distance
/// final km = tool.distanceTo(myLat, myLng);
/// ```
/// 
/// ## Performance
/// - Spatial indexing recommended for large datasets
/// - Bounding box pre-filter before precise distance calc
/// - Consider geohashing for efficient range queries
/// 
/// ## Testing approach
/// Proximity tests:
/// - Create entities at known locations
/// - Verify distance calculations are accurate
/// - Verify radius queries return correct results
/// - Test edge cases: poles, date line, zero distance
/// 
/// ## Integrates with
/// - Embeddable: "Find similar things nearby"
/// - Ownable: "My tools near current location"
/// - Temporal: "Events near me this weekend"

import '../utils/geo_utils.dart';

mixin Locatable {
  /// Latitude in decimal degrees (-90 to 90)
  double? latitude;
  
  /// Longitude in decimal degrees (-180 to 180)
  double? longitude;
  
  /// Human-readable location name
  String? locationName;
  
  /// Set location with optional name
  void setLocation(double lat, double lng, {String? name}) {
    latitude = lat;
    longitude = lng;
    locationName = name;
  }
  
  /// Clear location
  void clearLocation() {
    latitude = null;
    longitude = null;
    locationName = null;
  }
  
  /// Does this entity have a location?
  bool get hasLocation => latitude != null && longitude != null;
  
  /// Calculate distance to another point in kilometers.
  /// Uses Haversine formula for accuracy.
  double? distanceTo(double lat, double lng) {
    if (!hasLocation) return null;
    return haversineDistance(latitude!, longitude!, lat, lng);
  }

  /// Is this entity within radius of a point?
  bool isWithin(double lat, double lng, double radiusKm) {
    final dist = distanceTo(lat, lng);
    if (dist == null) return false;
    return dist <= radiusKm;
  }
}
