import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/config.dart';
import 'package:promo_viewer/screens/profile_screen.dart';
import 'package:promo_viewer/services/auth_service.dart';
import 'package:promo_viewer/services/email_deals_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('bootstrap and catalog use the deployed master branch', () {
    final config = jsonDecode(File('../server_config.json').readAsStringSync());
    expect(
      Uri.parse(kConfigUrl).path,
      '/jeeven0099/candy/master/server_config.json',
    );
    expect(
      config['server_url'],
      'https://raw.githubusercontent.com/jeeven0099/candy/master/promo_viewer/assets',
    );
  });

  test('beta cannot start Gmail consent or load private email deals', () async {
    expect(kGmailDealsEnabled, isFalse);
    await expectLater(AuthService.connectGmailForDeals(), throwsStateError);
    expect(await EmailDealsService.loadForCurrentUser(), isEmpty);
  });

  testWidgets('settings remain available without a Gmail entry point', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Gmail Deals'), findsNothing);
    expect(find.text('Connect Gmail'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
