# Beta Release 74

## Included

- Public For You and Near Me feeds, up to 10 qualified deals each.
- Up to 30 qualified replacements; no filler when the eligible pool runs out.
- Swipe right to like/save, left to dismiss, with action-specific Undo.
- Separate Saved tab; saved offers leave discovery feeds until unsaved.
- Signup, Settings, per-account preferences, memberships, saves, and swipe feedback.
- Birthday rewards only during the user's birthday month.
- Captured-source reliability checks before rule scores or learned adjustments.
- Correct `master` bootstrap/catalog URLs and refreshed bundled public catalog.
- New cache namespace for upgrades; pull-to-refresh bypasses the catalog cache.
- Gmail UI, connection launch, restore, and private-deal loading disabled for beta.

No Gmail worker/migration/Edge Function deployment is included. No Codemagic,
GitHub build workflow, or nightly scheduling configuration is changed. The public
scraper's evidence generation and link backfill fixes must ship with the app.

## Automated Checks

From `promo_viewer`:

```powershell
flutter test
dart run tool/audit_deal_reliability.dart assets/all_promotions.json
```

Tests cover the actual bundled cold-start feed, qualified reserves, known-city
nearby candidates, birthday restrictions, cache migration, forced refresh,
offline fallback, feedback, account-switch behavior, and notification routing.
The catalog test intentionally fails if a later build has insufficient fresh,
qualified offers. Refresh the public catalog instead of weakening the gate.

From the repository root, with the linked Supabase CLI:

```powershell
supabase db query --linked --file supabase/tests/beta_release_readiness.sql
```

This is read-only and returns schema/policies, not user records. Check that all
listed tables exist, row security is enabled, owner policies are present,
memberships and feedback metadata are deployed, and clients cannot write the
learned model. Local checks do not establish that production policies match.

## Release Order

1. Publish the source fixes, `server_config.json`, the validated catalog, and the
   app changes together on `master`. Do not release the strict app against the
   older published catalog that lacks evidence.
2. Verify both public URLs in `promo_viewer/lib/config.dart` and
   `server_config.json` return successfully, and audit the published catalog.
3. Let the existing Codemagic workflow build version `1.0.0+74`. A GitHub unsigned
   IPA build is not confirmation of a successful Codemagic/TestFlight upload.
4. Perform the device smoke test below before expanding beyond a small cohort.

## TestFlight Smoke Test (Not Yet Performed)

- Fresh install: signup without an invite code, confirmation if required, login,
  select preferences, and view real deals. No Gmail connection option is shown.
- Upgrade: the old cached catalog is not reused; refresh retrieves current data.
- Save and dismiss several deals, then verify the signed-in user's corresponding
  rows and feature snapshots in Supabase. Undo and unsave cancel their signals.
- Sign out, use a second account, and confirm preferences, memberships, saves,
  dismissed deals, and learned history do not carry over. Verify database RLS
  denies cross-account reads/writes, not only that the UI hides other records.
- Change birthday month and verify out-of-month rewards never enter either
  feed or its replacement queue.
- Allow location and test Near Me; deny permission and confirm a usable state.
  Fewer than 10 deals is acceptable when fewer pass quality/location checks.
- Tap a real notification with the app closed and open; both go to the intended
  detail page. Missing/expired deals have a safe unavailable or warning state.
- Test without a network connection. Bundled data still has source evidence;
  expired/stale offers stay excluded. Feedback delivery remains best-effort
  online; offline interactions are not guaranteed to reach Supabase.

The rule fallback works before a validated CatBoost model is available. Feedback
updates the user's local profile immediately; CatBoost trees require a separate
training/publication run and do not retrain after every swipe.
