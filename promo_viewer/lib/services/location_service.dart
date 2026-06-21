import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/promotion.dart';
import 'remote_data_service.dart';

Map<String, List<List<double>>> _parseLocations(String raw) {
  final data = json.decode(raw) as Map<String, dynamic>;
  final brands = data['brands'] as Map<String, dynamic>;
  return brands.map((brand, coords) {
    final list = (coords as List)
        .map((e) => [e[0] as double, e[1] as double])
        .toList();
    return MapEntry(brand, list);
  });
}

class LocationService {
  static Map<String, List<List<double>>>? _locations;

  /// Load brand_locations.json once and cache it.
  static Future<Map<String, List<List<double>>>> _loadLocations() async {
    if (_locations != null) return _locations!;
    final raw = await RemoteDataService.load('brand_locations.json');
    _locations = await compute(_parseLocations, raw);
    return _locations!;
  }

  /// Request location permission and return the current position, or null.
  static Future<Position?> getPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) return null;

      // Use high accuracy (GPS) so iOS doesn't serve a stale cell-tower position
      // from a previous city. 15-second timeout guards against no GPS signal indoors.
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        // GPS timed out (indoors, etc.) — fall back to last known position.
        return await Geolocator.getLastKnownPosition();
      }
    } catch (_) {
      return null;
    }
  }

  /// Haversine distance in km between two lat/lng points.
  static double haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Find distance to the nearest store for a brand.
  static double? nearestKm(
    String brand,
    double userLat,
    double userLng,
    Map<String, List<List<double>>> locations,
  ) {
    final stores = locations[brand];
    if (stores == null || stores.isEmpty) return null;
    double? best;
    for (final s in stores) {
      final d = haversineKm(userLat, userLng, s[0], s[1]);
      if (best == null || d < best) best = d;
    }
    return best;
  }

  /// Attach distanceKm to every promotion in-place.
  static Future<void> attachDistances(
    List<Promotion> promos,
    Position position,
  ) async {
    final locations = await _loadLocations();
    for (final p in promos) {
      if (p.isLocal && p.lat != null && p.lon != null) {
        // Local businesses use their embedded neighborhood coordinates.
        p.distanceKm = haversineKm(position.latitude, position.longitude, p.lat!, p.lon!);
      } else {
        p.distanceKm = nearestKm(p.brand, position.latitude, position.longitude, locations);
      }
    }
  }

  static String formatDistance(double? km) {
    if (km == null) return '';
    final miles = km * 0.621371;
    if (miles < 0.1) return '< 0.1 mi';
    if (miles < 10) return '${miles.toStringAsFixed(1)} mi';
    return '${miles.round()} mi';
  }

  /// Rough city name from coordinates — no API, purely bounding-box lookup.
  static String cityName(double lat, double lon) {
    const cities = <(double, double, double, double, String)>[
      (37.63, 37.93, -122.55, -122.33, 'San Francisco'),
      (37.33, 37.63, -122.15, -121.85, 'San Jose'),
      (37.73, 37.93, -122.35, -122.15, 'Oakland'),
      (47.45, 47.75, -122.50, -122.20, 'Seattle'),
      (47.45, 47.75, -122.20, -122.00, 'Bellevue'),
      (34.00, 34.15, -118.55, -118.15, 'Los Angeles'),
      (32.65, 32.85, -117.25, -117.05, 'San Diego'),
      (33.35, 33.65, -112.35, -111.85, 'Phoenix'),
      (39.65, 39.85, -105.10, -104.85, 'Denver'),
      (41.65, 42.05, -87.90, -87.55, 'Chicago'),
      (29.55, 30.10, -95.70, -95.05, 'Houston'),
      (32.60, 33.00, -97.00, -96.55, 'Dallas'),
      (30.15, 30.55, -97.95, -97.55, 'Austin'),
      (40.60, 40.90, -74.05, -73.85, 'New York'),
      (42.25, 42.45, -71.20, -71.00, 'Boston'),
      (38.80, 39.00, -77.20, -76.90, 'Washington DC'),
      (39.85, 40.05, -75.30, -74.95, 'Philadelphia'),
      (33.65, 33.85, -84.50, -84.30, 'Atlanta'),
      (25.65, 25.90, -80.40, -80.10, 'Miami'),
      (35.95, 36.25, -86.95, -86.65, 'Nashville'),
      (36.05, 36.25, -115.25, -115.05, 'Las Vegas'),
      (45.45, 45.65, -122.75, -122.55, 'Portland'),
    ];

    for (final (latMin, latMax, lonMin, lonMax, name) in cities) {
      if (lat >= latMin && lat <= latMax && lon >= lonMin && lon <= lonMax) {
        return name;
      }
    }
    return '${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)}';
  }
}
