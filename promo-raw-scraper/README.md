# promo-raw-scraper

The nightly Python pipeline that powers the Candy app. Scrapes 800+ brand promotion pages, extracts structured deal data with an LLM, verifies claims against the original text, scores results, and pushes the final JSON to the Flutter app.

## Steps

| # | Script | What it does |
|---|--------|--------------|
| 1 | `src/run_scraper.py` | Fetch brand pages (HTTP + Playwright for JS-rendered pages), hash-deduplicate, save raw text |
| 2 | `src/inspect_raw_data.py` | Scan raw text, build summary CSV |
| 3 | `src/list_text_candidates.py` | Rank and deduplicate candidates |
| 4 | `src/parse_candidates.py` | LLM extraction → Pydantic-validated `Promotion` objects → `structured_outputs/{brand}.json` |
| 5 | `src/normalize_promotions.py` | Clean, deduplicate, attach source evidence → `normalized_outputs/{brand}.json` |
| 5b | `backfill_deal_urls.py` | Fill `deal_url` from raw text markers (no LLM needed) |
| 6 | `src/generate_review_csv.py` | Human-readable `logs/promotion_review.csv` |
| 7 | `src/generate_merged_json.py` | Web-only promotions → `merged_promotions.json` |
| 8 | `src/merge_all_promotions.py` | Web + email → `all_promotions.json` |
| 9 | `src/run_keyword_backfill.py` | Generate search keywords for new brands |
| 10 | `src/apply_keyword_store.py` | Re-apply stored keywords after merge |
| 11 | `src/generate_fast_redemption.py` | Add `fast_redemption` one-liner to each deal |
| 12 | `src/generate_scores.py` | Compute `rank_base_score` |
| 13 | `src/generate_notifications.py` | Build `notification_candidates.json` |
| 14 | *(inline)* | Copy `all_promotions.json` to `promo_viewer/assets/` |
| 15 | *(inline)* | `git commit + push` → triggers Flutter web rebuild |

Run all steps in order:

```powershell
python run_pipeline.py --model openrouter --openrouter-model openai/gpt-4o-mini
```

Resume from a specific step after a crash:

```powershell
python run_pipeline.py --from-step 4 --skip-scrape --model openrouter --openrouter-model openai/gpt-4o-mini
```

## Setup

```powershell
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python -m playwright install chromium
```

Copy `.env.example` to `.env` and add your keys.

## Nightly run

`run_nightly.ps1` (at the repo root) is registered as a Windows scheduled task. It runs the full pipeline each night and runs a retry pass every three days for brands that previously failed.

## Data model

Deals are validated against the `Promotion` Pydantic model in `src/models.py`. Key fields:

- **Identity**: `brand`, `promotion_title`, `promotion_type`, `source`
- **Discount**: `discount_type`, `discount_value`, `promo_code`, `minimum_spend`
- **Eligibility**: `requires_membership`, `new_user_only`, `deal_scope`
- **Timing**: `start_date`, `end_date`, `valid_days`
- **Redemption**: `redemption_method`, `redemption_steps`, `deal_url`
- **Quality**: `global_quality_score`, `confidence_score`, `extraction_status`
- **Evidence**: `source_evidence` — excerpt from the original page that substantiates each claim

## Sources

Sources are configured in `sources/urls.json`. Each entry has a `brand`, `category`, one or more `urls`, a `source_type`, and an `allowed_to_fetch` flag. Only sources with `allowed_to_fetch: true` are scraped.

## Tests

```powershell
python -m pytest tests/ -v
```

76 tests across 5 files.

## Outputs

| Path | Contents |
|------|----------|
| `raw_text/*.txt` | Cleaned visible page text |
| `raw_text/*.meta.json` | URL, scrape timestamp, HTTP status |
| `structured_outputs/{brand}.json` | Raw LLM extraction |
| `normalized_outputs/{brand}.json` | Cleaned, verified deals |
| `all_promotions.json` | Final merged output (web + email) |
| `logs/promotion_review.csv` | Human-readable review sheet |
| `logs/pipeline_*.log` | Full run log per pipeline execution |
