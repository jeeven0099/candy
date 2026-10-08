import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_prefs.dart';
import 'supabase_service.dart';
import 'learned_preference_service.dart';

class UserPrefsService extends ChangeNotifier {
  static final UserPrefsService _i = UserPrefsService._();
  factory UserPrefsService() => _i;
  UserPrefsService._();

  // Shared notifier so ProfileScreen writes and FeedScreen reacts instantly.
  static final nearMeRadiusNotifier = ValueNotifier<int>(5);
  static String localKey(String name) =>
      '$name|${SupabaseService.currentUserId ?? 'guest'}';

  static Future<int> loadNearMeRadius() async {
    final owner = SupabaseService.currentUserId;
    final key = localKey('near_me_radius_mi');
    final storage = await SharedPreferences.getInstance();
    if (owner != SupabaseService.currentUserId) return 5;
    return _i.userId == null
        ? storage.getInt(key) ?? 5
        : nearMeRadiusNotifier.value;
  }

  static Future<void> setNearMeRadius(int miles) async {
    final owner = SupabaseService.currentUserId;
    final key = localKey('near_me_radius_mi');
    final storage = await SharedPreferences.getInstance();
    await storage.setInt(key, miles);
    if (owner != SupabaseService.currentUserId) return;
    nearMeRadiusNotifier.value = miles;
    if (owner != null) {
      await SupabaseService.client
          .from('users')
          .update({'radius_miles': miles})
          .eq('auth_id', owner);
    }
  }

  UserPrefs? _prefs;
  String? _userId; // users.id (not auth.uid)
  String? _owner;
  int _generation = 0;

  bool get _ownsState =>
      _owner != null && _owner == SupabaseService.currentUserId;
  UserPrefs? get prefs => _ownsState ? _prefs : null;
  String? get userId => _ownsState ? _userId : null;
  bool get hasPrefs => prefs != null && !prefs!.isEmpty;

  Future<void> load() async {
    if (!SupabaseService.isLoggedIn) return;
    final authId = SupabaseService.currentUserId;
    if (authId == null) return;
    final generation = ++_generation;
    if (_owner != authId) {
      _prefs = null;
      _userId = null;
      _owner = authId;
    }
    try {
      final userRow = await SupabaseService.client
          .from('users')
          .select('id,radius_miles')
          .eq('auth_id', authId)
          .maybeSingle();
      if (generation != _generation ||
          authId != SupabaseService.currentUserId ||
          userRow == null) {
        return;
      }
      final uid = userRow['id'] as String;

      final row = await SupabaseService.client
          .from('user_preferences')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (generation != _generation ||
          authId != SupabaseService.currentUserId) {
        return;
      }
      _userId = uid;
      _prefs = row == null ? null : UserPrefs.fromJson(row);
      nearMeRadiusNotifier.value =
          (userRow['radius_miles'] as num?)?.toInt() ?? 5;
      notifyListeners();
    } catch (e) {
      debugPrint('[UserPrefsService] load: $e');
    }
  }

  Future<void> save(UserPrefs prefs) async {
    if (!SupabaseService.isLoggedIn) return;
    final authId = SupabaseService.currentUserId;
    if (authId == null) return;
    final generation = ++_generation;
    try {
      String? uid = userId;
      if (uid == null) {
        var userRow = await SupabaseService.client
            .from('users')
            .select('id')
            .eq('auth_id', authId)
            .maybeSingle();

        // Recovery: users row missing (signUp insert failed). Create it now.
        if (userRow == null) {
          if (authId != SupabaseService.currentUserId) return;
          final email = SupabaseService.client.auth.currentUser?.email ?? '';
          await SupabaseService.client.from('users').insert({
            'auth_id': authId,
            'email': email,
          });
          userRow = await SupabaseService.client
              .from('users')
              .select('id')
              .eq('auth_id', authId)
              .single();
        }

        uid = userRow['id'] as String;
      }

      if (authId != SupabaseService.currentUserId ||
          generation != _generation) {
        return;
      }
      // onConflict: 'user_id' ensures UPDATE on re-save, not duplicate INSERT.
      await SupabaseService.client.from('user_preferences').upsert({
        'user_id': uid,
        ...prefs.toJson(),
      }, onConflict: 'user_id');
      if (authId != SupabaseService.currentUserId ||
          generation != _generation) {
        return;
      }
      _owner = authId;
      _userId = uid;
      _prefs = prefs;
      notifyListeners();
    } catch (e) {
      debugPrint('[UserPrefsService] save: $e');
      rethrow;
    }
  }

  Future<void> hideBrand(String brand) async {
    final current = prefs;
    if (current == null || current.isHiddenBrand(brand)) return;
    await save(current.withHiddenBrand(brand));
  }

  Future<void> unhideBrand(String brand) async {
    final current = prefs;
    if (current == null) return;
    await save(current.withoutHiddenBrand(brand));
  }

  void clear() {
    _generation++;
    _owner = null;
    nearMeRadiusNotifier.value = 5;
    LearnedPreferenceService().clear();
    _prefs = null;
    _userId = null;
    notifyListeners();
  }
}
