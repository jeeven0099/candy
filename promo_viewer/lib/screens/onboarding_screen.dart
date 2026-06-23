import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_prefs.dart';
import '../services/auth_service.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import 'main_screen.dart';

// ── Category definitions ──────────────────────────────────────────────────────

class _Cat {
  final String slug;
  final String label;
  final IconData icon;
  const _Cat(this.slug, this.label, this.icon);
}

const _kCategories = [
  _Cat('food',          'Food & Coffee',  Icons.coffee),
  _Cat('grocery',       'Grocery',        Icons.local_grocery_store),
  _Cat('fashion',       'Fashion',        Icons.checkroom),
  _Cat('beauty',        'Beauty',         Icons.face_retouching_natural),
  _Cat('tech',          'Tech',           Icons.devices),
  _Cat('home',          'Home',           Icons.home),
  _Cat('entertainment', 'Entertainment',  Icons.movie),
  _Cat('travel',        'Travel',         Icons.flight),
  _Cat('pets',          'Pets',           Icons.pets),
  _Cat('auto',          'Auto & Gas',     Icons.local_gas_station),
];

// ── Brand definitions (slug, display name, category slugs) ───────────────────

class _Brand {
  final String name;
  final List<String> cats;
  const _Brand(this.name, this.cats);
}

const _kBrands = [
  _Brand('Starbucks',           ['food']),
  _Brand('Chipotle',            ['food']),
  _Brand("McDonald's",          ['food']),
  _Brand('Dunkin',              ['food']),
  _Brand('Taco Bell',           ['food']),
  _Brand('Panera Bread',        ['food']),
  _Brand('Chick-fil-A',         ['food']),
  _Brand("Domino's",            ['food']),
  _Brand('Subway',              ['food']),
  _Brand('Shake Shack',         ['food']),
  _Brand('Kroger',              ['grocery']),
  _Brand('Whole Foods Market',  ['grocery']),
  _Brand('Costco',              ['grocery']),
  _Brand('Target',              ['grocery']),
  _Brand('Walmart',             ['grocery']),
  _Brand('Aldi',                ['grocery']),
  _Brand('Publix',              ['grocery']),
  _Brand("Trader Joe's",        ['grocery']),
  _Brand('Nike',                ['fashion']),
  _Brand('H&M',                 ['fashion']),
  _Brand('Lululemon',           ['fashion']),
  _Brand('Old Navy',            ['fashion']),
  _Brand('Zara',                ['fashion']),
  _Brand('Uniqlo',              ['fashion']),
  _Brand('American Eagle',      ['fashion']),
  _Brand('Coach',               ['fashion']),
  _Brand('Michael Kors',        ['fashion']),
  _Brand('Ulta Beauty',         ['beauty']),
  _Brand('Sephora',             ['beauty']),
  _Brand('Bath & Body Works',   ['beauty']),
  _Brand('e.l.f. Cosmetics',    ['beauty']),
  _Brand('ColourPop',           ['beauty']),
  _Brand('Amazon',              ['tech']),
  _Brand('Best Buy',            ['tech']),
  _Brand('GameStop',            ['tech']),
  _Brand('Dell',                ['tech']),
  _Brand('IKEA',                ['home']),
  _Brand('Home Depot',          ['home']),
  _Brand("Lowe's",              ['home']),
  _Brand('Wayfair',             ['home']),
  _Brand('AMC Theatres',        ['entertainment']),
  _Brand('Spotify',             ['entertainment']),
  _Brand('Disney+',             ['entertainment']),
  _Brand('Hulu',                ['entertainment']),
  _Brand('Southwest Airlines',  ['travel']),
  _Brand('Marriott',            ['travel']),
  _Brand('Delta Air Lines',     ['travel']),
  _Brand('Hilton',              ['travel']),
  _Brand('Petco',               ['pets']),
  _Brand('PetSmart',            ['pets']),
  _Brand('Shell',               ['auto']),
  _Brand('Exxon Mobil',         ['auto']),
];

// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl    = PageController();
  bool _isSignIn     = false;
  bool _loading      = false;
  String? _error;

  // Auth fields
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _codeCtrl   = TextEditingController();
  bool _obscure      = true;

  // Preferences
  final _selectedCats   = <String>{};
  final _selectedBrands = <String>{};

  @override
  void dispose() {
    _pageCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _goToPage(int p) {
    setState(() { _error = null; });
    _pageCtrl.animateToPage(p,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut);
  }

  // ── Auth actions ──────────────────────────────────────────────────────────

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
        // Load existing prefs
        await UserPrefsService().load();
        if (mounted) _launchApp();
      } else {
        await AuthService.signUp(
          email: email, password: pass,
          inviteCode: _codeCtrl.text,
        );
        // New user → go to category step
        if (mounted) _goToPage(1);
      }
    } on AuthException catch (e) {
      setState(() => _error = AuthService.friendlyError(e));
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePrefsAndLaunch() async {
    setState(() { _loading = true; _error = null; });
    try {
      await UserPrefsService().save(UserPrefs(
        favoriteCategories: _selectedCats.toList(),
        favoriteBrands:     _selectedBrands.toList(),
      ));
    } catch (_) {}
    if (mounted) _launchApp();
  }

  void _launchApp() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()),
      (_) => false,
    );
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

  // ── Page 1: Auth ──────────────────────────────────────────────────────────

  Widget _buildAuthPage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo / wordmark
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Candy.raspberry,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_offer, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Text('Candy', style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.w800,
                  letterSpacing: -1, color: Candy.chocolate,
                )),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              _isSignIn ? 'Welcome back' : 'Join the beta',
              style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w700,
                color: Candy.chocolate, letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isSignIn
                  ? 'Sign in to your Candy account'
                  : 'Discover the best deals around you',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 28),

            // Fields
            _Field(controller: _emailCtrl, label: 'Email',
                hint: 'you@example.com', inputType: TextInputType.emailAddress),
            const SizedBox(height: 14),
            _Field(
              controller: _passCtrl, label: 'Password',
              hint: '6+ characters',
              obscure: _obscure,
              suffix: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    size: 20, color: Colors.grey),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            if (!_isSignIn) ...[
              const SizedBox(height: 14),
              _Field(
                controller: _codeCtrl, label: 'Invite code',
                hint: 'e.g. CANDY2025',
                inputType: TextInputType.text,
                capitalization: TextCapitalization.characters,
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.error_outline, size: 16, color: Colors.red.shade600),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!,
                      style: TextStyle(fontSize: 13, color: Colors.red.shade700))),
                ]),
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Candy.raspberry,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        _isSignIn ? 'Sign In' : 'Join Beta',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),

            const SizedBox(height: 18),
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  _isSignIn = !_isSignIn;
                  _error = null;
                }),
                child: Text(
                  _isSignIn
                      ? "Don't have an account? Join Beta"
                      : 'Already have an account? Sign In',
                  style: const TextStyle(
                      color: Candy.raspberry, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Page 2: Categories ────────────────────────────────────────────────────

  Widget _buildCategoriesPage() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StepDots(current: 0),
            const SizedBox(height: 24),
            const Text('What do you usually shop for?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                    color: Candy.chocolate, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text("Select all that apply — we'll show your best deals first",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 20),

            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12,
                  childAspectRatio: 2.8,
                ),
                itemCount: _kCategories.length,
                itemBuilder: (_, i) {
                  final cat = _kCategories[i];
                  final sel = _selectedCats.contains(cat.slug);
                  return _SelectChip(
                    icon: cat.icon, label: cat.label, selected: sel,
                    onTap: () => setState(() {
                      sel ? _selectedCats.remove(cat.slug) : _selectedCats.add(cat.slug);
                    }),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _selectedCats.isEmpty ? null : () => _goToPage(2),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Candy.raspberry,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Continue →',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Page 3: Brands ────────────────────────────────────────────────────────

  Widget _buildBrandsPage() {
    final filtered = _selectedCats.isEmpty
        ? _kBrands
        : _kBrands.where((b) => b.cats.any(_selectedCats.contains)).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StepDots(current: 1),
            const SizedBox(height: 24),
            const Text('Pick your favorite brands',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                    color: Candy.chocolate, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text("We'll bump their deals to the top of your feed",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 16),

            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 10, runSpacing: 10,
                  children: filtered.map((b) {
                    final sel = _selectedBrands.contains(b.name);
                    return FilterChip(
                      label: Text(b.name),
                      selected: sel,
                      onSelected: (_) => setState(() {
                        sel ? _selectedBrands.remove(b.name) : _selectedBrands.add(b.name);
                      }),
                      selectedColor: Candy.raspberry.withValues(alpha: 0.15),
                      checkmarkColor: Candy.raspberry,
                      side: BorderSide(
                          color: sel ? Candy.raspberry : Colors.grey.shade300),
                      labelStyle: TextStyle(
                        fontSize: 13,
                        color: sel ? Candy.raspberry : Candy.chocolate,
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

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _savePrefsAndLaunch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Candy.raspberry,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        _selectedBrands.isEmpty
                            ? 'Skip for now →'
                            : 'Start discovering deals →',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepDots extends StatelessWidget {
  final int current; // 0 = categories, 1 = brands
  const _StepDots({required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(2, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 6),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? Candy.raspberry : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _SelectChip extends StatelessWidget {
  final IconData  icon;
  final String    label;
  final bool      selected;
  final VoidCallback onTap;
  const _SelectChip({required this.icon, required this.label,
      required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? Candy.raspberry.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? Candy.raspberry : Colors.grey.shade200,
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18,
                color: selected ? Candy.raspberry : Colors.grey.shade500),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? Candy.raspberry : Candy.chocolate,
            ))),
            if (selected)
              const Icon(Icons.check_circle, size: 16, color: Candy.raspberry),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController  controller;
  final String                 label;
  final String                 hint;
  final bool                   obscure;
  final Widget?                suffix;
  final TextInputType          inputType;
  final TextCapitalization     capitalization;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscure        = false,
    this.suffix,
    this.inputType      = TextInputType.text,
    this.capitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: Candy.chocolate)),
        const SizedBox(height: 6),
        TextField(
          controller:          controller,
          obscureText:         obscure,
          keyboardType:        inputType,
          textCapitalization:  capitalization,
          decoration: InputDecoration(
            hintText:        hint,
            hintStyle:       TextStyle(color: Colors.grey.shade400, fontSize: 14),
            suffixIcon:      suffix,
            filled:          true,
            fillColor:       Colors.white,
            contentPadding:  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border:          OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder:   OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder:   OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Candy.raspberry, width: 1.5)),
          ),
        ),
      ],
    );
  }
}
