import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../models/user_prefs.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import 'main_screen.dart';

// ── Limits ────────────────────────────────────────────────────────────────────

const _kMaxCats   = 3;
const _kMaxBrands = 7;
const _kRadiusKey = 'near_me_radius_mi';

// ── Category definitions ──────────────────────────────────────────────────────

class _Cat {
  final String slug;
  final String emoji;
  final String title;
  final String subtitle;
  final List<String> examples;
  const _Cat(this.slug, this.emoji, this.title, this.subtitle, this.examples);
}

const _kCategories = [
  _Cat('food', '🍔', 'Food & Coffee',
      'Eating out, coffee runs, quick meals',
      ['Starbucks', 'Chipotle', "McDonald's", 'Dunkin']),
  _Cat('grocery', '🛒', 'Groceries & Essentials',
      'Groceries, pharmacy, household items',
      ['Kroger', 'H-E-B', 'Target', 'CVS']),
  _Cat('fashion', '👕', 'Clothes & Shoes',
      'Fashion, shoes, activewear',
      ['Nike', 'Old Navy', 'Zara', 'Steve Madden']),
  _Cat('luxury', '👜', 'Bags, Jewelry & Accessible Luxury',
      'Coach, Kate Spade, Kendra Scott, etc.',
      ['Coach', 'Kate Spade', 'Tory Burch', 'Michael Kors']),
  _Cat('beauty', '💄', 'Beauty & Personal Care',
      'Makeup, skincare, fragrance, grooming',
      ['Sephora', 'Ulta Beauty', 'e.l.f.', 'Fenty Beauty']),
  _Cat('entertainment', '🎬', 'Entertainment',
      'Movies, bowling, events, streaming',
      ['AMC Theatres', 'Topgolf', 'Dave & Buster\'s', 'Spotify']),
  _Cat('home', '🏠', 'Home',
      'Furniture, bedding, kitchen, decor',
      ['IKEA', 'Wayfair', 'Home Depot', 'West Elm']),
  _Cat('tech', '💻', 'Tech',
      'Laptops, electronics, software',
      ['Best Buy', 'Amazon', 'Apple', 'Dell']),
];

// ── Brands per category ───────────────────────────────────────────────────────

const _kBrandsByCategory = <String, List<String>>{
  'food': [
    'Starbucks', 'Dunkin', 'Chipotle', "McDonald's", 'Chick-fil-A',
    'Taco Bell', 'Wingstop', 'Panera Bread', "Domino's", 'Shake Shack',
  ],
  'grocery': [
    'Kroger', 'Whole Foods Market', 'Costco', 'Target', 'Walmart',
    'Aldi', 'Publix', "Trader Joe's", 'CVS', 'Walgreens',
  ],
  'fashion': [
    'Nike', 'H&M', 'Lululemon', 'Old Navy', 'Zara',
    'Uniqlo', 'American Eagle', 'Gap', 'Adidas', 'Steve Madden',
  ],
  'luxury': [
    'Coach', 'Kate Spade', 'Michael Kors', 'Tory Burch', 'Kendra Scott',
    'Tumi', 'Vera Bradley', 'Rebecca Minkoff', 'Ralph Lauren', 'Calvin Klein',
  ],
  'beauty': [
    'Ulta Beauty', 'Sephora', 'Bath & Body Works', 'e.l.f. Cosmetics',
    'ColourPop', 'Fenty Beauty', 'The Ordinary', 'NYX Professional Makeup',
    'Tarte Cosmetics', 'Clinique',
  ],
  'entertainment': [
    'AMC Theatres', 'Regal Cinemas', 'Main Event', "Dave & Buster's",
    'Topgolf', 'Bowlero', 'Spotify', 'Disney+', 'Hulu', 'Netflix',
  ],
  'home': [
    'IKEA', 'Home Depot', "Lowe's", 'Wayfair', 'Crate & Barrel',
    'West Elm', 'Pottery Barn', 'Target', 'Bed Bath & Beyond', 'Amazon',
  ],
  'tech': [
    'Amazon', 'Best Buy', 'Apple', 'Dell', 'Microsoft',
    'GameStop', 'B&H Photo', 'Adorama', 'Samsung', 'Newegg',
  ],
};

List<String> _brandsForCategories(Set<String> cats) {
  final seen   = <String>{};
  final result = <String>[];
  for (final cat in _kCategories.map((c) => c.slug)) {
    if (!cats.contains(cat)) continue;
    for (final b in _kBrandsByCategory[cat] ?? []) {
      if (seen.add(b)) result.add(b);
    }
  }
  return result;
}

// ── Deal type definitions ─────────────────────────────────────────────────────

class _DealType {
  final String slug;
  final String emoji;
  final String title;
  final String subtitle;
  const _DealType(this.slug, this.emoji, this.title, this.subtitle);
}

const _kDealTypes = [
  _DealType('free',     '🎁', 'Free items & birthday rewards',
      'Free food, birthday deals, loyalty freebies'),
  _DealType('bogo',     '🔥', 'BOGO deals',
      'Buy one get one free or 50% off'),
  _DealType('discount', '💸', 'Big discounts',
      '30% off or more, major sales'),
  _DealType('nearby',   '📍', 'Nearby deals',
      'Deals within your chosen radius'),
  _DealType('online',   '🛍', 'Online promo codes',
      'Discount codes usable from any device'),
  _DealType('rewards',  '🏷', 'Rewards & member deals',
      'Loyalty program and membership exclusives'),
];

// ── Radius options ────────────────────────────────────────────────────────────

class _Radius {
  final int    miles;
  final String label;
  final String subtitle;
  const _Radius(this.miles, this.label, this.subtitle);
}

const _kRadii = [
  _Radius(1,  '1 mile',   'Walking distance'),
  _Radius(3,  '3 miles',  'Short drive'),
  _Radius(5,  '5 miles',  'Good for most cities'),
  _Radius(10, '10 miles', 'Wider area, great for Houston'),
  _Radius(25, '25 miles', 'Large metro or suburb'),
];

// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  /// When true, skip sign-up and start at category selection (editing prefs).
  final bool startAtPreferences;

  const OnboardingScreen({super.key, this.startAtPreferences = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // Page 0: Auth  1: Categories  2: Brands  3: Deal types  4: Radius
  late final PageController _pageCtrl;

  bool    _isSignIn = false;
  bool    _loading  = false;
  String? _error;

  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _codeCtrl  = TextEditingController();
  bool  _obscure   = true;

  final _selectedCats      = <String>{};
  final _selectedBrands    = <String>{};
  final _selectedDealTypes = <String>{};
  int   _radiusMi          = 5;
  int?  _birthdayMonth;
  int?  _birthdayDay;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: widget.startAtPreferences ? 1 : 0);
    if (widget.startAtPreferences) {
      final prefs = UserPrefsService().prefs;
      if (prefs != null) {
        _selectedCats.addAll(prefs.favoriteCategories);
        _selectedBrands.addAll(prefs.favoriteBrands);
        _selectedDealTypes.addAll(prefs.dealPriorities);
        _birthdayMonth = prefs.birthdayMonth;
        _birthdayDay   = prefs.birthdayDay;
      }
      _loadRadius();
    }
  }

  Future<void> _loadRadius() async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getInt(_kRadiusKey);
    if (saved != null && mounted) setState(() => _radiusMi = saved);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _goToPage(int p) {
    setState(() => _error = null);
    _pageCtrl.animateToPage(p,
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (!_isSignIn && _codeCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your invite code.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (_isSignIn) {
        await AuthService.signIn(email: email, password: pass);
        await UserPrefsService().load();
        if (mounted) _launchApp();
      } else {
        await AuthService.signUp(
            email: email, password: pass, inviteCode: _codeCtrl.text);
        if (mounted) _goToPage(1);
      }
    } on AuthException catch (e) {
      setState(() => _error = AuthService.friendlyError(e));
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePrefsAndFinish() async {
    setState(() { _loading = true; _error = null; });

    // Save radius to SharedPreferences (non-fatal)
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kRadiusKey, _radiusMi);
    } catch (_) {}

    // Save category/brand/deal prefs to Supabase — show error if it fails
    try {
      await UserPrefsService().save(UserPrefs(
        favoriteCategories: _selectedCats.toList(),
        favoriteBrands:     _selectedBrands.toList(),
        dealPriorities:     _selectedDealTypes.toList(),
        birthdayMonth:      _birthdayMonth,
        birthdayDay:        _birthdayDay,
      ));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not save your preferences. Please check your connection and try again.';
        });
      }
      return;
    }

    // Mark onboarding complete (best-effort, non-fatal)
    if (!widget.startAtPreferences) {
      try {
        final authId = SupabaseService.currentUserId;
        if (authId != null) {
          await SupabaseService.client.from('users').update({
            'onboarding_completed':    true,
            'onboarding_completed_at': DateTime.now().toIso8601String(),
          }).eq('auth_id', authId);
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _loading = false);
    if (widget.startAtPreferences) {
      Navigator.of(context).pop();
    } else {
      _launchApp();
    }
  }

  void _launchApp() => Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()), (_) => false);

  void _toggleCat(String slug) {
    setState(() {
      if (_selectedCats.contains(slug)) {
        _selectedCats.remove(slug);
        final stillValid = _brandsForCategories(_selectedCats).toSet();
        _selectedBrands.removeWhere((b) => !stillValid.contains(b));
      } else if (_selectedCats.length < _kMaxCats) {
        _selectedCats.add(slug);
      }
    });
  }

  void _toggleBrand(String name) => setState(() {
    if (_selectedBrands.contains(name)) {
      _selectedBrands.remove(name);
    } else if (_selectedBrands.length < _kMaxBrands) {
      _selectedBrands.add(name);
    }
  });

  void _toggleDeal(String slug) => setState(() {
    if (_selectedDealTypes.contains(slug)) {
      _selectedDealTypes.remove(slug);
    } else {
      _selectedDealTypes.add(slug);
    }
  });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Candy.cream,
      body: PageView(
        controller: _pageCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildAuthPage(),
          _buildCategoriesPage(),
          _buildBrandsPage(),
          _buildDealTypesPage(),
          _buildRadiusPage(),
        ],
      ),
    );
  }

  // ── Page 0: Auth ──────────────────────────────────────────────────────────

  Widget _buildAuthPage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: Candy.raspberry,
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.local_offer, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Candy', style: TextStyle(fontSize: 32,
                fontWeight: FontWeight.w800, letterSpacing: -1, color: Candy.chocolate)),
          ]),
          const SizedBox(height: 32),
          Text(_isSignIn ? 'Welcome back' : 'Join the beta',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700,
                  color: Candy.chocolate, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text(
            _isSignIn ? 'Sign in to your Candy account'
                      : 'Discover the best deals around you',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 28),
          _Field(controller: _emailCtrl, label: 'Email',
              hint: 'you@example.com', inputType: TextInputType.emailAddress),
          const SizedBox(height: 14),
          _Field(
            controller: _passCtrl, label: 'Password', hint: '6+ characters',
            obscure: _obscure,
            suffix: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                  size: 20, color: Colors.grey),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          if (!_isSignIn) ...[
            const SizedBox(height: 14),
            _Field(controller: _codeCtrl, label: 'Invite code',
                hint: 'e.g. CANDY2025',
                capitalization: TextCapitalization.characters),
            const SizedBox(height: 14),
            _birthdayPicker(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            _ErrorBox(message: _error!),
          ],
          const SizedBox(height: 24),
          _PrimaryButton(label: _isSignIn ? 'Sign In' : 'Join Beta',
              loading: _loading, onTap: _submit),
          const SizedBox(height: 18),
          Center(child: TextButton(
            onPressed: () => setState(() { _isSignIn = !_isSignIn; _error = null; }),
            child: Text(
              _isSignIn ? "Don't have an account? Join Beta"
                        : 'Already have an account? Sign In',
              style: const TextStyle(color: Candy.raspberry, fontWeight: FontWeight.w500),
            ),
          )),
        ]),
      ),
    );
  }

  static const _kMonths = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];

  Widget _birthdayPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Birthday (optional)',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Candy.chocolate),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _BirthdayDropdown<int>(
                hint: 'Month',
                value: _birthdayMonth,
                items: List.generate(12, (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text(_kMonths[i], style: const TextStyle(fontSize: 14)),
                )),
                onChanged: (v) => setState(() => _birthdayMonth = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _BirthdayDropdown<int>(
                hint: 'Day',
                value: _birthdayDay,
                items: List.generate(31, (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 14)),
                )),
                onChanged: (v) => setState(() => _birthdayDay = v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Page 1: Categories ────────────────────────────────────────────────────

  Widget _buildCategoriesPage() {
    final count = _selectedCats.length;
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PageHeader(
          step: 1, totalSteps: 4,
          showDots: !widget.startAtPreferences,
          title: 'Make Candy yours',
          subtitle: 'Pick what you usually buy. Candy will show better deals first.\nYou can change this anytime.',
          trailing: widget.startAtPreferences
              ? IconButton(icon: const Icon(Icons.close, color: Candy.chocolate),
                  onPressed: () => Navigator.of(context).pop())
              : const SizedBox.shrink(),
          badge: count == 0 ? 'Pick up to $_kMaxCats'
              : '$count / $_kMaxCats selected',
          badgeHighlight: count == _kMaxCats,
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            itemCount: _kCategories.length,
            separatorBuilder: (context, i) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final cat      = _kCategories[i];
              final sel      = _selectedCats.contains(cat.slug);
              final disabled = !sel && count >= _kMaxCats;
              return _CatCard(
                emoji: cat.emoji, title: cat.title,
                subtitle: cat.subtitle, examples: cat.examples,
                selected: sel, disabled: disabled,
                onTap: disabled ? null : () => _toggleCat(cat.slug),
              );
            },
          ),
        ),
        _BottomActions(
          primaryLabel: 'Continue →',
          primaryEnabled: count > 0,
          onPrimary: count > 0 ? () => _goToPage(2) : null,
          onSkip: () => _goToPage(2),
          loading: false,
        ),
      ]),
    );
  }

  // ── Page 2: Brands ────────────────────────────────────────────────────────

  Widget _buildBrandsPage() {
    final brands = _brandsForCategories(_selectedCats);
    final count  = _selectedBrands.length;
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PageHeader(
          step: 2, totalSteps: 4,
          showDots: !widget.startAtPreferences,
          backOnTap: () => _goToPage(1),
          title: 'Which brands do you care about?',
          subtitle: 'Pick brands you actually shop from, or would buy from if there was a good deal.',
          badge: count == 0 ? 'Pick up to $_kMaxBrands'
              : '$count / $_kMaxBrands selected',
          badgeHighlight: count == _kMaxBrands,
        ),
        Expanded(
          child: brands.isEmpty
              ? Center(child: Text('Select categories first to see brands here.',
                  style: TextStyle(color: Colors.grey.shade500)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Wrap(
                    spacing: 8, runSpacing: 8,
                    children: brands.map((b) {
                      final sel      = _selectedBrands.contains(b);
                      final disabled = !sel && count >= _kMaxBrands;
                      return FilterChip(
                        label: Text(b),
                        selected: sel,
                        onSelected: disabled ? null : (_) => _toggleBrand(b),
                        selectedColor: Candy.raspberry.withValues(alpha: 0.12),
                        disabledColor: Colors.grey.shade100,
                        checkmarkColor: Candy.raspberry,
                        side: BorderSide(
                          color: sel ? Candy.raspberry
                              : disabled ? Colors.grey.shade200
                              : Colors.grey.shade300),
                        labelStyle: TextStyle(fontSize: 13,
                          color: sel ? Candy.raspberry
                              : disabled ? Colors.grey.shade400 : Candy.chocolate,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.normal),
                        backgroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        showCheckmark: true,
                      );
                    }).toList(),
                  ),
                ),
        ),
        _BottomActions(
          primaryLabel: 'Continue →',
          primaryEnabled: true,
          onPrimary: () => _goToPage(3),
          onSkip: () => _goToPage(3),
          loading: false,
        ),
      ]),
    );
  }

  // ── Page 3: Deal types ────────────────────────────────────────────────────

  Widget _buildDealTypesPage() {
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PageHeader(
          step: 3, totalSteps: 4,
          showDots: !widget.startAtPreferences,
          backOnTap: () => _goToPage(2),
          title: 'What kind of deals should Candy prioritize?',
          subtitle: 'Select all that apply. This directly improves your ranking.',
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            itemCount: _kDealTypes.length,
            separatorBuilder: (context, i) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final dt  = _kDealTypes[i];
              final sel = _selectedDealTypes.contains(dt.slug);
              return _SimpleCard(
                emoji: dt.emoji, title: dt.title, subtitle: dt.subtitle,
                selected: sel, onTap: () => _toggleDeal(dt.slug),
              );
            },
          ),
        ),
        _BottomActions(
          primaryLabel: 'Continue →',
          primaryEnabled: true,
          onPrimary: () => _goToPage(4),
          onSkip: () => _goToPage(4),
          loading: false,
        ),
      ]),
    );
  }

  // ── Page 4: Radius ────────────────────────────────────────────────────────

  Widget _buildRadiusPage() {
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _PageHeader(
          step: 4, totalSteps: 4,
          showDots: !widget.startAtPreferences,
          backOnTap: () => _goToPage(3),
          title: 'How far should Candy look?',
          subtitle: 'Set the distance for nearby deals. You can always change this in Profile.',
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            itemCount: _kRadii.length,
            separatorBuilder: (context, i) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r   = _kRadii[i];
              final sel = r.miles == _radiusMi;
              return _SimpleCard(
                emoji: '📍',
                title: r.label,
                subtitle: r.label == '5 miles'
                    ? '${r.subtitle} (default)' : r.subtitle,
                selected: sel,
                onTap: () => setState(() => _radiusMi = r.miles),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _PrimaryButton(
            label: widget.startAtPreferences ? 'Save preferences'
                : 'Start discovering deals →',
            loading: _loading,
            onTap: _savePrefsAndFinish,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared layout components
// ─────────────────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final int     step;
  final int     totalSteps;
  final bool    showDots;
  final String  title;
  final String  subtitle;
  final String? badge;
  final bool    badgeHighlight;
  final VoidCallback? backOnTap;
  final Widget trailing;

  const _PageHeader({
    required this.step, required this.totalSteps, required this.showDots,
    required this.title, required this.subtitle,
    this.badge, this.badgeHighlight = false,
    this.backOnTap, this.trailing = const SizedBox.shrink(),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showDots) ...[
          _StepDots(current: step - 1, total: totalSteps),
          const SizedBox(height: 20),
        ],
        Row(children: [
          if (backOnTap != null) ...[
            GestureDetector(
              onTap: backOnTap,
              child: const Icon(Icons.arrow_back_ios_new,
                  size: 18, color: Candy.chocolate),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                  color: Candy.chocolate, letterSpacing: -0.5))),
          trailing,
        ]),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        if (badge != null) ...[
          const SizedBox(height: 6),
          Text(badge!,
            style: TextStyle(
              fontSize: 12,
              color: badgeHighlight ? Candy.raspberry : Colors.grey.shade400,
              fontWeight: badgeHighlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ]),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final String       primaryLabel;
  final bool         primaryEnabled;
  final bool         loading;
  final VoidCallback? onPrimary;
  final VoidCallback? onSkip;

  const _BottomActions({
    required this.primaryLabel, required this.primaryEnabled,
    required this.loading, this.onPrimary, this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(children: [
        _PrimaryButton(label: primaryLabel, loading: loading,
            enabled: primaryEnabled, onTap: onPrimary),
        if (onSkip != null) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: onSkip,
            child: Text('Skip for now',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          ),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepDots extends StatelessWidget {
  final int current;
  final int total;
  const _StepDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(children: List.generate(total, (i) {
      final active = i == current;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 6),
        width: active ? 24 : 8, height: 8,
        decoration: BoxDecoration(
          color: active ? Candy.raspberry : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }));
  }
}

class _CatCard extends StatelessWidget {
  final String       emoji;
  final String       title;
  final String       subtitle;
  final List<String> examples;
  final bool         selected;
  final bool         disabled;
  final VoidCallback? onTap;

  const _CatCard({
    required this.emoji, required this.title, required this.subtitle,
    required this.examples, required this.selected, required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? Candy.raspberry.withValues(alpha: 0.08)
              : disabled ? Colors.grey.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? Candy.raspberry : Colors.grey.shade200,
              width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600,
                color: disabled ? Colors.grey.shade400 : Candy.chocolate,
              )),
              const SizedBox(height: 2),
              Text(examples.join(', '),
                style: TextStyle(fontSize: 12,
                  color: disabled ? Colors.grey.shade300 : Colors.grey.shade500)),
            ],
          )),
          if (selected)
            const Icon(Icons.check_circle, color: Candy.raspberry, size: 20)
          else
            Icon(Icons.circle_outlined,
                color: disabled ? Colors.grey.shade200 : Colors.grey.shade300,
                size: 20),
        ]),
      ),
    );
  }
}

class _SimpleCard extends StatelessWidget {
  final String       emoji;
  final String       title;
  final String       subtitle;
  final bool         selected;
  final VoidCallback onTap;

  const _SimpleCard({
    required this.emoji, required this.title, required this.subtitle,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? Candy.raspberry.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? Candy.raspberry : Colors.grey.shade200,
              width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600,
                color: selected ? Candy.raspberry : Candy.chocolate,
              )),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          )),
          if (selected)
            const Icon(Icons.check_circle, color: Candy.raspberry, size: 20)
          else
            Icon(Icons.circle_outlined, color: Colors.grey.shade300, size: 20),
        ]),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String       label;
  final bool         loading;
  final bool         enabled;
  final VoidCallback? onTap;

  const _PrimaryButton({
    required this.label, required this.loading,
    this.enabled = true, this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        onPressed: (!enabled || loading) ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Candy.raspberry,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade200,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _BirthdayDropdown<T> extends StatelessWidget {
  final String hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _BirthdayDropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      hint: Text(hint, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Candy.raspberry, width: 1.5)),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, size: 16, color: Colors.red.shade600),
        const SizedBox(width: 8),
        Expanded(child: Text(message,
            style: TextStyle(fontSize: 13, color: Colors.red.shade700))),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool   obscure;
  final Widget? suffix;
  final TextInputType      inputType;
  final TextCapitalization capitalization;

  const _Field({
    required this.controller, required this.label, required this.hint,
    this.obscure = false, this.suffix,
    this.inputType = TextInputType.text,
    this.capitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13,
          fontWeight: FontWeight.w600, color: Candy.chocolate)),
      const SizedBox(height: 6),
      TextField(
        controller: controller, obscureText: obscure,
        keyboardType: inputType, textCapitalization: capitalization,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          suffixIcon: suffix,
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Candy.raspberry, width: 1.5)),
        ),
      ),
    ]);
  }
}
