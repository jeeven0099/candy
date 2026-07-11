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

// ── Demo data ─────────────────────────────────────────────────────────────────

class _DemoCard {
  final String brand;
  final String badge;
  final String logoDomain;
  const _DemoCard({required this.brand, required this.badge, required this.logoDomain});
}

const _kDemoCards = [
  _DemoCard(brand: 'Nike',   badge: '50% OFF',        logoDomain: 'nike.com'),
  _DemoCard(brand: 'Adidas', badge: r'$30 OFF',        logoDomain: 'adidas.com'),
  _DemoCard(brand: 'ASICS',  badge: 'Free Shipping',   logoDomain: 'asics.com'),
];

const _kTypedQuery  = 'running shoes';
const _kBrandCount  = 347;

// Animation timeline (ms in a 1 800 ms window)
//  0– 400  logo scale 0.95 → 1.00
//  700– 900  search bar fade in
//  1 000–1 300  query auto-types
//  1 300–1 500  card 1 slides up
//  1 400–1 600  card 2 slides up
//  1 500–1 700  card 3 slides up
//  1 900  navigate away (+ 100 ms buffer past end of animation)

const _kDur = 1800;

double _t(int ms) => ms / _kDur;

// ── Screen ────────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _searchFade;
  late final List<Animation<double>> _cardFade;
  late final List<Animation<double>> _cardSlide; // 0 → 1, maps to 24px → 0px

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kDur),
    );

    _logoScale = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: Interval(_t(0), _t(400), curve: Curves.easeOut)));

    _searchFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: Interval(_t(700), _t(900), curve: Curves.easeOut)));

    final starts = [_t(1300), _t(1400), _t(1500)];
    final ends   = [_t(1500), _t(1600), _t(1700)];
    _cardFade  = List.generate(3, (i) =>
        Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(parent: _ctrl,
                curve: Interval(starts[i], ends[i], curve: Curves.easeOut))));
    _cardSlide = List.generate(3, (i) =>
        Tween<double>(begin: 1.0, end: 0.0).animate(
            CurvedAnimation(parent: _ctrl,
                curve: Interval(starts[i], ends[i], curve: Curves.easeOut))));

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

    NotificationService().processNotificationCandidates();

    final remaining = 1900 - t.elapsedMilliseconds;
    if (remaining > 0) await Future.delayed(Duration(milliseconds: remaining));
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

  String get _typedText {
    const text = _kTypedQuery;
    final v = _ctrl.value;
    if (v <= _t(1000)) return '';
    if (v >= _t(1300)) return text;
    final progress = (v - _t(1000)) / (_t(1300) - _t(1000));
    return text.substring(0, (text.length * progress).round().clamp(0, text.length));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final typed = _typedText;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 5),

                  // ── Logo + wordmark ──────────────────────────────────────
                  Center(
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/Candy_logo.png',
                            width: 88,
                            height: 88,
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Candy',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: Candy.chocolate,
                              letterSpacing: -1.0,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Never pay full price',
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF9E9E9E),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Candy.mint,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Deals from $_kBrandCount brands',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFAAAAAA),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Search bar ───────────────────────────────────────────
                  Opacity(
                    opacity: _searchFade.value,
                    child: _FakeSearchBar(query: typed),
                  ),

                  const SizedBox(height: 16),

                  // ── Demo cards ───────────────────────────────────────────
                  for (int i = 0; i < _kDemoCards.length; i++) ...[
                    Opacity(
                      opacity: _cardFade[i].value,
                      child: Transform.translate(
                        offset: Offset(0, _cardSlide[i].value * 24),
                        child: _SplashDealCard(card: _kDemoCards[i]),
                      ),
                    ),
                    if (i < _kDemoCards.length - 1) const SizedBox(height: 10),
                  ],

                  const Spacer(flex: 3),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Fake search bar ───────────────────────────────────────────────────────────

class _FakeSearchBar extends StatelessWidget {
  final String query;
  const _FakeSearchBar({required this.query});

  @override
  Widget build(BuildContext context) {
    final isEmpty = query.isEmpty;
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEAEAEA), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search,
              size: 19,
              color: isEmpty ? const Color(0xFFCCCCCC) : const Color(0xFF999999)),
          const SizedBox(width: 10),
          Text(
            isEmpty ? 'Search brands or products…' : query,
            style: TextStyle(
              fontSize: 15,
              color: isEmpty ? const Color(0xFFCCCCCC) : Candy.chocolate,
              fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w500,
            ),
          ),
          if (!isEmpty) ...[
            // Blinking-style cursor (static; it moves as text grows)
            const SizedBox(width: 1),
            Container(width: 1.5, height: 17, color: Candy.raspberry),
          ],
        ],
      ),
    );
  }
}

// ── Demo deal card ────────────────────────────────────────────────────────────

class _SplashDealCard extends StatelessWidget {
  final _DemoCard card;
  const _SplashDealCard({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF2F2F2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              'https://icon.horse/icon/${card.logoDomain}',
              width: 36,
              height: 36,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.storefront_outlined,
                    size: 18, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 13),
          // Brand name
          Expanded(
            child: Text(
              card.brand,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Candy.chocolate,
              ),
            ),
          ),
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Candy.raspberry.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Candy.raspberry.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              card.badge,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Candy.raspberry,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
