import 'package:flutter/foundation.dart';

/// Temporary debug log for OAuth flow investigation (TestFlight build).
/// Shows on the sign-in page so the user can report what they see.
class AuthDebug {
  static final log = ValueNotifier<List<String>>([]);

  static void add(String msg) {
    final t = DateTime.now();
    final ts =
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    log.value = ['$ts  $msg', ...log.value].take(12).toList();
  }
}
