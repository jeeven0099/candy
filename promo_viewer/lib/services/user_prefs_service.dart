import 'package:flutter/foundation.dart';
import '../models/user_prefs.dart';
import 'supabase_service.dart';

class UserPrefsService extends ChangeNotifier {
  static final UserPrefsService _i = UserPrefsService._();
  factory UserPrefsService() => _i;
  UserPrefsService._();

  UserPrefs? _prefs;

  UserPrefs? get prefs => _prefs;
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

      final row = await SupabaseService.client
          .from('user_preferences')
          .select()
          .eq('user_id', userRow['id'] as String)
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
      final userRow = await SupabaseService.client
          .from('users')
          .select('id')
          .eq('auth_id', authId)
          .maybeSingle();
      if (userRow == null) return;

      await SupabaseService.client.from('user_preferences').upsert({
        'user_id': userRow['id'] as String,
        ...prefs.toJson(),
      });
      _prefs = prefs;
      notifyListeners();
    } catch (e) {
      debugPrint('[UserPrefsService] save: $e');
    }
  }

  void clear() {
    _prefs = null;
    notifyListeners();
  }
}
