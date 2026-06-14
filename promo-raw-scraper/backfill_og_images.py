"""
One-time script: extract og:image from existing raw HTML files and save to meta.json.
Run from the promo-raw-scraper directory with the venv active:
    python backfill_og_images.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "src"))
from clean_html import extract_og_image

RAW_TEXT_DIR = Path(__file__).parent / "raw_text"

updated = 0
found = 0
missing = 0

for meta_path in sorted(RAW_TEXT_DIR.glob("*.meta.json")):
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        if "og_image" in meta:
            continue
        html_path = Path(meta.get("html_path", ""))
        if not html_path.exists():
            missing += 1
            continue
        html = html_path.read_text(encoding="utf-8", errors="replace")
        og = extract_og_image(html)
        if og:
            found += 1
        meta["og_image"] = og
        meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
        updated += 1
    except Exception as e:
        print(f"  WARN {meta_path.stem}: {e}")

print(f"Updated {updated} meta files | og:image found in {found} | {missing} missing HTML")
