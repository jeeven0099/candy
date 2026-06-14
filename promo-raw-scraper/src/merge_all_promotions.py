"""
merge_all_promotions.py — Merge web and email promotions into a single
all_promotions.json for the Flutter app.

Deduplication key: (brand_slug, title_slug, discount_type)
When duplicates exist, keep the one with higher confidence_score.
Adds a 'source' field: 'web' | 'email' | 'both'
"""
from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WEB_FILE   = ROOT / "merged_promotions.json"
EMAIL_FILE = ROOT / "email_promotions.json"
OUTPUT     = ROOT / "all_promotions.json"


def slugify(value: str) -> str:
    value = (value or "").lower().strip()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    return value.strip("_") or "unknown"


def dedup_key(promo: dict) -> str:
    brand = slugify(promo.get("brand", ""))
    title = slugify(promo.get("promotion_title", ""))[:40]
    dtype = promo.get("discount_type", "unknown")
    return f"{brand}|{title}|{dtype}"


def load(path: Path, source_tag: str) -> list[dict]:
    if not path.exists():
        print(f"  [SKIP] {path.name} not found")
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    promos = data.get("promotions") or []
    for p in promos:
        p.setdefault("source", source_tag)
    print(f"  Loaded {len(promos)} promotions from {path.name}")
    return promos


def merge(web: list[dict], email: list[dict]) -> list[dict]:
    index: dict[str, dict] = {}

    for promo in web:
        key = dedup_key(promo)
        promo["source"] = "web"
        index[key] = promo

    for promo in email:
        key = dedup_key(promo)
        if key in index:
            existing = index[key]
            # Keep higher confidence; mark as sourced from both
            if (promo.get("confidence_score") or 0) >= (existing.get("confidence_score") or 0):
                promo["source"] = "both"
                index[key] = promo
            else:
                existing["source"] = "both"
        else:
            promo["source"] = "email"
            index[key] = promo

    return list(index.values())


_MIN_CONFIDENCE = 0.65


def main() -> None:
    print("Loading promotions...")
    web   = load(WEB_FILE, "web")
    email = load(EMAIL_FILE, "email")

    merged = merge(web, email)

    # Drop anything below the confidence threshold
    before = len(merged)
    merged = [p for p in merged if (p.get("confidence_score") or 0) >= _MIN_CONFIDENCE]
    dropped = before - len(merged)

    # Stats
    by_source = {"web": 0, "email": 0, "both": 0}
    for p in merged:
        by_source[p.get("source", "web")] += 1

    output = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "promotion_count": len(merged),
        "promotions": merged,
    }
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"\nMerged {len(merged)} promotions -> {OUTPUT.name}")
    print(f"  Dropped (confidence < {_MIN_CONFIDENCE:.0%}): {dropped}")
    print(f"  Web only  : {by_source['web']}")
    print(f"  Email only: {by_source['email']}")
    print(f"  Both      : {by_source['both']}")


if __name__ == "__main__":
    main()
