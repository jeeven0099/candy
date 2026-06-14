"""
normalize_email_promotions.py — Normalize structured_outputs/email/*.json
into email_promotions.json for the Flutter app.

Reuses the web normalizer's fix passes. Adds email-specific fields.
Private offers are kept as-is (high confidence, personal).
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

_SRC = Path(__file__).resolve().parents[2] / "src"
sys.path.insert(0, str(_SRC))

from normalize_promotions import (  # noqa: E402
    deduplicate,
    fix_confidence,
    fix_deal_scope,
    fix_free_shipping,
    fix_promotion_title,
    fix_redemption_method,
    fix_rewards_program_title,
    fix_subscription_pricing,
    fix_unknown_type_from_title,
    fix_zero_pct_discount,
    is_placeholder,
    compute_status,
)

ROOT = Path(__file__).resolve().parents[1]
STRUCTURED_DIR = ROOT / "structured_outputs" / "email"
OUTPUT_FILE = ROOT.parent / "email_promotions.json"   # sibling of merged_promotions.json


def _best_source_url(promo: dict) -> Optional[str]:
    """Try to find a click-through URL from the email links."""
    links = promo.get("links") or []
    for link in links:
        if any(skip in link for skip in ("unsubscribe", "optout", "privacy", "manage")):
            continue
        if link.startswith("http"):
            return link
    return None


def normalize_file(path: Path, now: datetime) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
    brand = data.get("brand", "")
    promos = data.get("promotions") or []
    if not isinstance(promos, list):
        return []

    normalized = []
    for promo in promos:
        if not isinstance(promo, dict) or is_placeholder(promo):
            continue

        # Preserve email-specific fields across normalization
        visibility = promo.get("visibility", "unknown")
        sender_email = promo.get("sender_email")
        email_subject = promo.get("email_subject")
        email_date = promo.get("email_date")

        promo["brand"] = brand
        promo["source_type"] = "email"

        promo = fix_zero_pct_discount(promo)
        promo = fix_free_shipping(promo)
        promo = fix_subscription_pricing(promo)
        promo = fix_unknown_type_from_title(promo)
        promo = fix_rewards_program_title(promo)
        promo = fix_promotion_title(promo, brand)
        promo = fix_redemption_method(promo)
        promo = fix_deal_scope(promo)

        # Private offers already have high specificity — don't penalise confidence
        if visibility != "private_user_offer":
            promo = fix_confidence(promo)

        promo["status"] = compute_status(promo, now)

        # Re-attach email fields (normalization passes may not touch them)
        promo["visibility"] = visibility
        promo["sender_email"] = sender_email
        promo["email_subject"] = email_subject
        promo["email_date"] = email_date

        normalized.append(promo)

    return deduplicate(normalized)


def main() -> None:
    now = datetime.now(timezone.utc)
    files = sorted(f for f in STRUCTURED_DIR.glob("*.json") if f.is_file())

    all_promos: list[dict] = []
    brand_count = 0

    for path in files:
        try:
            promos = normalize_file(path, now)
            all_promos.extend(promos)
            brand_count += 1
            print(f"  {path.stem}: {len(promos)} promotions")
        except Exception as exc:
            print(f"  [ERROR] {path.stem}: {exc}")

    by_visibility: dict[str, int] = {}
    for p in all_promos:
        v = p.get("visibility", "unknown")
        by_visibility[v] = by_visibility.get(v, 0) + 1

    output = {
        "generated_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "brand_count": brand_count,
        "promotion_count": len(all_promos),
        "promotions": all_promos,
    }
    OUTPUT_FILE.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"\nWrote {len(all_promos)} email promotions from {brand_count} brands -> {OUTPUT_FILE}")
    for v, n in sorted(by_visibility.items()):
        print(f"  {v}: {n}")


if __name__ == "__main__":
    main()
