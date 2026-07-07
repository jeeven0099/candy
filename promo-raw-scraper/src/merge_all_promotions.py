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

try:
    from langdetect import detect_langs as _detect_langs
    from langdetect.detector_factory import DetectorFactory as _DetectorFactory
    _DetectorFactory.seed = 0  # make detection deterministic
    _LANGDETECT_AVAILABLE = True
except ImportError:
    _LANGDETECT_AVAILABLE = False
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

# Fast character-level pre-check before running langdetect.
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
    desc = promo.get("short_summary") or promo.get("description") or ""
    combined = f"{title} {desc}".strip()

    # Fast path: unambiguous non-English characters.
    if _NON_ENGLISH_RE.search(combined):
        return False

    if not _LANGDETECT_AVAILABLE:
        return True

    try:
        # Check title alone first with a lower bar — catches "60-80% de Descuento en
        # Rebajas!" even when the LLM wrote an English summary that dilutes the signal.
        if len(title) >= 10:
            title_langs = _detect_langs(title)
            top = title_langs[0]
            if top.lang != "en" and top.prob >= 0.85:
                return False

        # Full combined check for anything that slips through.
        if len(combined) >= 15:
            langs = _detect_langs(combined)
            top = langs[0]
            # Only reject if confidently non-English. Short ambiguous strings
            # (e.g. "40% off") often score 0.5-0.7 for random languages — keep those.
            if top.lang != "en" and top.prob >= 0.90:
                return False
    except Exception:
        pass  # uncertain — keep rather than silently drop

    return True


def main() -> None:
    print("Loading promotions...")
    web = load(WEB_FILE, "web")
    # Email pipeline disabled — deals came from personal inbox, not suitable for multi-user beta.
    # To re-enable: replace [] with load(EMAIL_FILE, "email")

    merged = merge_national(web, [])

    # Drop non-English promotions
    before = len(merged)
    merged = [p for p in merged if _is_english(p)]
    dropped_non_english = before - len(merged)

    # Drop low-confidence promotions
    before = len(merged)
    merged = [p for p in merged if (p.get("confidence_score") or 0) >= _MIN_CONFIDENCE]
    dropped_confidence = before - len(merged)

    # Drop expired promotions (end_date is in the past)
    before = len(merged)
    merged = [p for p in merged if not _is_expired(p)]
    dropped_expired = before - len(merged)

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
    print(f"  Dropped non-English                    : {dropped_non_english}")
    print(f"  Dropped low-confidence (< {_MIN_CONFIDENCE:.0%})      : {dropped_confidence}")
    print(f"  Dropped expired (end_date in the past) : {dropped_expired}")
    for src, count in sorted(by_source.items()):
        print(f"  {src}: {count}")


if __name__ == "__main__":
    main()
