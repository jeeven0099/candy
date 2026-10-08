import 'package:flutter_test/flutter_test.dart';
import 'package:promo_viewer/models/user_prefs.dart';
import 'package:promo_viewer/services/user_memberships_service.dart';

void main() {
  test('membership matching cannot match an empty brand or program', () {
    expect(
      UserMembershipsService.hasMembership({'target circle'}, '', null),
      false,
    );
    expect(
      UserMembershipsService.hasMembership({''}, 'Target', 'Circle'),
      false,
    );
    expect(
      UserMembershipsService.hasMembership({'target circle'}, 'Target', null),
      true,
    );
  });
  test('memberships belong to preferences and survive hidden brand edits', () {
    const prefs = UserPrefs(
      memberships: ['Target Circle'],
      favoriteBrands: ['Target'],
    );
    final loaded = UserPrefs.fromJson(prefs.withHiddenBrand('Other').toJson());
    expect(loaded.memberships, ['Target Circle']);
    expect(loaded.withoutHiddenBrand('Other').memberships, ['Target Circle']);
    expect(loaded.withMemberships(['Costco']).favoriteBrands, ['Target']);
    expect(const UserPrefs().memberships, isEmpty);
  });
}
