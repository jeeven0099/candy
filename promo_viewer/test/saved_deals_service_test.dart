import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/promotion.dart';
import 'package:promo_viewer/services/saved_deals_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/reliable_offer.dart';

class _ControlledStorage extends Fake implements SharedPreferences {
  final values = <String, String>{};
  bool succeed = true;
  Completer<bool>? pending;
  @override
  String? getString(String key) => values[key];
  @override
  Future<bool> setString(String key, String value) async {
    if (!succeed) return false;
    values[key] = value;
    return pending?.future ?? true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final offer = Promotion.fromJson(reliableOfferJson({}));

  test('saves are idempotent and reload from account-scoped storage', () async {
    final storage = _ControlledStorage();
    final service = SavedDealsService.forTesting(
      currentAccount: () => 'A',
      storage: storage,
    );
    await service.save(offer);
    await service.save(offer);
    expect(service.all, hasLength(1));
    service.clearLocal();
    expect(service.all, isEmpty);
    await service.loadForUser('A');
    expect(service.isSaved(offer.id), isTrue);
    await service.unsave(offer.id);
    await service.loadForUser('A');
    expect(service.all, isEmpty);
  });

  test(
    'an account change hides the previous account before a reload',
    () async {
      var account = 'A';
      final storage = _ControlledStorage();
      final service = SavedDealsService.forTesting(
        currentAccount: () => account,
        storage: storage,
      );
      await service.save(offer);
      account = 'B';
      expect(service.all, isEmpty);
      expect(service.isSaved(offer.id), isFalse);
      expect(service.get(offer.id), isNull);
      await service.loadForUser('B');
      expect(service.all, isEmpty);
      account = 'A';
      await service.loadForUser('A');
      expect(service.isSaved(offer.id), isTrue);
    },
  );

  test('an in-flight save never writes into the next account cache', () async {
    var account = 'A';
    final storage = _ControlledStorage()..pending = Completer<bool>();
    final service = SavedDealsService.forTesting(
      currentAccount: () => account,
      storage: storage,
    );
    final save = service.save(offer);
    await Future<void>.delayed(Duration.zero);
    account = 'B';
    await service.loadForUser('B');
    storage.pending!.complete(true);
    await save;
    expect(service.all, isEmpty);
    expect(storage.values.containsKey('candy_saved_deals_B'), isFalse);
    expect(storage.values.containsKey('candy_saved_deals_A'), isTrue);
  });

  test('a failed local save rolls back instead of reporting success', () async {
    final storage = _ControlledStorage()..succeed = false;
    final service = SavedDealsService.forTesting(
      currentAccount: () => 'A',
      storage: storage,
    );
    await expectLater(service.save(offer), throwsStateError);
    expect(service.isSaved(offer.id), isFalse);
  });

  test(
    'a failed old-account unsave cannot restore its snapshot into a new account',
    () async {
      var account = 'A';
      final storage = _ControlledStorage();
      final service = SavedDealsService.forTesting(
        currentAccount: () => account,
        storage: storage,
      );
      await service.save(offer);
      storage.pending = Completer<bool>();
      final unsave = service.unsave(offer.id);
      final failure = expectLater(unsave, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      account = 'B';
      await service.loadForUser('B');
      storage.pending!.complete(false);
      await failure;
      expect(service.all, isEmpty);
      expect(service.get(offer.id), isNull);
    },
  );

  test('a failed local unsave keeps the saved deal available', () async {
    final storage = _ControlledStorage();
    final service = SavedDealsService.forTesting(
      currentAccount: () => 'A',
      storage: storage,
    );
    await service.save(offer);
    storage.succeed = false;
    await expectLater(service.unsave(offer.id), throwsStateError);
    expect(service.isSaved(offer.id), isTrue);
  });
}
