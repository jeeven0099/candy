import 'dart:convert';
import 'remote_data_service.dart';

class UserMembershipsService {
  static Set<String>? _programs;

  static Future<Set<String>> load() async {
    if (_programs != null) return _programs!;
    try {
      final raw = await RemoteDataService.load('user_memberships.json');
      final data = json.decode(raw) as Map<String, dynamic>;
      final list = data['memberships'] as List<dynamic>? ?? [];
      _programs = list
          .cast<Map<String, dynamic>>()
          .map((m) => (m['program'] as String? ?? '').toLowerCase())
          .where((s) => s.isNotEmpty)
          .toSet();
    } catch (_) {
      _programs = {};
    }
    return _programs!;
  }

  /// Returns true if the user has a membership that matches the brand name
  /// or membership name of the promotion.
  static bool hasMembership(Set<String> programs, String brand, String? membershipName) {
    final brandL = brand.toLowerCase();
    final nameL = (membershipName ?? '').toLowerCase();
    return programs.any((p) =>
        p.contains(brandL) || brandL.contains(p) ||
        (nameL.isNotEmpty && (p.contains(nameL) || nameL.contains(p))));
  }
}
