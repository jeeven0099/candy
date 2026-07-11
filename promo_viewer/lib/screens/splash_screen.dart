import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../services/interaction_service.dart';
import '../services/notification_service.dart';
import '../services/saved_deals_service.dart';
import '../services/supabase_service.dart';
import '../services/timezone_service.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import 'main_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _scale = Tween<double>(begin: 0.80, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();
    _init();
  }

  Future<void> _init() async {
    final t = Stopwatch()..start();

    await TimezoneService.init();
    await SavedDealsService.init();
    await InteractionService.init();
    await SupabaseService.init();

    if (SupabaseService.isLoggedIn) {
      await UserPrefsService().load();
      final uid = SupabaseService.currentUserId;
      if (uid != null) await SavedDealsService().loadForUser(uid);
      _tagSentryUser();
    }

    // Fire-and-forget: process notification candidates after init.
    NotificationService().processNotificationCandidates();

    // Guarantee the logo is visible for at least 1.5 s.
    final remaining = 1500 - t.elapsedMilliseconds;
    if (remaining > 0) await Future.delayed(Duration(milliseconds: remaining));
    if (!mounted) return;

    await _ctrl.reverse();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => SupabaseService.isLoggedIn
            ? const MainScreen()
            : const OnboardingScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _tagSentryUser() {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    Sentry.configureScope(
      (scope) => scope.setUser(SentryUser(id: user.id, email: user.email)),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Candy.cream,
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => Opacity(
            opacity: _opacity.value,
            child: Transform.scale(scale: _scale.value, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/Candy_logo.png', width: 120, height: 120),
              const SizedBox(height: 16),
              const Text(
                'Candy',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Candy.chocolate,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
