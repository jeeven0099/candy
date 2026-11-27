# Candy — Personal Deal Discovery

A personal deal and promotion tracker. A nightly Python pipeline scrapes 800+ brand pages, extracts structured promotions with an LLM, and publishes the results to a Flutter app on iOS and the web.

## What it does

- Scrapes public rewards, sale, and coupon pages from 800+ brands every night
- Sends each page through an LLM to extract structured deal data (title, discount, promo code, expiry, redemption steps, etc.)
- Verifies each extracted claim against the original scraped text before marking it active
- Syncs promotional emails from a connected Gmail account for private/personalised offers
- Ranks deals by proximity, day of week, membership status, and deal quality
- Delivers results to an iOS app and a web app; push notifications for new high-value deals
- Learns from saved/dismissed deals using a lightweight CatBoost preference model (beta)

## Repository layout

```
promo-raw-scraper/   Python pipeline — scraping, LLM extraction, scoring, nightly runner
promo_viewer/        Flutter app — iOS, Android, web
supabase/            Backend — migrations, Edge Functions, email sync queue
ranking/             Learned preference model (CatBoost, beta)
```

## How the data flows

```
Brand pages (800+)
  └─ run_scraper.py          fetch + hash-deduplicate raw text
      └─ parse_candidates.py  LLM → Pydantic-validated Promotion objects
          └─ normalize_promotions.py   clean, deduplicate, attach source evidence
              └─ generate_scores.py    compute rank_base_score
                  └─ all_promotions.json  copied to promo_viewer/assets/
                      └─ git push → GitHub Actions → Flutter web rebuild
                                  └─ Codemagic → signed iOS build → TestFlight
```

Email deals follow the same path through `email_sync_worker.py` and are merged at step 8.

The pipeline runs nightly via Windows Task Scheduler (`run_nightly.ps1`). A three-day retry pass re-attempts brands that failed on the main run.

## Pipeline setup

**Requirements:** Python 3.11+, a Chromium install for Playwright, an OpenRouter API key (or a local Ollama install).

```powershell
cd promo-raw-scraper
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python -m playwright install chromium
```

Copy `.env.example` to `.env` and fill in:

```
OPENROUTER_API_KEY=...
SUPABASE_URL=...
SUPABASE_SERVICE_ROLE_KEY=...
```

**Run the full pipeline:**

```powershell
python run_pipeline.py --model openrouter --openrouter-model openai/gpt-4o-mini
```

**Common flags:**

| Flag | Purpose |
|---|---|
| `--brand Starbucks` | Process one brand end-to-end |
| `--skip-scrape` | Skip scraping, re-parse existing raw text |
| `--from-step 4` | Resume from a specific step after a crash |
| `--force` | Re-parse all brands even if content is unchanged |
| `--model ollama` | Use a local Ollama model instead of OpenRouter |

## Flutter app setup

```powershell
cd promo_viewer
flutter pub get
flutter run
```

The app reads from the bundled `assets/all_promotions.json` on first launch. Connect a Gmail account in Settings to add private email deals. Supabase credentials are baked in at build time via Dart defines.

**iOS distribution:** Codemagic builds and signs the app for TestFlight on every push to `master`. A GitHub Actions workflow (`ios_testflight.yml`) also produces an unsigned IPA for sideloading.

**Web:** `deploy_web.yml` deploys to GitHub Pages on every push that touches `promo_viewer/`.

## Tests

```powershell
cd promo-raw-scraper
python -m pytest tests/ -v
```

76 tests across 5 files covering HTML cleaning, source evidence verification, email ingestion, deal URL backfill, and the email sync worker.

## Learned ranking (beta)

A CatBoost classifier adjusts deal scores based on each user's save/dismiss history. Training requires at least 100 labelled examples across 5 users. See [`ranking/README.md`](ranking/README.md) for setup and training instructions.

## Privacy and safety

- The scraper only fetches public pages with `allowed_to_fetch: true` in `sources/urls.json`. No login walls, CAPTCHAs, or anti-bot systems are bypassed.
- Gmail access uses OAuth; raw email bodies are never stored. Only extracted deal fields and a content hash reach the database.
- LLM prompts contain only scraped page text — no user data.
- Do not commit `.env`, `raw_html/`, `raw_text/`, or any file under `raw_email/`.
