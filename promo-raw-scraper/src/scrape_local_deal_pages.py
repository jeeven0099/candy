"""
scrape_local_deal_pages.py

Visits each local business website and looks for current deals/promotions.
Applies a strict quality gate (confidence >= 0.85) before accepting.
Outputs: local_promotions.json

Usage:
    python scrape_local_deal_pages.py [--limit 30] [--skip-checked-days 3]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import requests as _req

SRC = Path(__file__).resolve().parent
ROOT = SRC.parent
sys.path.insert(0, str(SRC))

from fetch_page import fetch_page
from fetch_page_js import PlaywrightSession

try:
    from bs4 import BeautifulSoup
    _BS4 = True
except ImportError:
    _BS4 = False

CANDIDATES_FILE = ROOT / "local_business_candidates.json"
OUTPUT_FILE     = ROOT / "local_promotions.json"

_DEAL_SIGNALS = [
    "sale", "special", "discount", "promo", "promotion", "offer",
    "happy hour", "deal", "coupon", "% off", "off today", "free",
    "first visit", "new guest", "first time", "student", "resident",
    "pop-up", "pop up", "event", "limited time", "this week", "today only",
    "weekday special", "prix fixe", "early bird", "complimentary",
    "bogo", "buy one", "get one",
]
_MIN_SIGNALS = 2
_CONFIDENCE_THRESHOLD = 0.85
_MAX_TEXT = 6000

_DEAL_PROMPT = """\
You are checking whether a local business website currently has any specific promotions or deals.

Business: {name}
Location: {address}
Website: {url}

Page content:
{text}

Look ONLY for SPECIFIC, CURRENT deals:
- Specific discounts: "20% off", "$5 off", "buy one get one free", "free item with purchase"
- Happy hour with specific times (e.g. "Mon-Fri 4-6pm, half-price drinks")
- Upcoming events with a clear offer or discounted admission
- First-visit or new-customer discounts with a stated benefit
- Student or resident discounts (if a specific benefit is stated)

Do NOT extract:
- Generic "visit us" or "shop now" or "new arrivals" messages
- Vague "great deals" or "great value" without specifics
- Expired events or past promotions
- General loyalty program descriptions without a current offer

Return ONLY valid JSON:
{{
  "has_deal": true,
  "promotions": [
    {{
      "promotion_title": "Short descriptive title",
      "discount_type": "percentage_off|amount_off|free_item|happy_hour|event|other",
      "discount_value": "20% off" or "$5 off" or "Free coffee" or null,
      "description": "Full deal description in 1-2 sentences",
      "valid_days": ["Monday", "Tuesday"] or [],
      "time_start": "17:00" or null,
      "time_end": "19:00" or null,
      "end_date": "YYYY-MM-DD" or null,
      "is_evergreen": false,
      "confidence_score": 0.90
    }}
  ]
}}

If no specific current deal exists, return: {{"has_deal": false, "promotions": []}}

JSON:"""


def html_to_text(html: str) -> str:
    if not _BS4:
        text = re.sub(r'<[^>]+>', ' ', html)
        return re.sub(r'\s+', ' ', text).strip()
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["script", "style", "nav", "footer", "head", "meta", "link"]):
        tag.decompose()
    return soup.get_text(separator="\n", strip=True)


def has_deal_signals(text: str) -> bool:
    lower = text.lower()
    count = sum(1 for s in _DEAL_SIGNALS if s in lower)
    return count >= _MIN_SIGNALS


def call_ollama(prompt: str, host: str, model: str, timeout: int = 90) -> dict | None:
    try:
        r = _req.post(
            f"{host}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=timeout,
        )
        if r.status_code != 200:
            return None
        raw = r.json().get("response", "")
        m = re.search(r'\{.*\}', raw, re.DOTALL)
        if not m:
            return None
        return json.loads(m.group(0))
    except (json.JSONDecodeError, Exception):
        return None


def fetch_page_html(url: str) -> str | None:
    result = fetch_page(url)
    if result.ok and result.html:
        return result.html
    try:
        with PlaywrightSession(timeout_ms=20000) as session:
            r = session.fetch(url)
            if r.ok and r.html:
                return r.html
    except Exception:
        pass
    return None


def days_since(ts: str | None) -> int | None:
    if not ts:
        return None
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        return (datetime.now(timezone.utc) - dt).days
    except Exception:
        return None


def build_promotion(biz: dict, promo_data: dict, source_url: str) -> dict:
    domain = urlparse(source_url).netloc.replace("www.", "")
    address = biz.get("address")
    if not address:
        address = f"{biz.get('neighborhood', '')}, {biz.get('city', '')}".strip(", ")
    return {
        "brand": biz["name"],
        "category": biz.get("category", "other"),
        "promotion_title": promo_data.get("promotion_title", ""),
        "promotion_type": "deal",
        "discount_type": promo_data.get("discount_type", "other"),
        "discount_value": promo_data.get("discount_value"),
        "deal_scope": "in_store_only",
        "status": "active",
        "confidence_score": float(promo_data.get("confidence_score", _CONFIDENCE_THRESHOLD)),
        "redemption_method": "in_store",
        "requires_membership": False,
        "requires_app": False,
        "purchase_required": promo_data.get("discount_type") not in ("free_item",),
        "valid_days": promo_data.get("valid_days") or [],
        "time_start": promo_data.get("time_start"),
        "time_end": promo_data.get("time_end"),
        "end_date": promo_data.get("end_date"),
        "description": promo_data.get("description", ""),
        "source": "local_neighborhood",
        "source_url": source_url,
        "website_domain": domain,
        "neighborhood": biz.get("neighborhood"),
        "city": biz.get("city"),
        "address": address,
        "lat": biz.get("lat"),
        "lon": biz.get("lon"),
        "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Scrape local business websites for deals")
    parser.add_argument("--ollama-host", default="http://localhost:11434")
    parser.add_argument("--ollama-model", default="qwen2.5:14b")
    parser.add_argument("--candidates", type=Path, default=CANDIDATES_FILE)
    parser.add_argument("--output", type=Path, default=OUTPUT_FILE)
    parser.add_argument("--limit", type=int, default=30, help="Max businesses to check per run")
    parser.add_argument("--skip-checked-days", type=int, default=3,
                        help="Skip businesses already checked within N days (default: 3)")
    args = parser.parse_args()

    if not args.candidates.exists():
        print(f"[ERROR] Candidates file not found: {args.candidates}")
        print("  Run scrape_neighborhood_directory.py first.")
        sys.exit(1)

    data = json.loads(args.candidates.read_text(encoding="utf-8"))
    businesses = data.get("businesses", [])
    print(f"Loaded {len(businesses)} business candidates")

    # Load existing output to preserve history and track last-checked times
    promo_index: dict[str, dict] = {}
    if args.output.exists():
        out_data = json.loads(args.output.read_text(encoding="utf-8"))
        for p in out_data.get("promotions", []):
            key = (p.get("brand") or "").lower().strip()
            if key:
                promo_index[key] = p
        print(f"  Loaded {len(promo_index)} existing local promotions")

    # Track check timestamps for businesses with no active deal
    check_log: dict[str, str] = {}
    if args.output.exists():
        out_data = json.loads(args.output.read_text(encoding="utf-8"))
        for entry in out_data.get("checked_no_deal", []):
            key = (entry.get("name") or "").lower().strip()
            check_log[key] = entry.get("checked_at", "")

    checked = 0
    found = 0
    no_deal_log: list[dict] = []

    for biz in businesses:
        if checked >= args.limit:
            break

        website = biz.get("website")
        if not website:
            continue

        biz_name = biz.get("name", "")
        biz_key = biz_name.lower().strip()

        # Skip if we already have an active deal for this biz checked recently
        existing_promo = promo_index.get(biz_key)
        if existing_promo:
            age = days_since(existing_promo.get("checked_at"))
            if age is not None and age < args.skip_checked_days:
                continue

        # Skip if we checked and found no deal recently
        last_no_deal_check = check_log.get(biz_key)
        if last_no_deal_check:
            age = days_since(last_no_deal_check)
            if age is not None and age < args.skip_checked_days:
                continue

        checked += 1
        print(f"\n[{checked}/{args.limit}] {biz_name} — {website}")

        html = fetch_page_html(website)
        if not html:
            print("  [SKIP] Could not fetch website")
            continue

        text = html_to_text(html)[:_MAX_TEXT]

        if not has_deal_signals(text):
            print("  [SKIP] Insufficient deal signals")
            check_log[biz_key] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            no_deal_log.append({"name": biz_name, "checked_at": check_log[biz_key]})
            continue

        time.sleep(1.0)

        address = biz.get("address") or f"{biz.get('neighborhood', '')}, {biz.get('city', '')}".strip(", ")
        prompt = _DEAL_PROMPT.format(
            name=biz_name,
            address=address,
            url=website,
            text=text,
        )

        result = call_ollama(prompt, args.ollama_host, args.ollama_model)
        if not result:
            print("  [SKIP] LLM extraction failed")
            continue

        if not result.get("has_deal"):
            print("  [SKIP] No current deal found")
            now_ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            check_log[biz_key] = now_ts
            no_deal_log.append({"name": biz_name, "checked_at": now_ts})
            continue

        promotions_raw = result.get("promotions") or []
        qualified = [
            p for p in promotions_raw
            if (p.get("confidence_score") or 0) >= _CONFIDENCE_THRESHOLD
            and p.get("promotion_title")
        ]

        if not qualified:
            print(f"  [SKIP] No promotions passed confidence >= {_CONFIDENCE_THRESHOLD}")
            continue

        best = max(qualified, key=lambda p: p.get("confidence_score", 0))
        promo = build_promotion(biz, best, website)
        print(f"  [OK] \"{best.get('promotion_title')}\" (confidence={best.get('confidence_score', 0):.2f})")
        promo_index[biz_key] = promo
        found += 1

    # Write output
    all_promos = list(promo_index.values())
    output = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "promotion_count": len(all_promos),
        "promotions": all_promos,
        "checked_no_deal": no_deal_log,
    }
    args.output.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"\nChecked {checked} businesses, found {found} new deal(s)")
    print(f"Total local promotions: {len(all_promos)}")
    print(f"Written to {args.output.name}")


if __name__ == "__main__":
    main()
