from __future__ import annotations

import argparse
import csv
import json
import time
from pathlib import Path
from typing import Dict, List, Optional

from structured_parser import parse_text_file, save_failed_output, save_promotions_json, slugify


PROJECT_ROOT = Path(__file__).resolve().parents[1]
STRUCTURED_DIR = PROJECT_ROOT / "structured_outputs"


def safe_int(value: object, default: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return default


def resolve_path(path_value: str) -> Optional[Path]:
    if not path_value:
        return None

    path = Path(path_value)

    if not path.is_absolute():
        path = PROJECT_ROOT / path

    return path


def load_rows(csv_path: Path) -> List[Dict[str, str]]:
    with csv_path.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def row_quality(row: Dict[str, str]) -> str:
    return (
        row.get("quality_status")
        or row.get("source_quality_status")
        or row.get("status")
        or ""
    ).strip().lower()


def row_text_path(row: Dict[str, str]) -> str:
    for key in ["raw_text_path", "text_path", "file_path", "path", "filename"]:
        value = row.get(key)
        if value:
            return value
    return ""


def row_brand(row: Dict[str, str]) -> str:
    return row.get("brand") or row.get("Brand") or "Unknown"


def row_category(row: Dict[str, str]) -> Optional[str]:
    return row.get("category") or row.get("Category") or None


def total_keywords(row: Dict[str, str]) -> int:
    if "total_keyword_count" in row:
        return safe_int(row["total_keyword_count"])

    total = 0
    for key, value in row.items():
        if key.endswith("_count"):
            total += safe_int(value)
    return total


def text_length(row: Dict[str, str]) -> int:
    for key in ["text_length", "clean_text_length", "length"]:
        if key in row:
            return safe_int(row[key])
    return 0


def select_candidates(rows: List[Dict[str, str]], limit: int) -> List[Dict[str, str]]:
    usable_rows = []

    for row in rows:
        quality = row_quality(row)

        if quality and quality not in {"usable", "weak", "success"}:
            continue

        path_value = row_text_path(row)
        if not path_value:
            continue

        path = resolve_path(path_value)
        if path is None or not path.exists():
            continue

        usable_rows.append(row)

    usable_rows.sort(
        key=lambda row: (
            -total_keywords(row),
            -text_length(row),
            row_brand(row).lower(),
        )
    )

    return usable_rows[:limit]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Parse candidate local text files into structured promotion JSON."
    )

    parser.add_argument(
        "--csv",
        default="logs/text_candidates.csv",
        help="Candidate CSV path. Default: logs/text_candidates.csv",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=10,
        help="Maximum number of candidate files to parse.",
    )
    parser.add_argument(
        "--model",
        choices=["rule_based", "ollama"],
        default="rule_based",
        help="Extraction backend. Default: rule_based",
    )
    parser.add_argument(
        "--ollama-model",
        default="llama3.1:8b",
        help="Ollama model name (only used when --model ollama). Default: llama3.1:8b",
    )
    parser.add_argument(
        "--ollama-host",
        default="http://localhost:11434",
        help="Ollama host URL. Default: http://localhost:11434",
    )
    parser.add_argument(
        "--ollama-timeout",
        type=int,
        default=3600,
        help="Seconds before an Ollama request times out. Default: 3600",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-parse brands that already have a successful structured output.",
    )
    parser.add_argument(
        "--brand",
        type=str,
        default=None,
        help="Only parse candidates whose brand name contains this substring (case-insensitive).",
    )

    args = parser.parse_args()

    csv_path = resolve_path(args.csv)

    if csv_path is None or not csv_path.exists():
        raise FileNotFoundError(f"CSV file does not exist: {args.csv}")

    rows = load_rows(csv_path)
    if args.brand:
        rows = [r for r in rows if args.brand.lower() in row_brand(r).lower()]
    candidates = select_candidates(rows, limit=args.limit)

    parsed_count = 0
    skipped_count = 0
    failed_count = 0

    for row in candidates:
        brand = row_brand(row)
        category = row_category(row)
        path_value = row_text_path(row)
        input_path = resolve_path(path_value)

        if input_path is None or not input_path.exists():
            skipped_count += 1
            continue

        # Skip if the existing structured output was already parsed from this same raw text file.
        # A different filename means a fresh scrape came in — re-parse regardless of --force.
        if not args.force:
            existing = STRUCTURED_DIR / f"{slugify(brand)}.json"
            if existing.exists():
                try:
                    existing_source = Path(
                        json.loads(existing.read_text(encoding="utf-8")).get("source_path", "")
                    ).name
                    current_source = Path(path_value).name
                    if existing_source == current_source:
                        print(f"[SKIP] {brand}: content unchanged ({current_source})")
                        skipped_count += 1
                        continue
                except Exception:
                    pass  # unreadable existing file — fall through and re-parse

        try:
            promotions = parse_text_file(
                input_path=input_path,
                brand=brand,
                category=category,
                model_type=args.model,
                ollama_model=args.ollama_model,
                ollama_host=args.ollama_host,
                ollama_timeout=args.ollama_timeout,
            )
            output_path = save_promotions_json(
                promotions=promotions,
                brand=brand,
                input_path=input_path,
            )
            print(f"[OK] {brand} ({len(promotions)} deals): {output_path}")
            parsed_count += 1

        except Exception as e:
            # Retry once after a short pause before giving up
            print(f"[RETRY] {brand}: first attempt failed ({type(e).__name__}), retrying...")
            time.sleep(5)
            try:
                promotions = parse_text_file(
                    input_path=input_path,
                    brand=brand,
                    category=category,
                    model_type=args.model,
                    ollama_model=args.ollama_model,
                    ollama_host=args.ollama_host,
                    ollama_timeout=args.ollama_timeout,
                )
                output_path = save_promotions_json(
                    promotions=promotions,
                    brand=brand,
                    input_path=input_path,
                )
                print(f"[OK] {brand} ({len(promotions)} deals) [retry]: {output_path}")
                parsed_count += 1
            except Exception as e2:
                failed_count += 1
                failed_path = save_failed_output(
                    raw_data=dict(row),
                    brand=brand,
                    input_path=input_path,
                    error=e2,
                )
                print(f"[FAILED] {brand}: {failed_path}")

    print()
    print("Summary")
    print(f"Parsed:  {parsed_count}")
    print(f"Skipped: {skipped_count}")
    print(f"Failed:  {failed_count}")


if __name__ == "__main__":
    main()