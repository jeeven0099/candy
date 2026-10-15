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
    remindAt: j['remindAt'] != null
        ? DateTime.parse(j['remindAt'] as String)
        : null,
  );
}

class SavedDealsService extends ChangeNotifier {
  static final SavedDealsService _instance = SavedDealsService._();
  factory SavedDealsService() => _instance;
  SavedDealsService._()
    : _currentAccount = (() => SupabaseService.currentUserId);

  @visibleForTesting
  SavedDealsService.forTesting({
    required String? Function() currentAccount,
    required SharedPreferences storage,
  }) : _currentAccount = currentAccount,
       _prefs = storage;

  static const _key = 'candy_saved_deals';
  final Map<String, SavedDeal> _saved = {};
  SharedPreferences? _prefs;
  final String? Function() _currentAccount;
  String? _owner;
  int _generation = 0;
  Future<void> _remoteWrites = Future<void>.value();
  bool get _ownsState => _owner == _currentAccount();

  // User-scoped key so two accounts on the same device never share saves.
  String _userKey(String? owner) {
    final uid = owner ?? 'guest';
    return '${_key}_$uid';
  }

  static Future<void> init() async {
    // Load only the current account's cache; startup reloads after auth restores.
    SavedDealsService()._prefs = await SharedPreferences.getInstance();
    await SavedDealsService().loadForUser(
      SupabaseService.currentUserId ?? 'guest',
    );
  }

  /// Call after login / on app start when already logged in.
  Future<void> loadForUser(String userId) async {
    final owner = userId == 'guest' ? null : userId;
    if (owner != _currentAccount()) return;
    final generation = ++_generation;
    _prefs ??= await SharedPreferences.getInstance();
    if (owner != _currentAccount() || generation != _generation) return;
    _owner = owner;
    _saved.clear();
    final raw = _prefs?.getString(_userKey(owner));
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
    _generation++;
    _owner = _currentAccount();
    _saved.clear();
    notifyListeners();
  }

  bool isSaved(String id) => _ownsState && _saved.containsKey(id);
  SavedDeal? get(String id) => _ownsState ? _saved[id] : null;

  List<SavedDeal> get all {
    if (!_ownsState) return [];
    final list = _saved.values.toList();
    list.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return list;
  }

  Future<void> save(
    Promotion promo, {
    DateTime? remindAt,
    Map<String, dynamic>? feedbackMeta,
  }) async {
    final owner = _currentAccount();
    _prefs ??= await SharedPreferences.getInstance();
    if (owner != _currentAccount()) return;
    if (!_ownsState) clearLocal();
    if (_saved.containsKey(promo.id)) return;
    final uid = UserPrefsService().userId;
    final meta = feedbackMeta ?? InteractionService.promoMeta(promo);
    final now = DateTime.now();
    final entry = SavedDeal(
      id: promo.id,
      brand: promo.brand,
      title: promo.title,
      endDate: promo.endDate,
      savedAt: now,
      remindAt: remindAt,
    );
    _saved[promo.id] = entry;
    try {
      await _persist(owner);
    } catch (_) {
      if (owner == _currentAccount() &&
          _ownsState &&
          identical(_saved[promo.id], entry)) {
        _saved.remove(promo.id);
        notifyListeners();
      }
      rethrow;
    }
    if (owner != _currentAccount()) return;
    notifyListeners();

    if (owner != _currentAccount()) return;
    InteractionService().recordDealSaved(
      promo.id,
      brand: promo.brand,
      category: promo.category,
      meta: meta,
    );

    // Keep save/remove requests ordered, including rapid swipe Undo.
    if (uid != null && SupabaseService.isLoggedIn) {
      _queueRemoteWrite(
        owner,
        'save',
        () => SupabaseService.client.from('saved_deals').upsert({
          'user_id': uid,
          'promotion_id': promo.id,
          'brand': promo.brand,
          'title_snapshot': promo.title,
          'source_url_snapshot': promo.sourceUrl,
          'saved_at': now.toIso8601String(),
          'status': 'active',
          'deleted_at': null,
        }, onConflict: 'user_id,promotion_id'),
      );
      InteractionService().bumpBrandAffinityPublic(promo.brand, saves: 1);
      InteractionService().bumpCategoryAffinityPublic(promo.category, saves: 1);
    }
  }

  Future<void> setReminder(String id, DateTime remindAt) async {
    if (!_ownsState) return;
    final owner = _currentAccount();
    final existing = _saved[id];
    if (existing == null) return;
    _saved[id] = existing.copyWith(remindAt: remindAt);
    await _persist(owner);
    if (owner != _currentAccount()) return;
    notifyListeners();
    if (owner != _currentAccount()) return;
    await NotificationService().scheduleReminder(
      promoId: id,
      brand: existing.brand,
      title: existing.title,
      remindAt: remindAt,
    );
  }

  Future<void> unsave(String id, {Map<String, dynamic>? feedbackMeta}) async {
    if (!_ownsState) return;
    final owner = _currentAccount();
    final uid = UserPrefsService().userId;
    final existing = _saved[id];
    if (existing == null) return;
    await NotificationService().cancelReminder(id);
    if (owner != _currentAccount()) return;
    _saved.remove(id);
    try {
      await _persist(owner);
    } catch (_) {
      if (owner == _currentAccount() && _ownsState && !_saved.containsKey(id)) {
        _saved[id] = existing;
        notifyListeners();
      }
      rethrow;
    }
    if (owner != _currentAccount()) return;
    notifyListeners();

    if (owner != _currentAccount()) return;
    InteractionService().recordDealUnsaved(
      id,
      brand: existing.brand,
      meta: feedbackMeta,
    );

    // Supabase write (fire-and-forget)
    if (uid != null && SupabaseService.isLoggedIn) {
      _queueRemoteWrite(
        owner,
        'unsave',
        () => SupabaseService.client
            .from('saved_deals')
            .update({
              'status': 'deleted',
              'deleted_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', uid)
            .eq('promotion_id', id),
      );
    }
  }

  void _queueRemoteWrite(
    String? owner,
    String action,
    Future<dynamic> Function() write,
  ) {
    _remoteWrites = _remoteWrites.then((_) async {
      if (owner != _currentAccount()) return;
      try {
        await write();
      } catch (error) {
        if (kDebugMode) debugPrint('[SavedDealsService] $action: $error');
      }
    });
  }

  Future<void> _persist(String? owner) async {
    final list = _saved.values.map((d) => d.toJson()).toList();
    final written = await _prefs?.setString(_userKey(owner), jsonEncode(list));
    if (written != true) throw StateError('Could not store saved deals.');
  }
}
