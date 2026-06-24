import 'package:flutter/foundation.dart';
import '../models/user_prefs.dart';
import 'supabase_service.dart';

class UserPrefsService extends ChangeNotifier {
  static final UserPrefsService _i = UserPrefsService._();
  factory UserPrefsService() => _i;
  UserPrefsService._();

  UserPrefs? _prefs;
  String? _userId; // users.id (not auth.uid)

  UserPrefs? get prefs => _prefs;
  String? get userId => _userId;
  bool get hasPrefs => _prefs != null && !_prefs!.isEmpty;

  Future<void> load() async {
    if (!SupabaseService.isLoggedIn) return;
    final authId = SupabaseService.currentUserId;
    if (authId == null) return;
    try {
      final userRow = await SupabaseService.client
          .from('users')
          .select('id')
          .eq('auth_id', authId)
          .maybeSingle();
      if (userRow == null) return;
      _userId = userRow['id'] as String;

      final row = await SupabaseService.client
          .from('user_preferences')
          .select()
          .eq('user_id', _userId!)
          .maybeSingle();
      if (row != null) {
        _prefs = UserPrefs.fromJson(row);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[UserPrefsService] load: $e');
    }
  }

  Future<void> save(UserPrefs prefs) async {
    if (!SupabaseService.isLoggedIn) return;
    final authId = SupabaseService.currentUserId;
    if (authId == null) return;
    try {
      String? uid = _userId;
      if (uid == null) {
        final userRow = await SupabaseService.client
            .from('users')
            .select('id')
            .eq('auth_id', authId)
            .maybeSingle();
        if (userRow == null) return;
        _userId = userRow['id'] as String;
        uid = _userId;
      }

      await SupabaseService.client.from('user_preferences').upsert({
        'user_id': uid,
        ...prefs.toJson(),
      });
      _prefs = prefs;
      notifyListeners();
    } catch (e) {
      debugPrint('[UserPrefsService] save: $e');
    }
  }

  Future<void> hideBrand(String brand) async {
    final current = _prefs;
    if (current == null || current.isHiddenBrand(brand)) return;
    await save(current.withHiddenBrand(brand));
  }

  Future<void> unhideBrand(String brand) async {
    final current = _prefs;
    if (current == null) return;
    await save(current.withoutHiddenBrand(brand));
  }

  void clear() {
    _prefs = null;
    _userId = null;
    notifyListeners();
  }
}
