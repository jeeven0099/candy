import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/push_token_service.dart';
import '../services/saved_deals_service.dart';
import '../services/supabase_service.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import 'onboarding_screen.dart';

const _kRadiusKey     = 'near_me_radius_mi';
const _kRadiusOptions = [1, 3, 5, 10, 25];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _radiusMi = 5;
  String _fcmStatus = 'Tap to check';
  bool _fcmChecking = false;

  @override
  void initState() {
    super.initState();
    _loadRadius();
  }

  Future<void> _checkFcm() async {
    setState(() { _fcmChecking = true; _fcmStatus = 'Checking…'; });
    try {
      if (Firebase.apps.isEmpty) {
        setState(() { _fcmStatus = 'Firebase not initialized'; _fcmChecking = false; });
        return;
      }
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        setState(() { _fcmStatus = 'Permission denied in iOS Settings'; _fcmChecking = false; });
        return;
      }
      // Wait up to 10 s for APNs token (required when swizzling is disabled)
      String? apns;
      for (int i = 0; i < 5 && apns == null; i++) {
        try {
          apns = await FirebaseMessaging.instance
              .getAPNSToken()
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
        } catch (_) {}
        if (apns == null) await Future.delayed(const Duration(seconds: 2));
      }
      if (apns == null) {
        setState(() { _fcmStatus = 'APNs token unavailable — Push Notifications capability missing in provisioning profile?'; _fcmChecking = false; });
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        setState(() { _fcmStatus = 'getToken() = null — APNs key wrong in Firebase'; _fcmChecking = false; });
        return;
      }
      setState(() { _fcmStatus = 'Token: ${token.substring(0, 20)}…\nSaving…'; });
      await PushTokenService.register();
      final row = await SupabaseService.client
          .from('device_tokens').select('token').limit(1).maybeSingle();
      setState(() {
        _fcmStatus = row != null ? 'Saved to Supabase' : 'Token ok but Supabase save failed';
        _fcmChecking = false;
      });
    } catch (e) {
      setState(() { _fcmStatus = 'Error: $e'; _fcmChecking = false; });
    }
  }

  Future<void> _loadRadius() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_kRadiusKey);
    if (saved != null && mounted) setState(() => _radiusMi = saved);
  }

  Future<void> _saveRadius(int mi) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRadiusKey, mi);
    UserPrefsService.nearMeRadiusNotifier.value = mi;
    if (mounted) setState(() => _radiusMi = mi);
    // Persist to users table so the DB reflects the actual choice
    final authId = SupabaseService.currentUserId;
    if (authId != null) {
      SupabaseService.client
          .from('users')
          .update({'radius_miles': mi})
          .eq('auth_id', authId)
          .then((_) {}, onError: (_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Candy.cream,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            if (SupabaseService.isLoggedIn)
              SliverToBoxAdapter(child: _buildAccountSection()),
            SliverToBoxAdapter(child: _buildLocationSection()),
            SliverToBoxAdapter(child: _buildDebugSection()),
            SliverToBoxAdapter(child: _buildAboutSection()),
            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        'Profile',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: Candy.chocolate,
        ),
      ),
    );
  }

  // ── Account ────────────────────────────────────────────────────────────────

  Widget _buildAccountSection() {
    final email = SupabaseService.currentUser?.email ?? '';
    return _Section(
      icon: Icons.account_circle_outlined,
      title: 'Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (email.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(email,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ),
          _TileRow(
            icon: Icons.tune_outlined,
            label: 'Edit preferences',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const OnboardingScreen(startAtPreferences: true)),
            ),
          ),
          const Divider(height: 1, indent: 40),
          _TileRow(
            icon: Icons.logout,
            label: 'Sign out',
            onTap: () async {
              SavedDealsService().clearLocal();
              await AuthService.signOut();
              UserPrefsService().clear();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  (_) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // ── Push notification debug ────────────────────────────────────────────────

  Widget _buildDebugSection() {
    return _Section(
      icon: Icons.notifications_outlined,
      title: 'Push Notifications',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_fcmStatus,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _fcmChecking ? null : _checkFcm,
              child: Text(_fcmChecking ? 'Checking…' : 'Check & Register Token'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Location radius ────────────────────────────────────────────────────────

  Widget _buildLocationSection() {
    return _Section(
      icon: Icons.near_me_outlined,
      title: 'Near Me Radius',
      subtitle: 'Distance for the Near Me chip in Deals',
      child: Row(
        children: _kRadiusOptions.map((mi) {
          final selected = mi == _radiusMi;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('$mi mi'),
              selected: selected,
              onSelected: (_) => _saveRadius(mi),
              selectedColor: Candy.raspberry,
              backgroundColor: Colors.white,
              side: BorderSide(
                  color: selected ? Candy.raspberry : Colors.grey.shade300),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? Colors.white : Candy.chocolate,
              ),
              showCheckmark: false,
              shape: const StadiumBorder(),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── About / feedback ───────────────────────────────────────────────────────

  Widget _buildAboutSection() {
    return _Section(
      icon: Icons.info_outline,
      title: 'About',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TileRow(
            icon: Icons.bug_report_outlined,
            label: 'Send feedback',
            onTap: () async {
              final uri = Uri.parse(
                  'mailto:support@candy.app?subject=Candy%20Feedback');
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            },
          ),
          const Divider(height: 1, indent: 40),
          _TileRow(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy & data',
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Privacy & Data'),
                content: const Text(
                  'Candy does not share your personal data with third parties. '
                  'Your search history, saved deals, and interaction data are stored '
                  'on our secure servers to improve your recommendations. '
                  'You can delete your account and all associated data at any time.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Got it'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Tiny layout helpers
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Candy.raspberry),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Candy.chocolate)),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 26),
              child: Text(subtitle!,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _TileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TileRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Candy.chocolate.withValues(alpha: 0.6)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 14, color: Candy.chocolate)),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

