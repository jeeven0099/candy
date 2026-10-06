import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/gmail_connection_service.dart';
import '../services/saved_deals_service.dart';
import '../services/supabase_service.dart';
import '../services/user_prefs_service.dart';
import '../theme/candy_colors.dart';
import 'onboarding_screen.dart';

const _kRadiusKey = 'near_me_radius_mi';
const _kRadiusOptions = [1, 3, 5, 10, 25];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  int _radiusMi = 5;
  StreamSubscription<AuthState>? _authSub;
  GmailConnectionStatus? _gmailStatus;
  bool _gmailBusy = false;
  String? _gmailError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GmailConnectionService.lastError.addListener(_onGmailDiagnosticChange);
    GmailConnectionService.diagnosticLog.addListener(_onGmailDiagnosticChange);
    _gmailError = GmailConnectionService.lastError.value;
    _loadRadius();
    _loadGmailStatus();
    _restoreGmailConnect();
    if (SupabaseService.isReady) {
      _authSub = SupabaseService.authStateChanges.listen(
        _onAuthStateChange,
        onError: (Object error) {
          if (GmailConnectionService.hasPendingConnect) {
            GmailConnectionService.reportFailure('oauth_callback', error);
            unawaited(GmailConnectionService.cancelPendingConnect());
          }
        },
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GmailConnectionService.lastError.removeListener(_onGmailDiagnosticChange);
    GmailConnectionService.diagnosticLog.removeListener(
      _onGmailDiagnosticChange,
    );
    _authSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !GmailConnectionService.hasPendingConnect) {
      return;
    }
    _finishGmailConnect(SupabaseService.client.auth.currentSession);
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

  Future<void> _loadGmailStatus() async {
    if (!SupabaseService.isLoggedIn) return;
    final status = await GmailConnectionService.loadStatus();
    if (!mounted) return;
    setState(() => _gmailStatus = status);
  }

  Future<void> _restoreGmailConnect() async {
    await GmailConnectionService.restorePendingConnect();
    if (!mounted || !GmailConnectionService.hasPendingConnect) return;
    await _finishGmailConnect(SupabaseService.client.auth.currentSession);
  }

  Future<void> _onAuthStateChange(AuthState state) async {
    if (state.event != AuthChangeEvent.signedIn ||
        !GmailConnectionService.hasPendingConnect) {
      return;
    }
    GmailConnectionService.log(
      'oauth_callback',
      'Received signed-in event from Google',
    );
    await _finishGmailConnect(state.session, fromOAuthCallback: true);
  }

  void _onGmailDiagnosticChange() {
    if (mounted) {
      setState(() => _gmailError = GmailConnectionService.lastError.value);
    }
  }

  Future<void> _finishGmailConnect(
    Session? session, {
    bool fromOAuthCallback = false,
  }) async {
    if (_gmailBusy || !mounted) return;
    setState(() {
      _gmailBusy = true;
      _gmailError = null;
    });
    try {
      final connected = await GmailConnectionService.vaultSessionIfPending(
        session,
        fromOAuthCallback: fromOAuthCallback,
      );
      if (!connected) return;
      await _loadGmailStatus();
      try {
        await closeInAppWebView();
      } catch (_) {}
    } catch (e) {
      final failure = GmailConnectionService.reportFailure(
        'save_connection',
        e,
      );
      await GmailConnectionService.cancelPendingConnect();
      if (mounted) {
        setState(() => _gmailError = failure);
      }
    } finally {
      if (mounted) setState(() => _gmailBusy = false);
    }
  }

  Future<void> _connectGmail() async {
    setState(() {
      _gmailBusy = true;
      _gmailError = null;
    });
    try {
      await GmailConnectionService.startConnect();
    } catch (e) {
      final failure = GmailConnectionService.reportFailure('open_google', e);
      await GmailConnectionService.cancelPendingConnect();
      if (mounted) setState(() => _gmailError = failure);
    } finally {
      if (mounted) setState(() => _gmailBusy = false);
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
              SliverToBoxAdapter(child: _buildAccountSection())
            else
              SliverToBoxAdapter(child: _buildSignInSection()),
            if (SupabaseService.isLoggedIn)
              SliverToBoxAdapter(child: _buildGmailSection()),
            SliverToBoxAdapter(child: _buildLocationSection()),
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
        'Settings',
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
              child: Text(
                email,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ),
          _TileRow(
            icon: Icons.tune_outlined,
            label: 'Edit preferences',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const OnboardingScreen(startAtPreferences: true),
              ),
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

  // ── Location radius ────────────────────────────────────────────────────────

  Widget _buildSignInSection() {
    return _Section(
      icon: Icons.account_circle_outlined,
      title: 'Account',
      child: _TileRow(
        icon: Icons.login,
        label: 'Create account or sign in',
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OnboardingScreen())),
      ),
    );
  }

  Widget _buildGmailSection() {
    final status = _gmailStatus;
    final connected = status?.isConnected ?? false;
    final title = connected
        ? (status?.googleEmail?.isNotEmpty == true
              ? status!.googleEmail!
              : 'Gmail connected')
        : 'Gmail not connected';
    final detail = connected
        ? _formatLastSync(status?.lastSyncAt)
        : 'Connect Gmail';

    return _Section(
      icon: Icons.mail_outline,
      title: 'Gmail Deals',
      subtitle: 'Private offers from your promotions inbox',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                connected ? Icons.check_circle : Icons.mail_outline,
                size: 20,
                color: connected ? const Color(0xFF2E7D32) : Candy.chocolate,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Candy.chocolate,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _gmailBusy ? null : _connectGmail,
                icon: _gmailBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link, size: 16),
                label: Text(connected ? 'Reconnect' : 'Connect'),
                style: FilledButton.styleFrom(
                  backgroundColor: Candy.raspberry,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (_gmailError != null || status?.syncError != null) ...[
            const SizedBox(height: 10),
            SelectableText(
              _gmailError ?? status!.syncError!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFC62828)),
            ),
          ],
          if (GmailConnectionService.diagnosticLog.value.isNotEmpty)
            TextButton.icon(
              onPressed: _showGmailLog,
              icon: const Icon(Icons.article_outlined, size: 18),
              label: const Text('Connection log'),
            ),
        ],
      ),
    );
  }

  void _showGmailLog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gmail connection log'),
        content: SizedBox(
          width: 480,
          height: MediaQuery.sizeOf(dialogContext).height * 0.5,
          child: SingleChildScrollView(
            child: ValueListenableBuilder<String>(
              valueListenable: GmailConnectionService.diagnosticLog,
              builder: (_, log, _) =>
                  SelectableText(log, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy connection log',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: GmailConnectionService.diagnosticLog.value),
              );
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Connection log copied')),
                );
              }
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatLastSync(DateTime? value) {
    if (value == null) return 'Not synced yet';
    final local = value.toLocal();
    return 'Last sync ${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildLocationSection() {
    return _Section(
      icon: Icons.near_me_outlined,
      title: 'Near Me Radius',
      subtitle: 'Distance used for Near Me deals',
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
                color: selected ? Candy.raspberry : Colors.grey.shade300,
              ),
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
                'mailto:support@candy.app?subject=Candy%20Feedback',
              );
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Candy.chocolate,
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 26),
              child: Text(
                subtitle!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
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

  const _TileRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

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
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, color: Candy.chocolate),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
