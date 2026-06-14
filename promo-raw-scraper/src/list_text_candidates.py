from __future__ import annotations

import csv
import re
from pathlib import Path
from typing import Dict, List, Tuple


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_TEXT_DIR = PROJECT_ROOT / "raw_text"
LOGS_DIR = PROJECT_ROOT / "logs"
SUMMARY_CSV = LOGS_DIR / "raw_data_summary.csv"
OUTPUT_CSV = LOGS_DIR / "text_candidates.csv"


KEYWORDS = [
    "reward",
    "offer",
    "deal",
    "promo",
    "discount",
    "valid",
    "expires",
    "birthday",
    "membership",
    "app",
    # sale-page vocabulary
    "sale",
    "off",
    "clearance",
    "savings",
    "coupon",
    "free",
    "redeem",
    "code",
]


def count_keyword(text: str, keyword: str) -> int:
    pattern = rf"\b{re.escape(keyword)}\b"
    return len(re.findall(pattern, text.lower()))


def classify_text(text_length: int) -> Tuple[str, str]:
    if text_length >= 300:
        return "usable", "ready_for_structured_parsing"
    return "too_short", "ignore_or_replace_source_later"


def read_summary_rows() -> List[Dict[str, str]]:
    if not SUMMARY_CSV.exists():
        return []

    with SUMMARY_CSV.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def find_text_path(row: Dict[str, str]) -> Path | None:
    candidate_keys = [
        "raw_text_path",
        "text_path",
        "file_path",
        "path",
        "filename",
        "file",
    ]

    for key in candidate_keys:
        value = row.get(key)
        if not value:
            continue

        path = Path(value)
        if not path.is_absolute():
            path = PROJECT_ROOT / path

        if path.exists():
            return path

    brand = row.get("brand", "").strip().lower()
    if brand:
        normalized = re.sub(r"[^a-z0-9]+", "_", brand).strip("_")
        matches = list(RAW_TEXT_DIR.glob(f"{normalized}*.txt"))
        if matches:
            return matches[0]

    return None


def build_candidate_row(row: Dict[str, str]) -> Dict[str, object]:
    brand = row.get("brand", "")
    category = row.get("category", "")

    text_path = find_text_path(row)

    if text_path is None:
        return {
            "brand": brand,
            "category": category,
            "raw_text_path": "",
            "text_length": 0,
            "line_count": 0,
            **{f"{kw}_count": 0 for kw in KEYWORDS},
            "total_keyword_count": 0,
            "quality_status": "file_error",
            "next_action": "check_file",
        }

    try:
        text = text_path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return {
            "brand": brand,
            "category": category,
            "raw_text_path": str(text_path.relative_to(PROJECT_ROOT)),
            "text_length": 0,
            "line_count": 0,
            **{f"{kw}_count": 0 for kw in KEYWORDS},
            "total_keyword_count": 0,
            "quality_status": "file_error",
            "next_action": "check_file",
        }

    counts = {f"{kw}_count": count_keyword(text, kw) for kw in KEYWORDS}
    total_keyword_count = sum(counts.values())

    text_length = len(text)
    line_count = len(text.splitlines())
    quality_status, next_action = classify_text(text_length)

    return {
        "brand": brand,
        "category": category,
        "raw_text_path": str(text_path.relative_to(PROJECT_ROOT)),
        "text_length": text_length,
        "line_count": line_count,
        **counts,
        "total_keyword_count": total_keyword_count,
        "quality_status": quality_status,
        "next_action": next_action,
    }


def deduplicate_by_brand(rows: List[Dict[str, object]]) -> List[Dict[str, object]]:
    """Keep only the most recently scraped file per brand (latest timestamp in filename)."""
    best: Dict[str, Dict[str, object]] = {}
    for row in rows:
        brand = str(row.get("brand", "")).strip()
        if not brand:
            continue
        path = str(row.get("raw_text_path", ""))
        existing = best.get(brand)
        if existing is None:
            best[brand] = row
        else:
            existing_path = str(existing.get("raw_text_path", ""))
            # String comparison works because filenames embed ISO timestamps
            if path and (not existing_path or path > existing_path):
                best[brand] = row
    return list(best.values())


def sort_key(row: Dict[str, object]) -> Tuple[int, int, int]:
    status_priority = {
        "usable": 0,
        "weak": 1,
        "too_short": 2,
        "file_error": 3,
        "unknown": 4,
    }

    return (
        status_priority.get(str(row["quality_status"]), 99),
        -int(row["total_keyword_count"]),
        -int(row["text_length"]),
    )


def main() -> None:
    LOGS_DIR.mkdir(parents=True, exist_ok=True)

    summary_rows = read_summary_rows()

    if not summary_rows:
        print(f"No summary rows found at {SUMMARY_CSV}")
        return

    candidate_rows = [build_candidate_row(row) for row in summary_rows]
    candidate_rows = deduplicate_by_brand(candidate_rows)
    candidate_rows.sort(key=sort_key)

    fieldnames = [
        "brand",
        "category",
        "raw_text_path",
        "text_length",
        "line_count",
        *[f"{kw}_count" for kw in KEYWORDS],
        "total_keyword_count",
        "quality_status",
        "next_action",
    ]

    with OUTPUT_CSV.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(candidate_rows)

    print(f"Wrote {len(candidate_rows)} candidates to {OUTPUT_CSV}")

    print("\nTop 20 text candidates:")
    for i, row in enumerate(candidate_rows[:20], start=1):
        print(
            f"{i:02d}. {row['brand']} | "
            f"{row['quality_status']} | "
            f"{row['text_length']} chars | "
            f"{row['total_keyword_count']} keyword hits | "
            f"{row['raw_text_path']}"
        )


if __name__ == "__main__":
    main()