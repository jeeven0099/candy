"""
merge_all_promotions.py — Merge web, email, and local neighborhood promotions
into a single all_promotions.json for the Flutter app.

Deduplication key: (brand_slug, title_slug, discount_type)
When duplicates exist, keep the one with higher confidence_score.
Adds a 'source' field: 'web' | 'email' | 'both' | 'local_neighborhood'
Local promotions are kept separate — they don't dedup against web/email since
local businesses are distinct from national brands.
"""
from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WEB_FILE   = ROOT / "merged_promotions.json"
EMAIL_FILE = ROOT / "email_promotions.json"
LOCAL_FILE = ROOT / "local_promotions.json"
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


def merge_national(web: list[dict], email: list[dict]) -> list[dict]:
    index: dict[str, dict] = {}

    for promo in web:
        key = dedup_key(promo)
        promo["source"] = "web"
        index[key] = promo

    for promo in email:
        key = dedup_key(promo)
        if key in index:
            existing = index[key]
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
_MIN_LOCAL_CONFIDENCE = 0.85  # stricter gate for local deals

# Characters that unambiguously indicate non-English text in a deal title.
# ¡ ¿ are Spanish-only punctuation; ñ is essentially absent from English.
_NON_ENGLISH_RE = re.compile(r'[¡¿ñÑ]')


def _is_expired(promo: dict) -> bool:
    end_date = promo.get("end_date")
    if not end_date:
        return False
    try:
        end = datetime.strptime(end_date[:10], "%Y-%m-%d").replace(tzinfo=timezone.utc)
        return end < datetime.now(timezone.utc)
    except ValueError:
        return False


def _is_english(promo: dict) -> bool:
    title = promo.get("promotion_title") or ""
    if _NON_ENGLISH_RE.search(title):
        return False
    desc = promo.get("short_summary") or promo.get("description") or ""
    if _NON_ENGLISH_RE.search(desc):
        return False
    return True


def main() -> None:
    print("Loading promotions...")
    web   = load(WEB_FILE, "web")
    # Email pipeline disabled — deals came from personal inbox, not suitable for multi-user beta.
    # To re-enable: replace [] with load(EMAIL_FILE, "email")
    local = load(LOCAL_FILE, "local_neighborhood")

    national = merge_national(web, [])

    # Drop non-English national promotions
    before = len(national)
    national = [p for p in national if _is_english(p)]
    dropped_non_english = before - len(national)

    # Drop low-confidence national promotions
    before = len(national)
    national = [p for p in national if (p.get("confidence_score") or 0) >= _MIN_CONFIDENCE]
    dropped_national = before - len(national)

    # Drop expired national promotions (end_date is in the past)
    before = len(national)
    national = [p for p in national if not _is_expired(p)]
    dropped_expired = before - len(national)

    # Drop low-confidence local promotions (stricter threshold already applied by scraper,
    # but enforce again here in case the file was manually edited)
    before_local = len(local)
    local = [p for p in local if (p.get("confidence_score") or 0) >= _MIN_LOCAL_CONFIDENCE]
    dropped_local = before_local - len(local)

    merged = national + local

    # Stats
    by_source: dict[str, int] = {}
    for p in merged:
        src = p.get("source", "web")
        by_source[src] = by_source.get(src, 0) + 1

    output = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "promotion_count": len(merged),
        "promotions": merged,
    }
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"\nMerged {len(merged)} promotions -> {OUTPUT.name}")
    print(f"  Dropped non-English                              : {dropped_non_english}")
    print(f"  Dropped national (confidence < {_MIN_CONFIDENCE:.0%})           : {dropped_national}")
    print(f"  Dropped expired  (end_date in the past)          : {dropped_expired}")
    print(f"  Dropped local    (confidence < {_MIN_LOCAL_CONFIDENCE:.0%})           : {dropped_local}")
    for src, count in sorted(by_source.items()):
        print(f"  {src}: {count}")


if __name__ == "__main__":
    main()
