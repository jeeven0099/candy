# promo_viewer

The Flutter app for Candy — a personal deal and promotion tracker. Runs on iOS, Android, and web.

## What it does

- Displays deals from 800+ brands, ranked by proximity, membership status, day of week, and deal quality
- Connects to Gmail (OAuth) to surface private/personalised email offers
- Saves and dismisses deals; learns preferences over time
- Push notifications for new high-value deals
- Source evidence panel — shows the exact text from the brand's page that backs each claim

## Setup

```powershell
flutter pub get
flutter run
```

The app bundles `assets/all_promotions.json` which is updated nightly by the pipeline and committed to the repo. No network request is needed to show deals on first launch.

## Distribution

**iOS (TestFlight):** Codemagic builds and signs a release IPA on every push to `master`. The GitHub Actions workflow `ios_testflight.yml` also produces an unsigned IPA for sideloading.

**Web:** The `deploy_web.yml` GitHub Actions workflow deploys to GitHub Pages on every push that touches `promo_viewer/`.

## Key files

| Path | Purpose |
|------|---------|
| `lib/models/promotion.dart` | Dart mirror of the Python `Promotion` schema; `rankScore()` personalises the feed |
| `lib/models/source_evidence.dart` | Proof receipt for a verified deal; `matchesOffer()` detects post-verification edits |
| `lib/services/gmail_connection_service.dart` | Gmail OAuth flow, token refresh, email sync trigger |
| `assets/all_promotions.json` | Bundled deal data, updated nightly |
| `assets/notification_candidates.json` | Deals queued for push notification |

## Ranking

Each deal starts with a `globalQualityScore` from the pipeline and gains or loses points at runtime:

- **Distance**: up to +30 for deals within half a mile of your location
- **Day of week**: +5 if valid today, −20 if explicitly not valid today
- **Membership**: +25 if you hold the required membership, −15 if you don't
- **Learned preferences** (beta): CatBoost adjustment of up to ±6 points based on your save/dismiss history

## Backend

Supabase handles authentication, Gmail token storage, the email sync queue, user preferences, and push notification delivery. See `supabase/` for migrations and Edge Functions.
