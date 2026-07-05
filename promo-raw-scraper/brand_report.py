#!/usr/bin/env python3
"""
brand_report.py  —  Daily scrape/parse health report.

Usage:
    python brand_report.py                  # prints table + writes brand_report.csv
    python brand_report.py --csv            # CSV only (no table)
    python brand_report.py --status blocked # filter by status
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

# ── Paths ─────────────────────────────────────────────────────────────────────
ROOT          = Path(__file__).resolve().parent
URLS_FILE     = ROOT / "sources" / "urls.json"
RAW_TEXT_DIR  = ROOT / "raw_text"
STRUCT_DIR    = ROOT / "structured_outputs"
FAILED_DIR    = STRUCT_DIR / "failed"
PROMO_FILE    = ROOT / "all_promotions.json"
REPORT_CSV    = ROOT / "brand_report.csv"

# ── Anti-bot signals in scraped text ──────────────────────────────────────────
_BLOCK_SIGNALS = [
    "access denied", "forbidden", "cloudflare", "captcha",
    "are you human", "just a moment", "checking your browser",
    "enable javascript", "pardon our interruption", "security check",
    "robot or human", "ddos-guard", "ray id",
]
_TOO_SHORT = 400       # chars — below this is almost certainly a challenge page
_HOMEPAGE_ONLY = True  # flag root-domain URLs with no path

# ── Brand slug helper ─────────────────────────────────────────────────────────
_SLUG_RE = re.compile(r"[^a-z0-9]+")

def _slug(brand: str) -> str:
    return _SLUG_RE.sub("_", brand.lower()).strip("_")

def _latest_raw(brand: str) -> Path | None:
    matches = sorted(RAW_TEXT_DIR.glob(f"{_slug(brand)}_*.txt"))
    return matches[-1] if matches else None

def _is_homepage(url: str) -> bool:
    try:
        p = urlparse(url)
        return p.path.strip("/") == "" and not p.query
    except Exception:
        return False

# ── Load all_promotions.json → per-brand deal counts ─────────────────────────
def _load_deal_counts() -> dict[str, dict]:
    """Returns {brand: {llm: int, synthetic: int}}"""
    counts: dict[str, dict] = {}
    if not PROMO_FILE.exists():
        return counts
    data = json.loads(PROMO_FILE.read_text(encoding="utf-8"))
    for p in data.get("promotions", []):
        brand = p.get("brand", "")
        if brand not in counts:
            counts[brand] = {"llm": 0, "synthetic": 0}
        if p.get("synthesized"):
            counts[brand]["synthetic"] += 1
        else:
            counts[brand]["llm"] += 1
    return counts

# ── Load failed structured outputs → set of brand names ──────────────────────
def _load_failed_brands() -> dict[str, str]:
    """Returns {brand: error_snippet}"""
    failed: dict[str, str] = {}
    if not FAILED_DIR.exists():
        return failed
    for f in FAILED_DIR.glob("*.json"):
        try:
            obj = json.loads(f.read_text(encoding="utf-8"))
            brand = obj.get("brand", f.stem)
            err   = obj.get("error", "unknown error")
            failed[brand] = err[:120]
        except Exception:
            failed[f.stem] = "could not read failed output"
    return failed

# ── Determine status + reason for one brand ───────────────────────────────────
def _assess(brand: str, urls: list[str], deal_counts: dict, failed_brands: dict) -> dict:
    llm_deals  = deal_counts.get(brand, {}).get("llm", 0)
    synth_deals = deal_counts.get(brand, {}).get("synthetic", 0)
    raw_file   = _latest_raw(brand)
    raw_chars  = 0
    status     = "never_scraped"
    reason     = "no raw file on disk — scrape has never succeeded"

    # ── Parse failed ──────────────────────────────────────────────────────────
    if brand in failed_brands:
        raw_chars = len(raw_file.read_text(encoding="utf-8", errors="ignore")) if raw_file else 0
        return {
            "status":        "parse_failed",
            "raw_chars":     raw_chars,
            "llm_deals":     0,
            "synth_deals":   0,
            "reason":        failed_brands[brand],
        }

    # ── Never scraped ─────────────────────────────────────────────────────────
    if raw_file is None:
        # Distinguish homepage-only vs true never-scraped
        if all(_is_homepage(u) for u in urls):
            return {
                "status":      "homepage_only",
                "raw_chars":   0,
                "llm_deals":   0,
                "synth_deals": 0,
                "reason":      "URL is root domain — no deals/offers path to scrape",
            }
        return {
            "status":      "never_scraped",
            "raw_chars":   0,
            "llm_deals":   0,
            "synth_deals": 0,
            "reason":      "scrape has never produced a raw file (likely 403/timeout/bot-block at request level)",
        }

    # ── Raw file exists — inspect it ──────────────────────────────────────────
    text = raw_file.read_text(encoding="utf-8", errors="ignore")
    raw_chars = len(text)
    text_l = text.lower()

    if raw_chars < _TOO_SHORT:
        status = "too_short"
        reason = f"raw file only {raw_chars} chars — scraper returned a challenge/redirect page"
    elif any(sig in text_l for sig in _BLOCK_SIGNALS):
        hit = next(s for s in _BLOCK_SIGNALS if s in text_l)
        status = "blocked_or_challenge"
        reason = f'anti-bot signal detected: "{hit}"'
    elif llm_deals > 0 or synth_deals > 0:
        if synth_deals > 0 and llm_deals == 0:
            status = "success_synthetic"
            reason = "price-grid synthesizer produced deal(s)"
        else:
            status = "success_llm"
            reason = "LLM extracted deal(s) successfully"
    else:
        status = "zero_deals_real"
        reason = "scraped OK but LLM found 0 deals and synthesizer found nothing"

    return {
        "status":      status,
        "raw_chars":   raw_chars,
        "llm_deals":   llm_deals,
        "synth_deals": synth_deals,
        "reason":      reason,
    }

# ── Main ──────────────────────────────────────────────────────────────────────
def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv",    action="store_true", help="CSV output only")
    ap.add_argument("--status", metavar="STATUS",    help="filter to one status")
    ap.add_argument("--out",    default=str(REPORT_CSV), help="CSV output path")
    args = ap.parse_args()

    sources     = json.loads(URLS_FILE.read_text(encoding="utf-8-sig"))
    deal_counts = _load_deal_counts()
    failed_brands = _load_failed_brands()

    rows = []
    for entry in sources:
        brand    = entry["brand"]
        category = entry.get("category", "")
        urls     = entry.get("urls", [entry.get("url", "")])
        url_str  = urls[0] if urls else ""

        info = _assess(brand, urls, deal_counts, failed_brands)
        rows.append({
            "brand":         brand,
            "category":      category,
            "url":           url_str,
            "status":        info["status"],
            "raw_chars":     info["raw_chars"],
            "llm_deals":     info["llm_deals"],
            "synth_deals":   info["synth_deals"],
            "reason":        info["reason"],
        })

    # Filter
    if args.status:
        rows = [r for r in rows if r["status"] == args.status]

    # Sort: failures first, then by brand name
    STATUS_ORDER = [
        "parse_failed", "blocked_or_challenge", "too_short",
        "zero_deals_real", "never_scraped", "homepage_only",
        "success_synthetic", "success_llm",
    ]
    rows.sort(key=lambda r: (STATUS_ORDER.index(r["status"]) if r["status"] in STATUS_ORDER else 99, r["brand"]))

    # Write CSV
    out_path = Path(args.out)
    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["brand","category","url","status","raw_chars","llm_deals","synth_deals","reason"])
        writer.writeheader()
        writer.writerows(rows)

    if not args.csv:
        # Print summary counts
        from collections import Counter
        counts = Counter(r["status"] for r in rows)
        total  = len(rows)
        print(f"\nBrand Health Report — {total} brands\n")
        print(f"  {'Status':<25} {'Count':>5}  {'%':>5}")
        print(f"  {'-'*37}")
        for status in STATUS_ORDER:
            n = counts.get(status, 0)
            if n:
                pct = n / total * 100
                print(f"  {status:<25} {n:>5}  {pct:>4.1f}%")

        # Print table
        COLS = ["brand", "status", "raw_chars", "llm_deals", "synth_deals", "reason"]
        widths = {c: max(len(c), max((len(str(r[c])) for r in rows), default=0)) for c in COLS}
        widths["brand"]  = min(widths["brand"],  30)
        widths["reason"] = min(widths["reason"],  55)

        print()
        header = "  ".join(c.upper().ljust(widths[c]) for c in COLS)
        print(header)
        print("-" * len(header))
        for r in rows:
            line = "  ".join(
                str(r[c])[:widths[c]].ljust(widths[c]) for c in COLS
            )
            print(line)

        print(f"\nCSV saved to: {out_path}")


if __name__ == "__main__":
    main()
