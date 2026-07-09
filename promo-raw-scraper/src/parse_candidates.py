from __future__ import annotations

import argparse
import csv
import gc
import json
import re
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional

from structured_parser import parse_text_file, save_failed_output, save_promotions_json, slugify


PROJECT_ROOT = Path(__file__).resolve().parents[1]
STRUCTURED_DIR = PROJECT_ROOT / "structured_outputs"
LOGS_DIR = PROJECT_ROOT / "logs"

_FAIL_RETRY_RE = re.compile(r'^\[(?:FAILED|RETRY)\] (.+?):', re.MULTILINE)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _is_rate_limit_error(e: Exception) -> bool:
    cls = type(e).__name__
    msg = str(e).lower()
    return (
        cls == "RateLimitError"
        or "rate_limit" in cls.lower()
        or "resourceexhausted" in cls.lower()
        or "429" in msg
        or "quota" in msg
        or "rate limit" in msg
        or "resource exhausted" in msg
    )


def _brands_with_failures() -> set[str]:
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
    try:
        import requests as _req
        _req.post(
            f"{host}/api/generate",
            json={"model": model, "keep_alive": 0},
            timeout=30,
        )
    except Exception:
        pass


# ── Per-brand processor ───────────────────────────────────────────────────────

def _process_brand(
    row: dict,
    model_type: str,
    args,
    tainted_brands: set[str],
    counters: dict,
    lock: threading.Lock,
    print_lock: threading.Lock,
) -> str:
    """
    Process one brand with the given model. Returns 'parsed', 'skipped', or 'failed'.
    Thread-safe: all shared state is updated under lock; all prints go through print_lock.
    """
    brand    = row_brand(row)
    category = row_category(row)
    path_value = row_text_path(row)
    input_path = resolve_path(path_value)

    def tprint(msg: str) -> None:
        with print_lock:
            print(msg, flush=True)

    if input_path is None or not input_path.exists():
        with lock:
            counters["skipped"] += 1
        return "skipped"

    if args.clean_only and brand.lower() in tainted_brands:
        tprint(f"[SKIP] {brand}: prior FAILED/RETRY history (--clean-only)")
        with lock:
            counters["skipped"] += 1
        return "skipped"

    if args.failed_only:
        slug = slugify(brand)
        if (STRUCTURED_DIR / f"{slug}.json").exists() or \
           (STRUCTURED_DIR / "failed" / f"{slug}.json").exists():
            tprint(f"[SKIP] {brand}: already attempted (--failed-only)")
            with lock:
                counters["skipped"] += 1
            return "skipped"

    if not args.force:
        existing = STRUCTURED_DIR / f"{slugify(brand)}.json"
        if existing.exists():
            try:
                existing_source = Path(
                    json.loads(existing.read_text(encoding="utf-8")).get("source_path", "")
                ).name
                current_source = Path(path_value).name
                if existing_source == current_source:
                    tprint(f"[SKIP] {brand}: content unchanged ({current_source})")
                    with lock:
                        counters["skipped"] += 1
                    return "skipped"
            except Exception:
                pass

    try:
        input_chars = len(input_path.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        input_chars = 0

    def call_parse(mt: str) -> list:
        return parse_text_file(
            input_path=input_path,
            brand=brand,
            category=category,
            model_type=mt,
            ollama_model=args.ollama_model,
            ollama_host=args.ollama_host,
            ollama_timeout=args.ollama_timeout,
            gemini_model=args.gemini_model,
            gemini_api_key=args.gemini_api_key,
            groq_model=args.groq_model,
            groq_api_key=args.groq_api_key,
            cloud_timeout=args.cloud_timeout,
        )

    def save_result(promotions: list, elapsed: float, tag: str) -> None:
        existing = STRUCTURED_DIR / f"{slugify(brand)}.json"
        if not promotions and existing.exists():
            try:
                old_deals = json.loads(existing.read_text(encoding="utf-8")).get("promotions", [])
                if old_deals:
                    tprint(
                        f"[KEPT] {brand}: 0 new deals, {len(old_deals)} old deal(s) preserved"
                        f" ({elapsed:.0f}s, {input_chars}c){tag}"
                    )
                    return
            except Exception:
                pass
        output_path = save_promotions_json(promotions=promotions, brand=brand, input_path=input_path)
        tprint(f"[OK] {brand} ({len(promotions)} deals, {elapsed:.0f}s, {input_chars}c){tag}: {output_path}")

    t0 = time.time()
    try:
        promotions = call_parse(model_type)
        elapsed = time.time() - t0
        save_result(promotions, elapsed, f" [{model_type}]")
        with lock:
            counters["parsed"] += 1
            counters["durations"].append(elapsed)
        return "parsed"

    except Exception as e:
        elapsed = time.time() - t0

        # Rate limit in parallel mode: log as quota and skip (Ollama is already busy)
        if _is_rate_limit_error(e):
            tprint(
                f"[QUOTA] {brand}: {model_type} quota hit after {elapsed:.0f}s"
                f" — skipped (re-run this brand with --model ollama)"
            )
            with lock:
                counters["quota"] = counters.get("quota", 0) + 1
                counters["skipped"] += 1
            return "skipped"

        is_timeout = "timed out" in str(e).lower()
        if is_timeout:
            failed_path = save_failed_output(
                raw_data=dict(row), brand=brand, input_path=input_path, error=e
            )
            tprint(f"[FAILED] {brand}: timeout after {elapsed:.0f}s ({input_chars}c) — {failed_path}")
            with lock:
                counters["failed"] += 1
            return "failed"

        # Non-timeout: retry once
        tprint(
            f"[RETRY] {brand}: failed after {elapsed:.0f}s ({input_chars}c,"
            f" {type(e).__name__}), retrying..."
        )
        time.sleep(5)
        t0 = time.time()
        try:
            promotions = call_parse(model_type)
            elapsed = time.time() - t0
            save_result(promotions, elapsed, f" [{model_type}][retry]")
            with lock:
                counters["parsed"] += 1
                counters["durations"].append(elapsed)
            return "parsed"
        except Exception as e2:
            elapsed = time.time() - t0
            failed_path = save_failed_output(
                raw_data=dict(row), brand=brand, input_path=input_path, error=e2
            )
            tprint(f"[FAILED] {brand} after {elapsed:.0f}s ({input_chars}c): {failed_path}")
            with lock:
                counters["failed"] += 1
            return "failed"


# ── Worker thread ─────────────────────────────────────────────────────────────

def _worker(
    candidates: list[dict],
    model_type: str,
    args,
    tainted_brands: set[str],
    counters: dict,
    lock: threading.Lock,
    print_lock: threading.Lock,
    rpm_sleep: float,
    label: str,
) -> None:
    """
    Processes a list of brands sequentially for one model.
    Runs in its own thread; concurrent with other model workers.
    rpm_sleep: seconds to sleep between successful cloud API calls for RPM compliance.
    """
    llm_calls = 0
    with print_lock:
        print(f"[{label}] Starting — {len(candidates)} brand(s) assigned", flush=True)

    for row in candidates:
        result = _process_brand(
            row, model_type, args, tainted_brands, counters, lock, print_lock
        )

        if result == "parsed":
            llm_calls += 1
            if model_type == "ollama":
                if args.gc_interval and llm_calls % args.gc_interval == 0:
                    gc.collect()
                if args.ollama_restart_interval and llm_calls % args.ollama_restart_interval == 0:
                    with print_lock:
                        print(f"[OLLAMA] Unloading model after brand #{llm_calls} (memory relief)...", flush=True)
                    _unload_ollama_model(args.ollama_host, args.ollama_model)
                    time.sleep(3)
            elif rpm_sleep > 0:
                # Respect cloud RPM limit between successful extractions
                time.sleep(rpm_sleep)

    with print_lock:
        print(f"[{label}] Done — {llm_calls} brand(s) extracted", flush=True)


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Parse candidate local text files into structured promotion JSON."
    )

    parser.add_argument("--csv", default="logs/text_candidates.csv")
    parser.add_argument("--limit", type=int, default=10,
                        help="Total candidates to consider across all workers. Default: 10")
    parser.add_argument(
        "--model",
        choices=["rule_based", "ollama", "gemini", "groq"],
        default="rule_based",
        help="Extraction backend for single-model (non-parallel) mode. Default: rule_based",
    )

    # Ollama
    parser.add_argument("--ollama-model", default="qwen2.5:14b")
    parser.add_argument("--ollama-host", default="http://localhost:11434")
    parser.add_argument("--ollama-timeout", type=int, default=3600)
    parser.add_argument("--gc-interval", type=int, default=10)
    parser.add_argument("--ollama-restart-interval", type=int, default=25)

    # Gemini
    parser.add_argument("--gemini-model", default="gemini-2.0-flash")
    parser.add_argument("--gemini-api-key", default=None)

    # Groq
    parser.add_argument("--groq-model", default="llama-3.3-70b-versatile")
    parser.add_argument("--groq-api-key", default=None)

    # Cloud shared
    parser.add_argument("--cloud-timeout", type=int, default=120)

    # Parallel mode
    parser.add_argument(
        "--parallel", action="store_true",
        help=(
            "Run Groq, Gemini, and Ollama concurrently, each on a designated slice of brands. "
            "Brands are sorted by richness; Groq gets the top N, Gemini the next M, Ollama the rest."
        ),
    )
    parser.add_argument(
        "--groq-brands", type=int, default=25,
        help="In --parallel mode: number of top brands assigned to Groq. Default: 25",
    )
    parser.add_argument(
        "--gemini-brands", type=int, default=25,
        help="In --parallel mode: number of brands assigned to Gemini (after Groq's slice). Default: 25",
    )

    # Filters
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--brand", type=str, default=None)
    parser.add_argument("--failed-only", action="store_true")
    parser.add_argument("--clean-only", action="store_true")

    args = parser.parse_args()

    csv_path = resolve_path(args.csv)
    if csv_path is None or not csv_path.exists():
        raise FileNotFoundError(f"CSV file does not exist: {args.csv}")

    rows = load_rows(csv_path)
    if args.brand:
        rows = [r for r in rows if args.brand.lower() in row_brand(r).lower()]
    candidates = select_candidates(rows, limit=args.limit)

    tainted_brands: set[str] = _brands_with_failures() if args.clean_only else set()
    if args.clean_only:
        print(f"[INFO] --clean-only: {len(tainted_brands)} brands excluded (prior FAILED/RETRY)")

    counters = {"parsed": 0, "skipped": 0, "failed": 0, "quota": 0, "durations": []}
    lock       = threading.Lock()
    print_lock = threading.Lock()

    # ── Parallel mode: three concurrent workers ───────────────────────────────
    if args.parallel:
        g  = args.groq_brands
        ge = args.gemini_brands
        groq_slice   = candidates[:g]
        gemini_slice = candidates[g : g + ge]
        ollama_slice = candidates[g + ge :]

        print(
            f"[PARALLEL] Groq={len(groq_slice)} brands  "
            f"Gemini={len(gemini_slice)} brands  "
            f"Ollama={len(ollama_slice)} brands"
        )

        # RPM compliance sleeps (fires only after a successful extraction)
        # Groq free: 30 RPM → 2s gap keeps well under limit
        # Gemini free: 15 RPM → 4s gap keeps well under limit
        threads = [
            threading.Thread(
                target=_worker,
                args=(groq_slice, "groq", args, tainted_brands,
                      counters, lock, print_lock, 2.0, "Groq"),
                daemon=True,
            ),
            threading.Thread(
                target=_worker,
                args=(gemini_slice, "gemini", args, tainted_brands,
                      counters, lock, print_lock, 4.0, "Gemini"),
                daemon=True,
            ),
            threading.Thread(
                target=_worker,
                args=(ollama_slice, "ollama", args, tainted_brands,
                      counters, lock, print_lock, 0.0, "Ollama"),
                daemon=True,
            ),
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

    # ── Single-model sequential mode (existing behaviour) ─────────────────────
    else:
        current_model   = args.model
        cloud_quota_hit = False
        llm_calls       = 0

        for row in candidates:
            brand      = row_brand(row)
            path_value = row_text_path(row)
            input_path = resolve_path(path_value)

            if input_path is None or not input_path.exists():
                with lock:
                    counters["skipped"] += 1
                continue

            if args.clean_only and brand.lower() in tainted_brands:
                print(f"[SKIP] {brand}: prior FAILED/RETRY history (--clean-only)")
                with lock:
                    counters["skipped"] += 1
                continue

            if args.failed_only:
                slug = slugify(brand)
                if (STRUCTURED_DIR / f"{slug}.json").exists() or \
                   (STRUCTURED_DIR / "failed" / f"{slug}.json").exists():
                    print(f"[SKIP] {brand}: already attempted (--failed-only)")
                    with lock:
                        counters["skipped"] += 1
                    continue

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
                            with lock:
                                counters["skipped"] += 1
                            continue
                    except Exception:
                        pass

            llm_calls += 1
            if args.gc_interval and llm_calls % args.gc_interval == 0:
                gc.collect()
                print(f"[GC] gc.collect() before brand #{llm_calls}")
            if current_model == "ollama" and args.ollama_restart_interval \
                    and llm_calls % args.ollama_restart_interval == 0:
                print(f"[OLLAMA] Unloading model before brand #{llm_calls} (memory relief)...")
                _unload_ollama_model(args.ollama_host, args.ollama_model)
                time.sleep(3)

            # Delegate to _process_brand but wrap rate-limit fallback logic here
            # so sequential mode can switch current_model for all remaining brands.
            try:
                input_chars = len(input_path.read_text(encoding="utf-8", errors="replace"))
            except Exception:
                input_chars = 0

            def call_parse(mt: str, _ip=input_path, _b=brand, _cat=row_category(row)) -> list:
                return parse_text_file(
                    input_path=_ip, brand=_b, category=_cat,
                    model_type=mt,
                    ollama_model=args.ollama_model, ollama_host=args.ollama_host,
                    ollama_timeout=args.ollama_timeout,
                    gemini_model=args.gemini_model, gemini_api_key=args.gemini_api_key,
                    groq_model=args.groq_model, groq_api_key=args.groq_api_key,
                    cloud_timeout=args.cloud_timeout,
                )

            def save_seq(promotions: list, elapsed: float, tag: str,
                         _b=brand, _ip=input_path, _ic=input_chars) -> None:
                existing = STRUCTURED_DIR / f"{slugify(_b)}.json"
                if not promotions and existing.exists():
                    try:
                        old = json.loads(existing.read_text(encoding="utf-8")).get("promotions", [])
                        if old:
                            print(f"[KEPT] {_b}: 0 new, {len(old)} old deal(s) preserved ({elapsed:.0f}s, {_ic}c){tag}")
                            return
                    except Exception:
                        pass
                out = save_promotions_json(promotions=promotions, brand=_b, input_path=_ip)
                print(f"[OK] {_b} ({len(promotions)} deals, {elapsed:.0f}s, {_ic}c){tag}: {out}")

            t0 = time.time()
            try:
                promotions = call_parse(current_model)
                elapsed = time.time() - t0
                save_seq(promotions, elapsed, f" [{current_model}]" if cloud_quota_hit else "")
                with lock:
                    counters["parsed"] += 1
                    counters["durations"].append(elapsed)

            except Exception as e:
                elapsed = time.time() - t0

                if _is_rate_limit_error(e) and current_model != "ollama":
                    cloud_quota_hit = True
                    prev = current_model
                    current_model = "ollama"
                    print(
                        f"[RATE-LIMIT] {prev} quota hit on {brand} after {elapsed:.0f}s"
                        f" — switching all remaining brands to local Ollama."
                    )
                    t0 = time.time()
                    try:
                        promotions = call_parse("ollama")
                        elapsed = time.time() - t0
                        save_seq(promotions, elapsed, " [ollama-fallback]")
                        with lock:
                            counters["parsed"] += 1
                            counters["durations"].append(elapsed)
                    except Exception as e2:
                        elapsed = time.time() - t0
                        failed_path = save_failed_output(
                            raw_data=dict(row), brand=brand, input_path=input_path, error=e2
                        )
                        print(f"[FAILED] {brand} (ollama fallback) after {elapsed:.0f}s: {failed_path}")
                        with lock:
                            counters["failed"] += 1
                    continue

                is_timeout = "timed out" in str(e).lower()
                if is_timeout:
                    failed_path = save_failed_output(
                        raw_data=dict(row), brand=brand, input_path=input_path, error=e
                    )
                    print(f"[FAILED] {brand}: timeout after {elapsed:.0f}s ({input_chars}c) — {failed_path}")
                    with lock:
                        counters["failed"] += 1
                    continue

                print(f"[RETRY] {brand}: failed after {elapsed:.0f}s ({input_chars}c, {type(e).__name__}), retrying...")
                time.sleep(5)
                t0 = time.time()
                try:
                    promotions = call_parse(current_model)
                    elapsed = time.time() - t0
                    save_seq(promotions, elapsed, " [retry]")
                    with lock:
                        counters["parsed"] += 1
                        counters["durations"].append(elapsed)
                except Exception as e2:
                    elapsed = time.time() - t0
                    failed_path = save_failed_output(
                        raw_data=dict(row), brand=brand, input_path=input_path, error=e2
                    )
                    print(f"[FAILED] {brand} after {elapsed:.0f}s ({input_chars}c): {failed_path}")
                    with lock:
                        counters["failed"] += 1

        if cloud_quota_hit:
            print("Note: Cloud quota was hit mid-run — remaining brands processed by local Ollama.")

    # ── Summary ───────────────────────────────────────────────────────────────
    print()
    print("Summary")
    print(f"Parsed:  {counters['parsed']}")
    print(f"Skipped: {counters['skipped']}")
    print(f"Failed:  {counters['failed']}")
    if counters.get("quota", 0):
        print(f"Quota:   {counters['quota']} brand(s) skipped due to cloud rate limit")
    durations = counters["durations"]
    if durations:
        avg = sum(durations) / len(durations)
        print(f"LLM timing: avg {avg:.0f}s  min {min(durations):.0f}s  max {max(durations):.0f}s  (n={len(durations)})")


if __name__ == "__main__":
    main()
