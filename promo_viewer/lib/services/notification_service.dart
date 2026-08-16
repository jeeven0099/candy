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

// Top-level so it can execute in the background isolate when an action button
// is tapped while the app is terminated.
@pragma('vm:entry-point')
Future<void> _onBgNotifAction(NotificationResponse response) async {
  final payload  = response.payload;
  final actionId = response.actionId;
  if (payload == null || payload.isEmpty) return;
  if (actionId != 'interested' && actionId != 'not_interested') return;
  try {
    final m   = jsonDecode(payload) as Map<String, dynamic>;
    final id  = m['id']    as String? ?? '';
    final b   = m['brand'] as String? ?? '';
    final cat = m['cat']   as String? ?? '';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(NotificationService.kFeedbackKey);
    final fb  = raw != null
        ? (jsonDecode(raw) as Map<String, dynamic>)
        : <String, dynamic>{};
    fb[id] = {
      'brand': b, 'category': cat,
      'interested': actionId == 'interested',
      'ts': DateTime.now().toIso8601String(),
    };
    await prefs.setString(NotificationService.kFeedbackKey, jsonEncode(fb));
  } catch (_) {}
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  static const _channelId   = 'candy_reminders';
  static const _channelName = 'Deal Reminders';

  // Notification action/category IDs
  static const _kCategoryId = 'deal_candidate';
  static const _kInterested = 'interested';
  static const _kDismissed  = 'not_interested';

  // Rate-limit config
  static const _maxPerDay         = 2;
  static const _minGapHours       = 4;
  static const _quietStart        = 22; // 10 PM
  static const _quietEnd          = 8;  // 8 AM
  static const _brandCooldownDays = 7;
  static const _dealCooldownDays  = 7;

  static const _kMinGlobalQuality  = 60.0;
  static const _kPersonalThreshold = 95.0;
  static const _kUnknownThreshold  = 105.0;

  // SharedPreferences keys
  static const _kNotifiedDeals  = 'notif_notified_deals_v1';
  static const _kNotifiedBrands = 'notif_notified_brands_v1';
  static const _kSentToday      = 'notif_sent_today_v1';
  static const _kLastSentAt     = 'notif_last_sent_at_v1';
  static const _kNotifHistory   = 'notif_history_v1';
  // Accessed by the top-level background handler so must be public
  static const kFeedbackKey     = 'notif_feedback_v1';
  static const _kPendingPromoId = 'pending_notif_promo_id';

  FlutterLocalNotificationsPlugin? _plugin;

  static GlobalKey<NavigatorState>? _navigatorKey;

  static String? pendingPromoId;
  static final tapNotifier = ValueNotifier<String?>(null);

  /// Persists a notification promo_id to SharedPreferences so it survives
  /// app restarts and iOS memory termination.
  static Future<void> storePendingPromoId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingPromoId, id);
  }

  /// Reads and clears the persisted promo_id. Returns null if none stored.
  static Future<String?> consumePendingPromoId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kPendingPromoId);
    if (id != null) await prefs.remove(_kPendingPromoId);
    return id;
  }

  static Future<void> init({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (kIsWeb) return;
    _navigatorKey = navigatorKey;
    final svc = NotificationService();
    svc._plugin = FlutterLocalNotificationsPlugin();
    await svc._plugin!.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: false,
          requestSoundPermission: true,
          notificationCategories: [
            DarwinNotificationCategory(
              _kCategoryId,
              actions: [
                DarwinNotificationAction.plain(_kInterested, 'Interested'),
                DarwinNotificationAction.plain(
                  _kDismissed, 'Not Interested',
                  options: {DarwinNotificationActionOption.destructive},
                ),
              ],
              options: {DarwinNotificationCategoryOption.hiddenPreviewShowTitle},
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: _handleTap,
      onDidReceiveBackgroundNotificationResponse: _onBgNotifAction,
    );
    final launchDetails = await svc._plugin!.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        final id = _parsePayload(payload).id;
        pendingPromoId = id;
        await storePendingPromoId(id);
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

  // ---------------------------------------------------------------------------
  // Payload encoding — includes brand/category so action handlers are
  // self-contained even when running in the background isolate.
  // ---------------------------------------------------------------------------

  static String _makePayload(String id, String brand, String category) =>
      jsonEncode({'id': id, 'brand': brand, 'cat': category});

  static ({String id, String brand, String category}) _parsePayload(String payload) {
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      return (
        id:       m['id']    as String? ?? payload,
        brand:    m['brand'] as String? ?? '',
        category: m['cat']   as String? ?? '',
      );
    } catch (_) {
      // Legacy payloads are plain promoId strings
      return (id: payload, brand: '', category: '');
    }
  }

  // ---------------------------------------------------------------------------
  // Tap / action handling
  // ---------------------------------------------------------------------------

  static void _handleTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    final parsed  = _parsePayload(payload);
    final promoId = parsed.id;
    final actionId = response.actionId;

    if (actionId == _kInterested || actionId == _kDismissed) {
      _recordFeedback(
          promoId, parsed.brand, parsed.category, actionId == _kInterested);
      return;
    }

    // Always persist so MainScreen can navigate even if cached is empty now
    storePendingPromoId(promoId);

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

  static Future<void> _recordFeedback(
      String promoId, String brand, String category, bool interested) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(kFeedbackKey);
      final fb    = raw != null
          ? (jsonDecode(raw) as Map<String, dynamic>)
          : <String, dynamic>{};
      fb[promoId] = {
        'brand': brand, 'category': category,
        'interested': interested,
        'ts': DateTime.now().toIso8601String(),
      };
      // Prune entries older than 30 days
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      fb.removeWhere((_, v) {
        final ts = DateTime.tryParse((v as Map)['ts'] as String? ?? '');
        return ts != null && ts.isBefore(cutoff);
      });
      await prefs.setString(kFeedbackKey, jsonEncode(fb));
    } catch (_) {}

    // Fire-and-forget to Supabase via InteractionService
    InteractionService()
        .recordNotificationFeedback(promoId, brand, category, interested);
  }

  // ---------------------------------------------------------------------------
  // Pipeline-driven notification candidates
  // ---------------------------------------------------------------------------

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

    final userPrefs = UserPrefsService().prefs;
    final svc       = InteractionService();

    // Load stored notification feedback to factor into scoring
    final feedbackRaw = sharedPrefs.getString(kFeedbackKey);
    final feedback = feedbackRaw != null
        ? (jsonDecode(feedbackRaw) as Map<String, dynamic>)
        : <String, dynamic>{};

    final scored = rawCandidates.map((c) {
      final signals = _affinitySignals(c, userPrefs, svc, feedback);
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

      final c       = entry.c;
      final globalQ = (c['notify_score'] as num?)?.toDouble() ?? 0.0;
      final signals = entry.signals;
      final pScore  = entry.score;

      if (globalQ < _kMinGlobalQuality) continue;

      // Skip deals the user already said they're not interested in
      if (signals.contains('user_dismissed')) continue;

      final threshold = signals.isNotEmpty ? _kPersonalThreshold : _kUnknownThreshold;
      if (pScore < threshold) continue;

      final promoId  = c['promo_id']  as String? ?? '';
      final brand    = c['brand']     as String? ?? '';
      final category = c['category']  as String? ?? '';

      if (_isCooledDown(notifiedDeals,  promoId, _dealCooldownDays))  continue;
      if (_isCooledDown(notifiedBrands, brand,   _brandCooldownDays)) continue;

      final title  = c['notification_title'] as String? ?? brand;
      final body   = _personalBody(c, signals);
      final reason = signals.isNotEmpty ? body : 'exceptional deal';

      await _sendImmediate(
        id:       promoId.hashCode & 0x7FFFFFFF,
        title:    title,
        body:     body,
        promoId:  promoId,
        brand:    brand,
        category: category,
        score:    pScore,
      );

      notifiedDeals[promoId] = today;
      notifiedBrands[brand]  = today;
      sent++;

      _appendHistory(sharedPrefs, {
        'brand':                brand,
        'category':             category,
        'promo_id':             promoId,
        'global_quality_score': globalQ,
        'personalized_score':   pScore,
        'trigger_signals':      signals,
        'reason':               reason,
        'fired_at':             now.toIso8601String(),
      });

      break;
    }

    if (sent > 0) {
      _saveNotifiedDeals(sharedPrefs, notifiedDeals);
      _saveNotifiedBrands(sharedPrefs, notifiedBrands);
      _saveTodayCount(sharedPrefs, todayCount + sent, today);
      await sharedPrefs.setString(_kLastSentAt, now.toIso8601String());
    }
  }

  List<String> _affinitySignals(
    Map<String, dynamic> c,
    UserPrefs? prefs,
    InteractionService svc,
    Map<String, dynamic> feedback,
  ) {
    final signals  = <String>[];
    if (prefs == null) return signals;

    final brandRaw = (c['brand']    as String? ?? '').toLowerCase();
    final catRaw   = (c['category'] as String? ?? '').toLowerCase();

    final isFavBrand = prefs.favoriteBrands.any((b) => b.toLowerCase() == brandRaw);
    if (isFavBrand) signals.add('favorite_brand');

    final isFavCat = catRaw.isNotEmpty &&
        prefs.favoriteCategories.any((cat) => cat.toLowerCase() == catRaw);
    if (isFavCat) signals.add('favorite_category');

    final interacted = PromotionsService.cached.any((p) =>
        p.brand.toLowerCase() == brandRaw &&
        (svc.clickCount(p.id) > 0 || svc.hasFastRedeemed(p.id)));
    if (interacted) signals.add('brand_interaction');

    // Past notification feedback for this brand/category
    for (final v in feedback.values) {
      final f = v as Map<String, dynamic>;
      final fb   = (f['brand']    as String? ?? '').toLowerCase();
      final fc   = (f['category'] as String? ?? '').toLowerCase();
      final interested = f['interested'] as bool? ?? false;
      if (fb == brandRaw || fc == catRaw) {
        signals.add(interested ? 'user_interested' : 'user_dismissed');
        break;
      }
    }

    return signals;
  }

  double _scoreFromSignals(double base, List<String> signals) {
    double s = base;
    if (signals.contains('favorite_brand'))    s += 40.0;
    if (signals.contains('favorite_category')) s += 25.0;
    if (signals.contains('brand_interaction')) s += 15.0;
    if (signals.contains('user_interested'))   s += 35.0;
    if (signals.contains('user_dismissed'))    s -= 80.0; // pushed far below threshold
    return s;
  }

  String _personalBody(Map<String, dynamic> c, List<String> signals) {
    final base = c['notification_body'] as String? ?? c['title'] as String? ?? '';
    if (signals.contains('user_interested'))   return '$base — based on your feedback';
    if (signals.contains('favorite_brand'))    return '$base — from a brand you love';
    if (signals.contains('favorite_category')) return '$base — in a category you follow';
    return base;
  }

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
  // Reminder scheduling (for saved deals expiring soon)
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
      payload: _makePayload(promoId, brand, ''),
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
    required String promoId,
    required String brand,
    required String category,
    required double score,
  }) async {
    await _plugin?.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: const AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            AndroidNotificationAction('interested',   'Interested',    showsUserInterface: false),
            AndroidNotificationAction('not_interested', 'Not Interested', showsUserInterface: false, cancelNotification: true),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          subtitle: 'Tap to see deal',
          categoryIdentifier: _kCategoryId,
        ),
      ),
      payload: _makePayload(promoId, brand, category),
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

  Map<String, String> _loadNotifiedDeals(SharedPreferences prefs) {
    final raw = prefs.getString(_kNotifiedDeals);
    if (raw == null) return {};
    try { return Map<String, String>.from(jsonDecode(raw) as Map); }
    catch (_) { return {}; }
  }

  void _saveNotifiedDeals(SharedPreferences prefs, Map<String, String> map) {
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
    try { return Map<String, String>.from(jsonDecode(raw) as Map); }
    catch (_) { return {}; }
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