from __future__ import annotations

import argparse
import csv
import gc
import json
import re
import time
from pathlib import Path
from typing import Dict, List, Optional

from structured_parser import parse_text_file, save_failed_output, save_promotions_json, slugify


PROJECT_ROOT = Path(__file__).resolve().parents[1]
STRUCTURED_DIR = PROJECT_ROOT / "structured_outputs"
LOGS_DIR = PROJECT_ROOT / "logs"

_FAIL_RETRY_RE = re.compile(r'^\[(?:FAILED|RETRY)\] (.+?):', re.MULTILINE)


def _brands_with_failures() -> set[str]:
    """Return lowercase brand names that ever appeared as [FAILED] or [RETRY] in any pipeline log."""
    tainted: set[str] = set()
    for log in LOGS_DIR.glob("pipeline_*.log"):
        try:
            text = log.read_text(encoding="utf-8", errors="replace")
            for m in _FAIL_RETRY_RE.finditer(text):
                tainted.add(m.group(1).strip().lower())
        except Exception:
            pass
    return tainted


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


def _unload_ollama_model(host: str, model: str) -> None:
    """POST keep_alive=0 to unload the model from VRAM between batches."""
    try:
        import requests as _req
        _req.post(
            f"{host}/api/generate",
            json={"model": model, "keep_alive": 0},
            timeout=30,
        )
    except Exception:
        pass


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
        choices=["rule_based", "ollama", "gemini", "groq"],
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
        "--gemini-model",
        default="gemini-2.0-flash",
        help="Gemini model name (only used when --model gemini). Default: gemini-2.0-flash",
    )
    parser.add_argument(
        "--gemini-api-key",
        default=None,
        help="Google AI Studio API key (falls back to GEMINI_API_KEY env var).",
    )
    parser.add_argument(
        "--groq-model",
        default="llama-3.3-70b-versatile",
        help="Groq model name (only used when --model groq). Default: llama-3.3-70b-versatile",
    )
    parser.add_argument(
        "--groq-api-key",
        default=None,
        help="Groq API key (falls back to GROQ_API_KEY env var).",
    )
    parser.add_argument(
        "--cloud-timeout",
        type=int,
        default=120,
        help="Seconds before a cloud model request times out. Default: 120",
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
    parser.add_argument(
        "--failed-only",
        action="store_true",
        help="Skip brands already attempted this run (success or failure). Only processes brands with no output at all.",
    )
    parser.add_argument(
        "--clean-only",
        action="store_true",
        help="Only parse brands that have never had a [FAILED] or [RETRY] in any past pipeline log. Useful for benchmarking clean LLM timing.",
    )
    parser.add_argument(
        "--gc-interval",
        type=int,
        default=10,
        help="Call gc.collect() every N LLM-processed brands (0 = disabled). Default: 10",
    )
    parser.add_argument(
        "--ollama-restart-interval",
        type=int,
        default=25,
        help="Unload Ollama model every N brands to free VRAM (0 = disabled). Default: 25",
    )

    args = parser.parse_args()

    csv_path = resolve_path(args.csv)

    if csv_path is None or not csv_path.exists():
        raise FileNotFoundError(f"CSV file does not exist: {args.csv}")

    rows = load_rows(csv_path)
    if args.brand:
        rows = [r for r in rows if args.brand.lower() in row_brand(r).lower()]
    candidates = select_candidates(rows, limit=args.limit)

    _tainted_brands: set[str] = _brands_with_failures() if args.clean_only else set()
    if args.clean_only:
        print(f"[INFO] --clean-only: {len(_tainted_brands)} brands excluded due to prior FAILED/RETRY history")

    parsed_count = 0
    skipped_count = 0
    failed_count = 0
    llm_calls = 0
    parse_durations: list[float] = []

    for row in candidates:
        brand = row_brand(row)
        category = row_category(row)
        path_value = row_text_path(row)
        input_path = resolve_path(path_value)

        if input_path is None or not input_path.exists():
            skipped_count += 1
            continue

        # --clean-only: skip any brand that ever had a [FAILED] or [RETRY] in past logs.
        if args.clean_only:
            if brand.lower() in _tainted_brands:
                print(f"[SKIP] {brand}: has prior FAILED/RETRY history (--clean-only)")
                skipped_count += 1
                continue

        # --failed-only: skip any brand already attempted this run (success or failure).
        # Only processes brands with no output at all — i.e. never attempted.
        if args.failed_only:
            slug = slugify(brand)
            if (STRUCTURED_DIR / f"{slug}.json").exists() or \
               (STRUCTURED_DIR / "failed" / f"{slug}.json").exists():
                print(f"[SKIP] {brand}: already attempted (--failed-only)")
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

        # Proactive memory relief before each LLM call batch
        llm_calls += 1
        if args.gc_interval and llm_calls % args.gc_interval == 0:
            gc.collect()
            print(f"[GC] gc.collect() before brand #{llm_calls}")
        if args.model == "ollama" and args.ollama_restart_interval and llm_calls % args.ollama_restart_interval == 0:
            print(f"[OLLAMA] Unloading model before brand #{llm_calls} (memory relief)...")
            _unload_ollama_model(args.ollama_host, args.ollama_model)
            time.sleep(3)

        try:
            input_chars = len(input_path.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            input_chars = 0

        t0 = time.time()
        try:
            promotions = parse_text_file(
                input_path=input_path,
                brand=brand,
                category=category,
                model_type=args.model,
                ollama_model=args.ollama_model,
                ollama_host=args.ollama_host,
                ollama_timeout=args.ollama_timeout,
                gemini_model=args.gemini_model,
                gemini_api_key=args.gemini_api_key,
                groq_model=args.groq_model,
                groq_api_key=args.groq_api_key,
                cloud_timeout=args.cloud_timeout,
            )
            elapsed = time.time() - t0
            parse_durations.append(elapsed)

            # Don't regress: if the new parse found 0 deals but the previous
            # structured output had deals, keep the old file and warn.
            if not promotions:
                existing = STRUCTURED_DIR / f"{slugify(brand)}.json"
                if existing.exists():
                    try:
                        old_deals = json.loads(existing.read_text(encoding="utf-8")).get("promotions", [])
                        if old_deals:
                            print(f"[KEPT] {brand}: new parse found 0 deals but {len(old_deals)} old deal(s) preserved ({elapsed:.0f}s, {input_chars}c)")
                            parsed_count += 1
                            continue
                    except Exception:
                        pass

            output_path = save_promotions_json(
                promotions=promotions,
                brand=brand,
                input_path=input_path,
            )
            print(f"[OK] {brand} ({len(promotions)} deals, {elapsed:.0f}s, {input_chars}c): {output_path}")
            parsed_count += 1

        except Exception as e:
            elapsed = time.time() - t0
            is_timeout = 'timed out' in str(e).lower()
            if is_timeout:
                # Timeouts won't resolve on retry with the same input — fail fast.
                failed_count += 1
                failed_path = save_failed_output(
                    raw_data=dict(row),
                    brand=brand,
                    input_path=input_path,
                    error=e,
                )
                print(f"[FAILED] {brand}: timeout after {elapsed:.0f}s ({input_chars}c), skipping retry — {failed_path}")
                continue

            # Non-timeout failures (JSON parse errors, etc.) — retry once
            print(f"[RETRY] {brand}: first attempt failed after {elapsed:.0f}s ({input_chars}c, {type(e).__name__}), retrying...")
            time.sleep(5)
            t0 = time.time()
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
                elapsed = time.time() - t0
                parse_durations.append(elapsed)

                # Same don't-regress guard on retry path
                if not promotions:
                    existing = STRUCTURED_DIR / f"{slugify(brand)}.json"
                    if existing.exists():
                        try:
                            old_deals = json.loads(existing.read_text(encoding="utf-8")).get("promotions", [])
                            if old_deals:
                                print(f"[KEPT] {brand}: retry found 0 deals but {len(old_deals)} old deal(s) preserved ({elapsed:.0f}s)")
                                parsed_count += 1
                                continue
                        except Exception:
                            pass

                output_path = save_promotions_json(
                    promotions=promotions,
                    brand=brand,
                    input_path=input_path,
                )
                print(f"[OK] {brand} ({len(promotions)} deals, {elapsed:.0f}s, {input_chars}c) [retry]: {output_path}")
                parsed_count += 1
            except Exception as e2:
                elapsed = time.time() - t0
                failed_count += 1
                failed_path = save_failed_output(
                    raw_data=dict(row),
                    brand=brand,
                    input_path=input_path,
                    error=e2,
                )
                print(f"[FAILED] {brand} after {elapsed:.0f}s ({input_chars}c): {failed_path}")

    print()
    print("Summary")
    print(f"Parsed:  {parsed_count}")
    print(f"Skipped: {skipped_count}")
    print(f"Failed:  {failed_count}")
    if parse_durations:
        avg = sum(parse_durations) / len(parse_durations)
        print(f"LLM timing: avg {avg:.0f}s  min {min(parse_durations):.0f}s  max {max(parse_durations):.0f}s  (n={len(parse_durations)})")


if __name__ == "__main__":
    main()