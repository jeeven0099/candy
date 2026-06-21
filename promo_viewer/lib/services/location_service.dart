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
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low, // city-level is enough
        ),
      );
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
}
