import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/promotion.dart';
import 'notification_service.dart';

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

  static Future<void> init() async {
    final svc = SavedDealsService();
    svc._prefs = await SharedPreferences.getInstance();
    final raw = svc._prefs!.getString(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          final deal = SavedDeal.fromJson(item as Map<String, dynamic>);
          svc._saved[deal.id] = deal;
        }
      } catch (_) {}
    }
  }

  bool isSaved(String id) => _saved.containsKey(id);
  SavedDeal? get(String id) => _saved[id];

  List<SavedDeal> get all {
    final list = _saved.values.toList();
    list.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return list;
  }

  Future<void> save(Promotion promo, {DateTime? remindAt}) async {
    _saved[promo.id] = SavedDeal(
      id: promo.id,
      brand: promo.brand,
      title: promo.title,
      endDate: promo.endDate,
      savedAt: DateTime.now(),
      remindAt: remindAt,
    );
    await _persist();
    notifyListeners();
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
  }

  Future<void> _persist() async {
    final list = _saved.values.map((d) => d.toJson()).toList();
    await _prefs?.setString(_key, jsonEncode(list));
  }
}
