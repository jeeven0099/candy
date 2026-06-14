"""
list_email_candidates.py — Scan email_text/*.meta.json, rank by deal signal
strength and visibility, and output logs/email_candidates.csv.

Visibility priority for ranking:
  private_user_offer   — highest (personal deals)
  member_offer         — medium
  public_general_offer — lower (likely already in web pipeline)
"""
from __future__ import annotations

import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EMAIL_TEXT_DIR = ROOT / "email_text"
LOGS_DIR = ROOT / "logs"
OUTPUT_CSV = LOGS_DIR / "email_candidates.csv"

_VISIBILITY_RANK = {
    "private_user_offer": 0,
    "member_offer": 1,
    "public_general_offer": 2,
    "unknown": 3,
}

FIELDNAMES = [
    "brand", "sender_email", "subject", "sent_at", "visibility",
    "total_keyword_count", "promo_codes", "discount_phrases",
    "text_length", "link_count", "text_path", "content_hash",
]


def main() -> None:
    metas = []
    seen_hashes: set[str] = set()

    for meta_path in sorted(EMAIL_TEXT_DIR.glob("*.meta.json")):
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except Exception:
            continue

        if not meta.get("deal_signal"):
            continue

        # Require at least one concrete retail signal — a promo code, a specific
        # % off / $ off phrase, or a private/member offer (already personal).
        # This filters finance newsletters, job alerts, and educational emails
        # that trip generic keywords like "save", "reward", "free" but never
        # contain an actual discount users can redeem.
        visibility = meta.get("visibility", "")
        has_concrete = (
            bool(meta.get("promo_codes"))
            or bool(meta.get("discount_phrases"))
            or visibility in ("private_user_offer", "member_offer")
        )
        if not has_concrete:
            continue

        h = meta.get("content_hash", "")
        if h in seen_hashes:
            continue
        seen_hashes.add(h)

        text_path = ROOT / meta.get("text_path", "")
        if not text_path.exists():
            continue

        metas.append(meta)

    # Sort: visibility rank asc, then keyword count desc, then text length desc
    metas.sort(key=lambda m: (
        _VISIBILITY_RANK.get(m.get("visibility", "unknown"), 3),
        -m.get("total_keyword_count", 0),
        -m.get("text_length", 0),
    ))

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    with OUTPUT_CSV.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDNAMES, extrasaction="ignore")
        writer.writeheader()
        for m in metas:
            writer.writerow({
                **m,
                "promo_codes": "|".join(m.get("promo_codes") or []),
                "discount_phrases": "|".join(m.get("discount_phrases") or []),
            })

    print(f"Found {len(metas)} email candidates -> {OUTPUT_CSV}")
    by_vis: dict[str, int] = {}
    for m in metas:
        v = m.get("visibility", "unknown")
        by_vis[v] = by_vis.get(v, 0) + 1
    for v, n in sorted(by_vis.items(), key=lambda x: _VISIBILITY_RANK.get(x[0], 9)):
        print(f"  {v}: {n}")


if __name__ == "__main__":
    main()
