import 'package:flutter/foundation.dart';
import '../models/user_prefs.dart';
import 'supabase_service.dart';

class UserPrefsService extends ChangeNotifier {
  static final UserPrefsService _i = UserPrefsService._();
  factory UserPrefsService() => _i;
  UserPrefsService._();

  // Shared notifier so ProfileScreen writes and FeedScreen reacts instantly.
  static final nearMeRadiusNotifier = ValueNotifier<int>(5);

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
        var userRow = await SupabaseService.client
            .from('users')
            .select('id')
            .eq('auth_id', authId)
            .maybeSingle();

        // Recovery: users row missing (signUp insert failed). Create it now.
        if (userRow == null) {
          final email = SupabaseService.client.auth.currentUser?.email ?? '';
          await SupabaseService.client.from('users').insert({
            'auth_id': authId,
            'email':   email,
          });
          userRow = await SupabaseService.client
              .from('users')
              .select('id')
              .eq('auth_id', authId)
              .single();
        }

        _userId = userRow['id'] as String;
        uid = _userId;
      }

      // onConflict: 'user_id' ensures UPDATE on re-save, not duplicate INSERT.
      await SupabaseService.client.from('user_preferences').upsert(
        {'user_id': uid, ...prefs.toJson()},
        onConflict: 'user_id',
      );
      _prefs = prefs;
      notifyListeners();
    } catch (e) {
      debugPrint('[UserPrefsService] save: $e');
      rethrow;
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
