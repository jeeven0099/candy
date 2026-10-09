import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'interaction_service.dart';
import 'push_token_service.dart';
import 'saved_deals_service.dart';
import 'supabase_service.dart';
import 'timezone_service.dart';
import 'user_prefs_service.dart';

class AppStartupService {
  static Future<void>? _initialization;
  static bool isReady = false;

  static Future<void> init() => _initialization ??= _initialize();

  static Future<void> _initialize() async {
    try {
      await TimezoneService.init();
      await SavedDealsService.init();
      await InteractionService.init();
      await SupabaseService.init();
      if (SupabaseService.isLoggedIn) {
        await UserPrefsService().load();
        final user = SupabaseService.currentUser;
        if (user != null) {
          await SavedDealsService().loadForUser(user.id);
          Sentry.configureScope(
            (scope) =>
                scope.setUser(SentryUser(id: user.id, email: user.email)),
          );
        }
        unawaited(PushTokenService.register());
      }
      isReady = true;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }
}
