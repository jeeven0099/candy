"""
generate_review_csv.py — Build logs/promotion_review.csv from normalized_outputs/

Columns:
  brand, promotion_title, promotion_type, discount_type, discount_value,
  requires_membership, membership_name, requires_app, minimum_spend,
  redemption_method, deal_scope, confidence_score, status, needs_review,
  source_path
"""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NORMALIZED_DIR = ROOT / "normalized_outputs"
LOGS_DIR = ROOT / "logs"
OUTPUT_CSV = LOGS_DIR / "promotion_review.csv"

CSV_COLUMNS = [
    "brand",
    "promotion_title",
    "promotion_type",
    "discount_type",
    "discount_value",
    "requires_membership",
    "membership_name",
    "requires_app",
    "minimum_spend",
    "redemption_method",
    "deal_scope",
    "confidence_score",
    "status",
    "needs_review",
    "source_path",
]

_NEEDS_REVIEW_STATUSES = {"expired", "needs_review", "low_confidence"}

_STATUS_SORT_ORDER = {
    "expired":        0,
    "low_confidence": 1,
    "needs_review":   2,
    "online_only":    3,
    "probably_active": 4,
    "active":         5,
}


def promo_to_row(promo: dict) -> dict:
    status = promo.get("status", "needs_review")
    return {
        "brand":              promo.get("brand", ""),
        "promotion_title":    promo.get("promotion_title", ""),
        "promotion_type":     promo.get("promotion_type", "unknown"),
        "discount_type":      promo.get("discount_type", "unknown"),
        "discount_value":     promo.get("discount_value") or "",
        "requires_membership": promo.get("requires_membership", False),
        "membership_name":    promo.get("membership_name") or "",
        "requires_app":       promo.get("requires_app", False),
        "minimum_spend":      promo.get("minimum_spend") or "",
        "redemption_method":  promo.get("redemption_method", "unknown"),
        "deal_scope":         promo.get("deal_scope", "unknown"),
        "confidence_score":   promo.get("confidence_score", 0.0),
        "status":             status,
        "needs_review":       status in _NEEDS_REVIEW_STATUSES,
        "source_path":        promo.get("source_path", ""),
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate logs/promotion_review.csv from normalized_outputs/"
    )
    parser.add_argument("--input-dir", type=str, default=None, help="Override input directory")
    parser.add_argument("--output", type=str, default=None, help="Override output CSV path")
    parser.add_argument("--brand", type=str, default=None, help="Filter by brand substring")
    parser.add_argument(
        "--needs-review-only",
        action="store_true",
        help="Only include rows where needs_review=True",
    )
    args = parser.parse_args()

    input_dir = Path(args.input_dir) if args.input_dir else NORMALIZED_DIR
    output_path = Path(args.output) if args.output else OUTPUT_CSV
    output_path.parent.mkdir(parents=True, exist_ok=True)

    files = sorted(f for f in input_dir.glob("*.json") if f.is_file())
    if args.brand:
        files = [f for f in files if args.brand.lower() in f.stem.lower()]

    rows = []
    brand_count = 0

    for path in files:
        try:
            data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
        except Exception as exc:
            print(f"  [ERROR] {path.name}: {exc}")
            continue

        promotions = data.get("promotions", [])
        if not isinstance(promotions, list):
            continue

        brand_count += 1
        for promo in promotions:
            if not isinstance(promo, dict):
                continue
            row = promo_to_row(promo)
            if args.needs_review_only and not row["needs_review"]:
                continue
            rows.append(row)

    # Sort: by status priority, then brand name, then confidence desc
    rows.sort(key=lambda r: (
        _STATUS_SORT_ORDER.get(r["status"], 99),
        r["brand"].lower(),
        -float(r["confidence_score"] or 0),
    ))

    with output_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)

    # Summary
    by_status: dict[str, int] = {}
    for r in rows:
        by_status[r["status"]] = by_status.get(r["status"], 0) + 1

    print(f"\nWrote {len(rows)} promotions from {brand_count} brands -> {output_path}")
    print("\nBreakdown by status:")
    for status in sorted(by_status, key=lambda s: _STATUS_SORT_ORDER.get(s, 99)):
        print(f"  {status:<18} {by_status[status]}")


if __name__ == "__main__":
    main()
