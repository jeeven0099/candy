# Per-User Gmail Ingestion

This pipeline keeps Gmail deals private to each Candy user.

## Flow

1. The app asks the signed-in user for Gmail readonly consent from Settings.
2. `supabase/functions/gmail-token-vault` stores Google provider tokens with the service role.
3. `src/user_email_ingestion.py` reads one connected Gmail account, fetches Promotions-tab emails from the past 14 days, extracts deals, scores them with the heuristic ranker, and writes rows to `user_email_deals`.
4. The app reads only the signed-in user's active `user_email_deals` rows and blends them into For You ranking.

The public nightly pipeline is unchanged. Do not re-enable the old global `email_promotions.json` merge for multi-user builds.

## Required Secrets

Supabase Edge Function:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

Email ingestion runner:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `GMAIL_GOOGLE_CLIENT_ID` or `GOOGLE_CLIENT_ID`
- `GMAIL_GOOGLE_CLIENT_SECRET` or `GOOGLE_CLIENT_SECRET`

The Google OAuth client must be the same client used for the app's Supabase Google provider so refresh tokens can be exchanged.

## Manual Run

The runner loads the scraper's local `.env` automatically. `--env-file` can select a different secrets file.

```powershell
cd C:\Users\user\Desktop\promo-raw-scraper\promo-raw-scraper
python .\src\user_email_ingestion.py --google-email you@gmail.com --reason manual
```

The default Gmail query is:

```text
category:promotions newer_than:14d
```

This stores each extracted deal in `user_email_deals.promotion_json` using the same normalized promotion fields as web deals.
All matching messages are fetched through Gmail pagination. Use `--limit 50` for a smaller trial run. Both the Promotions label and the 14-day received-date window are checked on every message; additional search filters cannot widen that scope.

To sync by Candy user id instead of Gmail address:

```powershell
python .\src\user_email_ingestion.py --user-id <users.id> --reason manual
```

To sync every connected Gmail account later, you must opt in explicitly:

```powershell
python .\src\user_email_ingestion.py --all-users --limit 50 --reason scheduled
```

The personal ranker is model-free by default. Later, use a model by passing `--rank-model` and setting `OPENROUTER_API_KEY`:

```powershell
python .\src\user_email_ingestion.py --google-email you@gmail.com --extraction-model openrouter --openrouter-model openai/gpt-4o-mini --rank-model <chosen-model>
```

## First Deployment

1. Apply `supabase/migrations/003_email_ingestion.sql` in the Supabase SQL editor. This adds private deal tables and their row-level policies.
2. Deploy `supabase/functions/gmail-token-vault/index.ts` as the `gmail-token-vault` Edge Function. The Supabase URL and keys above are provided automatically by hosted Edge Functions. Keep JWT verification enabled.
3. Build the updated Candy app and connect the desired Google account in Settings > Gmail Deals. The function verifies the Gmail address from Google's API before saving tokens.
4. Run the command above with that Gmail address. The Gmail token must belong to the selected connection; a mismatch stops the run.

With an authenticated Supabase CLI, the function can be deployed from the repository root:

```powershell
supabase db query --linked --file supabase/migrations/003_email_ingestion.sql
supabase functions deploy gmail-token-vault --project-ref <project-ref>
```

The first manual run can use the fresh access token. Continued syncing after it expires requires the Google client ID and secret listed above. Connecting ordinary Google sign-in alone does not provide Gmail consent.

## Validation

```powershell
cd promo-raw-scraper
python -m pytest tests/test_user_email_ingestion.py tests/test_core.py -q
```

The tests cover pagination, account selection, Promotions/date restrictions, short emails, coupon codes, redemption links, expiry, and private storage. No live mailbox or model is used in tests.

App OAuth checks are in `promo_viewer/test/gmail_connection_test.dart`: stale sessions, mismatched accounts, and abandoned connection attempts. Run them with `flutter test test/gmail_connection_test.dart` from `promo_viewer`.
