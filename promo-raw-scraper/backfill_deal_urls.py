"""
backfill_deal_urls.py

Scans existing raw text files for [deal_url:/path] markers and matches them
to existing normalized promotions by keyword proximity. Updates normalized
JSON files in place — no LLM calls needed.

Run after regen_text_from_html.py has been executed.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC  = ROOT / "src"
sys.path.insert(0, str(SRC))

NORMALIZED_DIR = ROOT / "normalized_outputs"
RAW_TEXT_DIR   = ROOT / "raw_text"

_DEAL_URL_RE = re.compile(r'\[deal_url:(/[^\]]*)\]')


def _most_recent_txt(brand_slug: str) -> Path | None:
    files = sorted(RAW_TEXT_DIR.glob(f"{brand_slug}_*.txt"))
    return files[-1] if files else None


def _slugify(value: str) -> str:
    value = value.lower().strip()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    return value.strip("_") or "unknown"


def _keyword_tokens(text: str) -> set[str]:
    """Return meaningful lowercase words (length >= 4) from a string."""
    return {w for w in re.split(r'\W+', text.lower()) if len(w) >= 4}


def find_deal_url_for_promo(promo: dict, text: str, markers: list[tuple[int, str]]) -> str | None:
    """
    Find the best matching [deal_url:] marker for a promotion.

    Strategy: for each marker position, score it by how many of the
    promotion's title keywords appear within a 600-char window around it.
    Return the path of the highest-scoring marker (min 1 keyword match).
    """
    if not markers:
        return None

    title  = promo.get("promotion_title") or ""
    summary = promo.get("short_summary") or ""
    query_tokens = _keyword_tokens(title + " " + summary)

    # Remove very common words that appear everywhere on the page
    query_tokens -= {"that", "this", "with", "from", "your", "save", "sale",
                     "deal", "offer", "free", "shop", "brand", "item", "more"}
    if not query_tokens:
        return None

    best_path  = None
    best_score = 0

    for pos, path in markers:
        window_start = max(0, pos - 400)
        window_end   = min(len(text), pos + 200)
        window = text[window_start:window_end].lower()
        window_tokens = _keyword_tokens(window)
        score = len(query_tokens & window_tokens)
        if score > best_score:
            best_score = score
            best_path  = path

    return best_path if best_score >= 1 else None


def process_brand(norm_path: Path) -> tuple[int, int]:
    """Return (promotions_updated, promotions_total)."""
    data = json.loads(norm_path.read_text(encoding="utf-8"))
    promotions = data.get("promotions", [])
    if not promotions:
        return 0, 0

    brand_slug = _slugify(data.get("brand", norm_path.stem))
    txt_path = _most_recent_txt(brand_slug)
    if not txt_path:
        return 0, len(promotions)

    text = txt_path.read_text(encoding="utf-8", errors="replace")

    # Extract all markers with their positions
    markers = [(m.start(), m.group(1)) for m in _DEAL_URL_RE.finditer(text)]
    if not markers:
        return 0, len(promotions)

    # Resolve relative paths to absolute using website_domain
    domain = data.get("website_domain", "")

    updated = 0
    for promo in promotions:
        # Skip if already has a deal_url
        if promo.get("deal_url"):
            continue

        path = find_deal_url_for_promo(promo, text, markers)
        if path:
            absolute = f"https://www.{domain}{path}" if domain else path
            promo["deal_url"] = absolute
            updated += 1

    if updated:
        norm_path.write_text(
            json.dumps(data, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

    return updated, len(promotions)


def main() -> None:
    norm_files = sorted(NORMALIZED_DIR.glob("*.json"))
    print(f"Processing {len(norm_files)} brand files...\n")

    total_updated = 0
    total_promos  = 0
    brands_with_urls = 0

    for path in norm_files:
        try:
            updated, total = process_brand(path)
            total_promos += total
            if updated:
                total_updated += updated
                brands_with_urls += 1
                print(f"  {path.stem}: +{updated} deal_url(s)")
        except Exception as exc:
            print(f"  [ERROR] {path.stem}: {exc}")

    print(f"\nDone.")
    print(f"  Brands with at least one deal_url : {brands_with_urls}")
    print(f"  Promotions updated                : {total_updated} / {total_promos}")


if __name__ == "__main__":
    main()
