import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_prefs.dart';
import '../services/auth_service.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import 'main_screen.dart';

// ── Limits ────────────────────────────────────────────────────────────────────

const _kMaxCats   = 3;
const _kMaxBrands = 7;

// ── Category definitions ──────────────────────────────────────────────────────

class _Cat {
  final String slug;
  final String emoji;
  final String title;
  final String subtitle;
  const _Cat(this.slug, this.emoji, this.title, this.subtitle);
}

const _kCategories = [
  _Cat('food',          '🍔', 'Food & Coffee',
      'Eating out, coffee runs, quick meals'),
  _Cat('grocery',       '🛒', 'Groceries & Essentials',
      'Groceries, pharmacy, household items'),
  _Cat('fashion',       '👕', 'Clothes & Shoes',
      'Fashion, shoes, activewear'),
  _Cat('luxury',        '👜', 'Bags, Jewelry & Accessible Luxury',
      'Coach, Kate Spade, Kendra Scott, etc.'),
  _Cat('beauty',        '💄', 'Beauty & Personal Care',
      'Makeup, skincare, fragrance, grooming'),
  _Cat('entertainment', '🎬', 'Entertainment',
      'Movies, bowling, events, streaming'),
  _Cat('home',          '🏠', 'Home',
      'Furniture, bedding, kitchen, decor'),
  _Cat('tech',          '💻', 'Tech',
      'Laptops, electronics, software'),
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

// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  /// When true, skip sign-up and start at category selection (editing prefs).
  final bool startAtPreferences;

  const OnboardingScreen({super.key, this.startAtPreferences = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageCtrl;

  bool    _isSignIn = false;
  bool    _loading  = false;
  String? _error;

  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _codeCtrl  = TextEditingController();
  bool  _obscure   = true;

  final _selectedCats   = <String>{};
  final _selectedBrands = <String>{};

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: widget.startAtPreferences ? 1 : 0);
    if (widget.startAtPreferences) {
      final prefs = UserPrefsService().prefs;
      if (prefs != null) {
        _selectedCats.addAll(prefs.favoriteCategories);
        _selectedBrands.addAll(prefs.favoriteBrands);
      }
    }
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
    try {
      await UserPrefsService().save(UserPrefs(
        favoriteCategories: _selectedCats.toList(),
        favoriteBrands:     _selectedBrands.toList(),
      ));
    } catch (_) {}
    if (!mounted) return;
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

  void _toggleBrand(String name) {
    setState(() {
      if (_selectedBrands.contains(name)) {
        _selectedBrands.remove(name);
      } else if (_selectedBrands.length < _kMaxBrands) {
        _selectedBrands.add(name);
      }
    });
  }

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
        ],
      ),
    );
  }

  // ── Page 0: Auth ──────────────────────────────────────────────────────────

  Widget _buildAuthPage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: Candy.raspberry,
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.local_offer, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Candy', style: TextStyle(fontSize: 32,
                  fontWeight: FontWeight.w800, letterSpacing: -1,
                  color: Candy.chocolate)),
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
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              _ErrorBox(message: _error!),
            ],
            const SizedBox(height: 24),
            _PrimaryButton(
                label: _isSignIn ? 'Sign In' : 'Join Beta',
                loading: _loading, onTap: _submit),
            const SizedBox(height: 18),
            Center(child: TextButton(
              onPressed: () => setState(() { _isSignIn = !_isSignIn; _error = null; }),
              child: Text(
                _isSignIn ? "Don't have an account? Join Beta"
                          : 'Already have an account? Sign In',
                style: const TextStyle(color: Candy.raspberry,
                    fontWeight: FontWeight.w500),
              ),
            )),
          ],
        ),
      ),
    );
  }

  // ── Page 1: Categories ────────────────────────────────────────────────────

  Widget _buildCategoriesPage() {
    final count = _selectedCats.length;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!widget.startAtPreferences) _StepDots(current: 0),
              if (!widget.startAtPreferences) const SizedBox(height: 20),
              Row(children: [
                const Expanded(
                  child: Text('What do you usually buy?',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                          color: Candy.chocolate, letterSpacing: -0.5)),
                ),
                if (widget.startAtPreferences)
                  IconButton(
                    icon: const Icon(Icons.close, color: Candy.chocolate),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(
                count == 0 ? 'Pick up to $_kMaxCats categories'
                           : '$count / $_kMaxCats selected',
                style: TextStyle(
                  fontSize: 13,
                  color: count == _kMaxCats ? Candy.raspberry : Colors.grey.shade500,
                  fontWeight: count == _kMaxCats ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: _kCategories.length,
              separatorBuilder: (context, i) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final cat      = _kCategories[i];
                final sel      = _selectedCats.contains(cat.slug);
                final disabled = !sel && count >= _kMaxCats;
                return _CatCard(
                  emoji: cat.emoji, title: cat.title, subtitle: cat.subtitle,
                  selected: sel, disabled: disabled,
                  onTap: disabled ? null : () => _toggleCat(cat.slug),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: _PrimaryButton(
              label: 'Continue →', loading: false,
              enabled: count > 0,
              onTap: count > 0 ? () => _goToPage(2) : null,
            ),
          ),
        ],
      ),
    );
  }

  // ── Page 2: Brands ────────────────────────────────────────────────────────

  Widget _buildBrandsPage() {
    final brands = _brandsForCategories(_selectedCats);
    final count  = _selectedBrands.length;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!widget.startAtPreferences) _StepDots(current: 1),
              if (!widget.startAtPreferences) const SizedBox(height: 20),
              Row(children: [
                GestureDetector(
                  onTap: () => _goToPage(1),
                  child: const Icon(Icons.arrow_back_ios_new,
                      size: 18, color: Candy.chocolate),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Pick your favorite brands',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                          color: Candy.chocolate, letterSpacing: -0.5)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                count == 0 ? 'Pick up to $_kMaxBrands brands'
                           : '$count / $_kMaxBrands selected',
                style: TextStyle(
                  fontSize: 13,
                  color: count == _kMaxBrands ? Candy.raspberry : Colors.grey.shade500,
                  fontWeight: count == _kMaxBrands ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
                          : Colors.grey.shade300,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      color: sel ? Candy.raspberry
                          : disabled ? Colors.grey.shade400 : Candy.chocolate,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                    ),
                    backgroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    showCheckmark: true,
                  );
                }).toList(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: _PrimaryButton(
              label: widget.startAtPreferences ? 'Save preferences'
                  : count == 0 ? 'Skip for now →' : 'Start discovering deals →',
              loading: _loading,
              onTap: _savePrefsAndFinish,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepDots extends StatelessWidget {
  final int current;
  const _StepDots({required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(children: List.generate(2, (i) {
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
  final String emoji;
  final String title;
  final String subtitle;
  final bool   selected;
  final bool   disabled;
  final VoidCallback? onTap;

  const _CatCard({
    required this.emoji, required this.title, required this.subtitle,
    required this.selected, required this.disabled, required this.onTap,
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
            width: selected ? 1.5 : 1,
          ),
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
              Text(subtitle, style: TextStyle(
                fontSize: 12,
                color: disabled ? Colors.grey.shade300 : Colors.grey.shade500,
              )),
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
    this.obscure        = false,
    this.suffix,
    this.inputType      = TextInputType.text,
    this.capitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: Candy.chocolate)),
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
