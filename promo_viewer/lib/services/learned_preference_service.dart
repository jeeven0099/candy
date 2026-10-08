import 'package:flutter/foundation.dart';

import '../models/promotion.dart';
import '../models/user_prefs.dart';
import '../utils/catboost_preference_model.dart';
import '../utils/preference_features.dart';
import 'supabase_service.dart';
import 'user_memberships_service.dart';

class LearnedPreferenceService extends ChangeNotifier {
  static final _instance = LearnedPreferenceService._();
  factory LearnedPreferenceService() => _instance;
  LearnedPreferenceService._()
    : _currentAccount = (() => SupabaseService.currentUserId),
      _feedbackLoader = _fetchFeedback,
      _modelLoader = _fetchModel;

  @visibleForTesting
  LearnedPreferenceService.forTesting({
    required String? Function() currentAccount,
    required Future<List<Map<String, dynamic>>> Function(String) feedbackLoader,
    required Future<Map<String, dynamic>?> Function() modelLoader,
  }) : _currentAccount = currentAccount,
       _feedbackLoader = feedbackLoader,
       _modelLoader = modelLoader;

  final String? Function() _currentAccount;
  final Future<List<Map<String, dynamic>>> Function(String) _feedbackLoader;
  final Future<Map<String, dynamic>?> Function() _modelLoader;

  final _profile = PreferenceProfile();
  final List<Map<String, dynamic>> _localEvents = [];
  CatBoostPreferenceModel? _model;
  Set<String>? _memberships;
  String? _owner;
  int _loadGeneration = 0;

  String? get modelVersion =>
      _owner == _currentAccount() ? _model?.version : null;

  bool isDismissed(String id) =>
      _owner != null && _owner == _currentAccount() && _profile.isDismissed(id);

  void clear() {
    _loadGeneration++;
    _owner = null;
    _model = null;
    _memberships = null;
    _profile.clear();
    _localEvents.clear();
    notifyListeners();
  }

  void setMembershipContext(Set<String> memberships) =>
      _memberships = {...memberships};

  Map<String, double> features(
    Promotion p, {
    UserPrefs? prefs,
    bool? isMember,
  }) {
    if (_owner != _currentAccount()) {
      return PreferenceProfile().features(p, prefs: prefs, isMember: isMember);
    }
    final member =
        isMember ??
        (_memberships == null
            ? null
            : UserMembershipsService.hasMembership(
                _memberships!,
                p.brand,
                p.membershipName,
              ));
    return _profile.features(p, prefs: prefs, isMember: member);
  }

  double adjustment(Promotion p, {UserPrefs? prefs, bool? isMember}) {
    if (_owner == null || _owner != _currentAccount() || _model == null) {
      return 0;
    }
    return _model!.adjustment(features(p, prefs: prefs, isMember: isMember));
  }

  void record(Map<String, dynamic> event) {
    if (!const {
      'deal_saved',
      'deal_unsaved',
      'not_interested',
      'not_interested_undone',
    }.contains(event['event_type'])) {
      return;
    }
    final account = _currentAccount();
    if (account == null) return;
    if (_owner != account) {
      _loadGeneration++;
      _owner = account;
      _model = null;
      _memberships = null;
      _profile.clear();
      _localEvents.clear();
    }
    _localEvents.add(event);
    if (_localEvents.length > 1000) _localEvents.removeAt(0);
    _profile.apply(event);
    notifyListeners();
  }

  Future<void> loadForCurrentUser(String? userId) async {
    final account = _currentAccount();
    if (account == null || userId == null) {
      clear();
      return;
    }
    if (_owner != account) clear();
    _owner = account;
    final generation = ++_loadGeneration;
    try {
      final rows = await _feedbackLoader(
        userId,
      ).timeout(const Duration(seconds: 5));
      if (generation != _loadGeneration || account != _currentAccount()) {
        return;
      }
      final events = [
        ...rows.map((r) => Map<String, dynamic>.from(r)),
        ..._localEvents,
      ];
      int sequence(Map<String, dynamic> e) =>
          int.tryParse('${(e['metadata'] as Map?)?['event_sequence']}') ??
          DateTime.tryParse(
            e['created_at'] as String? ?? '',
          )?.microsecondsSinceEpoch ??
          0;
      events.sort((a, b) => sequence(a).compareTo(sequence(b)));
      _profile.clear();
      for (final event in events) {
        _profile.apply(event);
      }
    } catch (_) {
      // Feedback and model availability must never block the ordinary feed.
    }
    if (generation != _loadGeneration || account != _currentAccount()) return;
    try {
      final artifact = await _modelLoader().timeout(const Duration(seconds: 5));
      if (generation != _loadGeneration || account != _currentAccount()) {
        return;
      }
      _model = artifact == null
          ? null
          : CatBoostPreferenceModel.parse(artifact);
    } catch (_) {
      if (generation == _loadGeneration && account == _currentAccount()) {
        _model = null;
      }
    }
    if (generation == _loadGeneration && account == _currentAccount()) {
      notifyListeners();
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchFeedback(
    String userId,
  ) async {
    final rows = await SupabaseService.client
        .from('user_interactions')
        .select('promotion_id,event_type,brand,category,created_at,metadata')
        .eq('user_id', userId)
        .inFilter('event_type', [
          'deal_saved',
          'deal_unsaved',
          'not_interested',
          'not_interested_undone',
        ])
        .gte(
          'created_at',
          DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 90))
              .toIso8601String(),
        )
        .order('created_at', ascending: false)
        .limit(1000);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  static Future<Map<String, dynamic>?> _fetchModel() async {
    final row = await SupabaseService.client
        .from('learned_ranking_model')
        .select('artifact')
        .eq('id', 'beta')
        .maybeSingle();
    return row?['artifact'] is Map
        ? Map<String, dynamic>.from(row!['artifact'])
        : null;
  }
}
