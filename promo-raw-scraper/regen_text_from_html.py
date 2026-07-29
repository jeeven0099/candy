"""
regen_text_from_html.py

Re-runs clean_html.clean_visible_text() on every saved raw HTML file so that
[deal_url:/path] markers (added in the latest clean_html.py update) are
injected into the raw text files. Run this once after updating clean_html.py.

After this script: run  python run_pipeline.py --skip-scrape --from-step 4 --force ...
to re-extract promotions from the updated text files.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC  = ROOT / "src"
sys.path.insert(0, str(SRC))

from clean_html import clean_visible_text  # noqa: E402 (needs sys.path first)

RAW_HTML_DIR = ROOT / "raw_html"
RAW_TEXT_DIR = ROOT / "raw_text"

html_files = sorted(RAW_HTML_DIR.glob("*.html"))
print(f"Found {len(html_files)} HTML file(s) to reprocess.\n")

ok = skipped = failed = 0
for html_path in html_files:
    stem = html_path.stem  # e.g. aspinal_of_london_20260728T020808Z
    txt_path = RAW_TEXT_DIR / f"{stem}.txt"

    if not txt_path.exists():
        skipped += 1
        continue

    try:
        html = html_path.read_text(encoding="utf-8", errors="replace")
        new_text = clean_visible_text(html)
        txt_path.write_text(new_text, encoding="utf-8")
        ok += 1
    except Exception as exc:
        print(f"  [ERROR] {stem}: {exc}")
        failed += 1

print(f"\nDone: {ok} reprocessed, {skipped} skipped (no .txt), {failed} failed.")
print(f"\nNext step:")
print(f"  python run_pipeline.py --skip-scrape --from-step 4 --force "
      f"--model openrouter --openrouter-model openai/gpt-oss-120b --cloud-timeout 60")
