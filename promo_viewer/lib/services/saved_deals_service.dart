import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/promotion.dart';
import 'interaction_service.dart';
import 'notification_service.dart';
import 'supabase_service.dart';
import 'user_prefs_service.dart';

class SavedDeal {
  final String id;
  final String brand;
  final String title;
  final String? endDate;
  final DateTime savedAt;
  final DateTime? remindAt;

  const SavedDeal({
    required this.id,
    required this.brand,
    required this.title,
    this.endDate,
    required this.savedAt,
    this.remindAt,
  });

  SavedDeal copyWith({DateTime? remindAt}) => SavedDeal(
        id: id,
        brand: brand,
        title: title,
        endDate: endDate,
        savedAt: savedAt,
        remindAt: remindAt ?? this.remindAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'brand': brand,
        'title': title,
        'endDate': endDate,
        'savedAt': savedAt.toIso8601String(),
        'remindAt': remindAt?.toIso8601String(),
      };

  factory SavedDeal.fromJson(Map<String, dynamic> j) => SavedDeal(
        id: j['id'] as String,
        brand: j['brand'] as String,
        title: j['title'] as String,
        endDate: j['endDate'] as String?,
        savedAt: DateTime.parse(j['savedAt'] as String),
        remindAt:
            j['remindAt'] != null ? DateTime.parse(j['remindAt'] as String) : null,
      );
}

class SavedDealsService extends ChangeNotifier {
  static final SavedDealsService _instance = SavedDealsService._();
  factory SavedDealsService() => _instance;
  SavedDealsService._();

  static const _key = 'candy_saved_deals';
  final Map<String, SavedDeal> _saved = {};
  SharedPreferences? _prefs;

  // User-scoped key so two accounts on the same device never share saves.
  String get _userKey {
    final uid = SupabaseService.currentUserId ?? 'guest';
    return '${_key}_$uid';
  }

  static Future<void> init() async {
    // Only initialises SharedPreferences — data is loaded in loadForUser()
    // once the authenticated user ID is known.
    SavedDealsService()._prefs = await SharedPreferences.getInstance();
  }

  /// Call after login / on app start when already logged in.
  Future<void> loadForUser(String userId) async {
    _saved.clear();
    final raw = _prefs?.getString('${_key}_$userId');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          final deal = SavedDeal.fromJson(item as Map<String, dynamic>);
          _saved[deal.id] = deal;
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Call on sign-out to wipe in-memory state immediately.
  void clearLocal() {
    _saved.clear();
    notifyListeners();
  }

  bool isSaved(String id) => _saved.containsKey(id);
  SavedDeal? get(String id) => _saved[id];

  List<SavedDeal> get all {
    final list = _saved.values.toList();
    list.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return list;
  }

  Future<void> save(Promotion promo, {DateTime? remindAt}) async {
    final now = DateTime.now();
    _saved[promo.id] = SavedDeal(
      id: promo.id,
      brand: promo.brand,
      title: promo.title,
      endDate: promo.endDate,
      savedAt: now,
      remindAt: remindAt,
    );
    await _persist();
    notifyListeners();

    // Supabase write (fire-and-forget)
    final uid = UserPrefsService().userId;
    if (uid != null && SupabaseService.isLoggedIn) {
      SupabaseService.client.from('saved_deals').upsert({
        'user_id':          uid,
        'promotion_id':     promo.id,
        'brand':            promo.brand,
        'title_snapshot':   promo.title,
        'source_url_snapshot': promo.sourceUrl,
        'saved_at':         now.toIso8601String(),
        'status':           'active',
      }, onConflict: 'user_id,promotion_id').then((_) {}, onError: (e) {
        if (kDebugMode) debugPrint('[SavedDealsService] save: $e');
      });
      InteractionService().bumpBrandAffinityPublic(promo.brand, saves: 1);
      InteractionService().bumpCategoryAffinityPublic(promo.category, saves: 1);
    }
  }

  Future<void> setReminder(String id, DateTime remindAt) async {
    final existing = _saved[id];
    if (existing == null) return;
    _saved[id] = existing.copyWith(remindAt: remindAt);
    await _persist();
    notifyListeners();
    await NotificationService().scheduleReminder(
      promoId: id,
      brand: existing.brand,
      title: existing.title,
      remindAt: remindAt,
    );
  }

  Future<void> unsave(String id) async {
    await NotificationService().cancelReminder(id);
    _saved.remove(id);
    await _persist();
    notifyListeners();

    // Supabase write (fire-and-forget)
    final uid = UserPrefsService().userId;
    if (uid != null && SupabaseService.isLoggedIn) {
      SupabaseService.client.from('saved_deals')
          .update({'status': 'deleted', 'deleted_at': DateTime.now().toIso8601String()})
          .eq('user_id', uid)
          .eq('promotion_id', id)
          .then((_) {}, onError: (e) {
        if (kDebugMode) debugPrint('[SavedDealsService] unsave: $e');
      });
    }
  }

  Future<void> _persist() async {
    final list = _saved.values.map((d) => d.toJson()).toList();
    await _prefs?.setString(_userKey, jsonEncode(list));
  }
}
