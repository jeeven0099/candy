# Promo Raw Scraper

A raw collection foundation for public promotion/rewards/sales pages and promotional emails.

This project does **not** do AI extraction yet. It only:

1. Loads configured public source URLs from `sources/urls.json`
2. Fetches allowed pages politely
3. Saves raw HTML to `raw_html/`
4. Extracts visible text and saves it to `raw_text/`
5. Collects promotional emails from IMAP or local `.eml` files
6. Saves raw emails to `raw_email/` and cleaned email text to `raw_email_text/`
7. Computes SHA256 content hashes
8. Skips duplicate unchanged content
9. Logs each run to `logs/*.jsonl`
10. Produces summary/candidate files with keyword signals

## Safety / scope

This scraper does not bypass CAPTCHAs, login walls, anti-bot systems, or private pages. Sources default to normal public pages only. Set `allowed_to_fetch` to `false` for any source you have not reviewed.

The email pipeline only reads messages from an inbox you explicitly configure. Do not commit `.env`, raw email files, or email logs; `.gitignore` excludes them by default.

## Setup

```bash
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\\Scripts\\activate
pip install -r requirements.txt
```

## Run

```bash
python src/run_scraper.py
```

Run a single brand:

```bash
python src/run_scraper.py --brand Starbucks
```

Dry run:

```bash
python src/run_scraper.py --dry-run --limit 5
```

Inspect raw text quality:

```bash
python src/inspect_raw_data.py
```

## Email Pipeline

The email pipeline can read your mailbox through IMAP. Credentials are read from environment variables only.

PowerShell example for Gmail with an app password:

```powershell
$env:EMAIL_ADDRESS="your_email@gmail.com"
$env:EMAIL_APP_PASSWORD="your_app_password"
$env:EMAIL_GMAIL_QUERY='newer_than:30d (sale OR deal OR coupon OR promo OR offer OR discount)'
python src/email_pipeline.py --limit 50
```

Or fill in `.env.test` and load it directly:

```powershell
python src/email_pipeline.py --env-file .env.test --limit 50
```

Generic IMAP example:

```powershell
$env:EMAIL_ADDRESS="you@example.com"
$env:EMAIL_APP_PASSWORD="your_app_password"
$env:EMAIL_IMAP_HOST="imap.example.com"
python src/email_pipeline.py --limit 50 --since-days 30
```

Process exported `.eml` files without connecting to email:

```powershell
python src/email_pipeline.py --eml-dir C:\path\to\eml_exports --limit 50
```

## Outputs

- `raw_html/*.html`: raw fetched HTML
- `raw_text/*.txt`: cleaned visible text
- `raw_text/*.meta.json`: metadata sidecar
- `raw_email/*.eml`: raw fetched email messages
- `raw_email_text/*.txt`: cleaned visible email text
- `raw_email_text/*.meta.json`: email metadata sidecar
- `logs/scrape_results.jsonl`: scrape attempts
- `logs/email_results.jsonl`: email ingestion attempts
- `logs/email_deal_candidates.jsonl`: email messages with deal-like signals
- `logs/raw_data_summary.csv`: summary of extracted text files

## Next step

After raw data looks useful, add the AI extraction layer:

```text
raw_text/*.txt -> LLM extractor -> validated promotion JSON
```
