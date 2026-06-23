import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class SupabaseService {
  static bool _ready = false;

  static bool get isReady => _ready;
  static bool get isLoggedIn => _ready && client.auth.currentUser != null;
  static User? get currentUser => _ready ? client.auth.currentUser : null;
  static String? get currentUserId => currentUser?.id;

  static SupabaseClient get client => Supabase.instance.client;

  static Stream<AuthState> get authStateChanges =>
      Supabase.instance.client.auth.onAuthStateChange;

  static Future<void> init() async {
    if (supabaseUrl.contains('YOUR_PROJECT_ID')) {
      debugPrint('[Supabase] Not configured — running in guest mode');
      return;
    }
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnon); // ignore: deprecated_member_use
      _ready = true;
    } catch (e) {
      debugPrint('[Supabase] Init failed: $e — running in guest mode');
    }
  }
}
