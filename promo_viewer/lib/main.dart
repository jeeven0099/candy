import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'screens/main_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/interaction_service.dart';
import 'services/notification_service.dart';
import 'services/saved_deals_service.dart';
import 'services/supabase_service.dart';
import 'services/timezone_service.dart';
import 'services/user_prefs_service.dart';
import 'theme/candy_colors.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://c51b5b12b038586731b61a2de7c26a6b@o4511633696620544.ingest.us.sentry.io/4511633700683776';
      options.tracesSampleRate = 0.2;
    },
    appRunner: () async {
      WidgetsFlutterBinding.ensureInitialized();
      await TimezoneService.init();
      await NotificationService.init(navigatorKey: navigatorKey);
      await SavedDealsService.init();
      await InteractionService.init();
      await SupabaseService.init();
      if (SupabaseService.isLoggedIn) {
        await UserPrefsService().load();
        final uid = SupabaseService.currentUserId;
        if (uid != null) await SavedDealsService().loadForUser(uid);
        _tagSentryUser();
      }
      // Fire-and-forget: process pipeline notification candidates on every launch.
      // Rate limits and quiet hours are enforced inside the method.
      NotificationService().processNotificationCandidates();
      runApp(const PromoViewerApp());
    },
  );
}

void _tagSentryUser() {
  final user = SupabaseService.currentUser;
  if (user == null) return;
  Sentry.configureScope((scope) => scope.setUser(SentryUser(id: user.id, email: user.email)));
}

class PromoViewerApp extends StatelessWidget {
  const PromoViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Candy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Candy.raspberry,
          brightness: Brightness.light,
        ).copyWith(surface: Candy.cream),
        useMaterial3: true,
        scaffoldBackgroundColor: Candy.cream,
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          indicatorColor: Candy.raspberry.withValues(alpha: 0.12),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Candy.raspberry);
            }
            return IconThemeData(color: Candy.chocolate.withValues(alpha: 0.45));
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: Candy.raspberry, fontWeight: FontWeight.w600, fontSize: 12);
            }
            return TextStyle(
              color: Candy.chocolate.withValues(alpha: 0.45), fontSize: 12);
          }),
        ),
      ),
      home: SupabaseService.isLoggedIn ? const MainScreen() : const OnboardingScreen(),
    );
  }
}
