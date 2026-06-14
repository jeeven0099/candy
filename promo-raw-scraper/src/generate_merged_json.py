"""
generate_merged_json.py — Merge all normalized_outputs/*.json into a single
queryable merged_promotions.json for app consumption.
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NORMALIZED_DIR = ROOT / "normalized_outputs"
OUTPUT_FILE = ROOT / "merged_promotions.json"

_ACTIVE_STATUSES = {"active", "probably_active", "online_only"}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Merge normalized_outputs/ into a single merged_promotions.json"
    )
    parser.add_argument(
        "--active-only",
        action="store_true",
        help="Include only active/probably_active/online_only promotions",
    )
    parser.add_argument(
        "--output",
        type=str,
        default=None,
        help=f"Output file path. Default: {OUTPUT_FILE}",
    )
    args = parser.parse_args()

    output_path = Path(args.output) if args.output else OUTPUT_FILE
    files = sorted(f for f in NORMALIZED_DIR.glob("*.json") if f.is_file())

    all_promotions: list[dict] = []
    brand_count = 0
    warn_count = 0

    for path in files:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            promos = data.get("promotions") or []
            if args.active_only:
                promos = [p for p in promos if p.get("status") in _ACTIVE_STATUSES]
            all_promotions.extend(promos)
            brand_count += 1
        except Exception as exc:
            print(f"  [WARN] {path.stem}: {exc}")
            warn_count += 1

    merged = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "brand_count": brand_count,
        "promotion_count": len(all_promotions),
        "promotions": all_promotions,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(merged, indent=2, ensure_ascii=False), encoding="utf-8")

    filter_note = " (active only)" if args.active_only else ""
    print(f"Merged {len(all_promotions)} promotions{filter_note} from {brand_count} brands -> {output_path}")
    if warn_count:
        print(f"  ({warn_count} file(s) skipped due to errors)")


if __name__ == "__main__":
    main()
