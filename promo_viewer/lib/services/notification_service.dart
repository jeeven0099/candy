import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'remote_data_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/user_prefs.dart';
import '../screens/deal_detail_screen.dart';
import 'interaction_service.dart';
import 'promotions_service.dart';
import 'user_prefs_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  static const _channelId   = 'candy_reminders';
  static const _channelName = 'Deal Reminders';

  // Rate-limit config
  static const _maxPerDay          = 2;
  static const _minGapHours        = 4;
  static const _quietStart         = 22; // 10 PM
  static const _quietEnd           = 8;  // 8 AM
  static const _brandCooldownDays  = 7;
  static const _dealCooldownDays   = 7;

  // Hard quality floor — never fire a notification for a weak deal,
  // even if it matches all personal preferences.
  static const _kMinGlobalQuality = 60.0;

  // Personalised threshold (at least one affinity signal fires): 95
  // Unknown brand/category (no signals): 105 — must be truly exceptional
  static const _kPersonalThreshold = 95.0;
  static const _kUnknownThreshold  = 105.0;

  // SharedPreferences keys
  static const _kNotifiedDeals      = 'notif_notified_deals_v1';
  static const _kNotifiedBrands     = 'notif_notified_brands_v1';
  static const _kSentToday          = 'notif_sent_today_v1';
  static const _kLastSentAt         = 'notif_last_sent_at_v1';
  static const _kNotifHistory       = 'notif_history_v1'; // capped at 50 entries

  FlutterLocalNotificationsPlugin? _plugin;

  static GlobalKey<NavigatorState>? _navigatorKey;

  // Holds a promoId when the app is launched cold from a notification tap.
  static String? pendingPromoId;
  static final tapNotifier = ValueNotifier<String?>(null);

  static Future<void> init({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (kIsWeb) return;
    _navigatorKey = navigatorKey;
    final svc = NotificationService();
    svc._plugin = FlutterLocalNotificationsPlugin();
    await svc._plugin!.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: false,
          requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: _handleTap,
    );
    final launchDetails = await svc._plugin!.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final id = launchDetails?.notificationResponse?.payload;
      if (id != null && id.isNotEmpty) {
        pendingPromoId = id;
      }
    }
    final androidPlugin = svc._plugin!
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Reminders for saved deals expiring soon.',
      importance: Importance.high,
    ));
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  static void _handleTap(NotificationResponse response) {
    final promoId = response.payload;
    if (promoId == null || promoId.isEmpty) return;
    final matches = PromotionsService.cached.where((p) => p.id == promoId);
    if (matches.isEmpty) {
      pendingPromoId = promoId;
      tapNotifier.value = promoId;
      return;
    }
    _navigatorKey?.currentState?.push(
      MaterialPageRoute(builder: (_) => DealDetailScreen(promo: matches.first)),
    );
  }

  // ---------------------------------------------------------------------------
  // Pipeline-driven notification candidates
  // ---------------------------------------------------------------------------

  /// Called once on app launch. Reads notification_candidates.json, re-scores
  /// each candidate against the user's actual preferences and interaction
  /// history, then sends the best qualifying deal (if any clears the bar).
  Future<void> processNotificationCandidates() async {
    if (kIsWeb) return;
    if (_inQuietHours()) return;

    final sharedPrefs = await SharedPreferences.getInstance();
    final todayCount  = _loadTodayCount(sharedPrefs);
    if (todayCount >= _maxPerDay) return;

    final lastSentStr = sharedPrefs.getString(_kLastSentAt);
    if (lastSentStr != null) {
      final last = DateTime.tryParse(lastSentStr);
      if (last != null &&
          DateTime.now().difference(last).inHours < _minGapHours) { return; }
    }

    final Map<String, dynamic> data;
    try {
      final raw = await RemoteDataService.load('notification_candidates.json');
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final rawCandidates = (data['candidates'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .toList() ?? [];
    if (rawCandidates.isEmpty) return;

    // User context for personalisation
    final userPrefs = UserPrefsService().prefs;
    final svc       = InteractionService();

    // Attach affinity signals and re-score, then sort best-first
    final scored = rawCandidates.map((c) {
      final signals = _affinitySignals(c, userPrefs, svc);
      final score   = _scoreFromSignals(
          (c['notify_score'] as num?)?.toDouble() ?? 0.0, signals);
      return (c: c, signals: signals, score: score);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final notifiedDeals  = _loadNotifiedDeals(sharedPrefs);
    final notifiedBrands = _loadNotifiedBrands(sharedPrefs);
    final now   = DateTime.now();
    final today = _dateKey(now);
    int sent    = 0;

    for (final entry in scored) {
      if (todayCount + sent >= _maxPerDay) break;

      final c        = entry.c;
      final globalQ  = (c['notify_score'] as num?)?.toDouble() ?? 0.0;
      final signals  = entry.signals;
      final pScore   = entry.score;

      // Hard quality floor — affinity cannot rescue a genuinely weak deal
      if (globalQ < _kMinGlobalQuality) continue;

      // Personalised deals get a lower bar; unknown brands need to be truly exceptional
      final threshold = signals.isNotEmpty ? _kPersonalThreshold : _kUnknownThreshold;
      if (pScore < threshold) continue;

      final promoId = c['promo_id'] as String? ?? '';
      final brand   = c['brand']   as String? ?? '';

      if (_isCooledDown(notifiedDeals,  promoId, _dealCooldownDays))  continue;
      if (_isCooledDown(notifiedBrands, brand,   _brandCooldownDays)) continue;

      final title  = c['notification_title'] as String? ?? brand;
      final body   = _personalBody(c, signals);
      final reason = signals.isNotEmpty ? body : 'exceptional deal';

      await _sendImmediate(
        id:      promoId.hashCode & 0x7FFFFFFF,
        title:   title,
        body:    body,
        payload: promoId,
        score:   pScore,
      );

      notifiedDeals[promoId] = today;
      notifiedBrands[brand]  = today;
      sent++;

      _appendHistory(sharedPrefs, {
        'brand':                brand,
        'category':             c['category'] ?? '',
        'promo_id':             promoId,
        'global_quality_score': globalQ,
        'personalized_score':   pScore,
        'trigger_signals':      signals,
        'reason':               reason,
        'fired_at':             now.toIso8601String(),
      });

      break; // one per launch — gap enforced on next open
    }

    if (sent > 0) {
      _saveNotifiedDeals(sharedPrefs, notifiedDeals);
      _saveNotifiedBrands(sharedPrefs, notifiedBrands);
      _saveTodayCount(sharedPrefs, todayCount + sent, today);
      await sharedPrefs.setString(_kLastSentAt, now.toIso8601String());
    }
  }

  /// Which personal affinity signals apply to this candidate.
  List<String> _affinitySignals(
    Map<String, dynamic> c,
    UserPrefs? prefs,
    InteractionService svc,
  ) {
    final signals  = <String>[];
    if (prefs == null) return signals;

    final brandRaw = (c['brand']    as String? ?? '').toLowerCase();
    final catRaw   = (c['category'] as String? ?? '').toLowerCase();

    final isFavBrand = prefs.favoriteBrands.any((b) {
      final bl = b.toLowerCase();
      return bl == brandRaw || brandRaw.contains(bl) || bl.contains(brandRaw);
    });
    if (isFavBrand) signals.add('favorite_brand');

    final isFavCat = catRaw.isNotEmpty &&
        prefs.favoriteCategories.any((cat) => cat.toLowerCase() == catRaw);
    if (isFavCat) signals.add('favorite_category');

    final interacted = PromotionsService.cached.any((p) =>
        p.brand.toLowerCase() == brandRaw &&
        (svc.clickCount(p.id) > 0 || svc.hasFastRedeemed(p.id)));
    if (interacted) signals.add('brand_interaction');

    return signals;
  }

  /// Base quality score + affinity bonuses.
  double _scoreFromSignals(double base, List<String> signals) {
    double s = base;
    if (signals.contains('favorite_brand'))    s += 40.0;
    if (signals.contains('favorite_category')) s += 25.0;
    if (signals.contains('brand_interaction')) s += 15.0;
    return s;
  }

  /// Notification body with personalised suffix based on active signals.
  String _personalBody(Map<String, dynamic> c, List<String> signals) {
    final base = c['notification_body'] as String? ?? c['title'] as String? ?? '';
    if (signals.contains('favorite_brand'))    return '$base — from a brand you love';
    if (signals.contains('favorite_category')) return '$base — in a category you follow';
    return base;
  }

  /// Appends a rich history entry (capped at 50) for later analysis.
  void _appendHistory(SharedPreferences prefs, Map<String, dynamic> entry) {
    final raw = prefs.getString(_kNotifHistory);
    List<dynamic> history = [];
    if (raw != null) {
      try { history = jsonDecode(raw) as List; } catch (_) {}
    }
    history.add(entry);
    if (history.length > 50) history = history.sublist(history.length - 50);
    prefs.setString(_kNotifHistory, jsonEncode(history));
  }

  // ---------------------------------------------------------------------------
  // Reminder scheduling (for saved deals expiring soon — existing feature)
  // ---------------------------------------------------------------------------

  Future<void> scheduleReminder({
    required String promoId,
    required String brand,
    required String title,
    required DateTime remindAt,
  }) async {
    if (kIsWeb) return;
    final when = tz.TZDateTime.from(remindAt, tz.local);
    if (when.isBefore(tz.TZDateTime.now(tz.local))) return;

    await _plugin?.zonedSchedule(
      id: _notifId(promoId),
      title: '$brand deal is expiring soon!',
      body: title,
      payload: promoId,
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelReminder(String promoId) async {
    if (kIsWeb) return;
    await _plugin?.cancel(id: _notifId(promoId));
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _sendImmediate({
    required int id,
    required String title,
    required String body,
    required String payload,
    required double score,
  }) async {
    await _plugin?.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          subtitle: 'Tap to see deal',
        ),
      ),
      payload: payload,
    );
  }

  bool _inQuietHours() {
    final h = DateTime.now().hour;
    return h >= _quietStart || h < _quietEnd;
  }

  bool _isCooledDown(Map<String, String> history, String key, int cooldownDays) {
    final ts = history[key];
    if (ts == null) return false;
    final d = DateTime.tryParse(ts);
    if (d == null) return false;
    return DateTime.now().difference(d).inDays < cooldownDays;
  }

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  // notifiedDeals: { promoId → "YYYY-MM-DD" }
  Map<String, String> _loadNotifiedDeals(SharedPreferences prefs) {
    final raw = prefs.getString(_kNotifiedDeals);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  void _saveNotifiedDeals(SharedPreferences prefs, Map<String, String> map) {
    // Prune entries older than cooldown period to keep storage small
    final cutoff = DateTime.now().subtract(const Duration(days: _dealCooldownDays));
    map.removeWhere((_, ts) {
      final d = DateTime.tryParse(ts);
      return d != null && d.isBefore(cutoff);
    });
    prefs.setString(_kNotifiedDeals, jsonEncode(map));
  }

  Map<String, String> _loadNotifiedBrands(SharedPreferences prefs) {
    final raw = prefs.getString(_kNotifiedBrands);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  void _saveNotifiedBrands(SharedPreferences prefs, Map<String, String> map) {
    final cutoff = DateTime.now().subtract(const Duration(days: _brandCooldownDays));
    map.removeWhere((_, ts) {
      final d = DateTime.tryParse(ts);
      return d != null && d.isBefore(cutoff);
    });
    prefs.setString(_kNotifiedBrands, jsonEncode(map));
  }

  int _loadTodayCount(SharedPreferences prefs) {
    final raw = prefs.getString(_kSentToday);
    if (raw == null) return 0;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final today = _dateKey(DateTime.now());
      if (map['date'] == today) return (map['count'] as num?)?.toInt() ?? 0;
    } catch (_) {}
    return 0;
  }

  void _saveTodayCount(SharedPreferences prefs, int count, String today) {
    prefs.setString(_kSentToday, jsonEncode({'date': today, 'count': count}));
  }

  static int _notifId(String id) => id.hashCode & 0x7FFFFFFF;
}
