import 'supabase_service.dart';
import 'user_prefs_service.dart';

class UserMembershipsService {
  static Future<Set<String>> load() async {
    final owner = SupabaseService.currentUserId;
    if (owner == null) return {};
    if (UserPrefsService().userId == null) await UserPrefsService().load();
    if (owner != SupabaseService.currentUserId) return {};
    return (UserPrefsService().prefs?.memberships ?? const <String>[])
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  /// Returns true if the user has a membership that matches the brand name
  /// or membership name of the promotion.
  static bool hasMembership(
    Set<String> programs,
    String brand,
    String? membershipName,
  ) {
    final brandL = brand.trim().toLowerCase();
    final nameL = (membershipName ?? '').trim().toLowerCase();
    return programs.any(
      (p) =>
          p.isNotEmpty &&
          ((brandL.isNotEmpty && (p.contains(brandL) || brandL.contains(p))) ||
              (nameL.isNotEmpty && (p.contains(nameL) || nameL.contains(p)))),
    );
  }
}
