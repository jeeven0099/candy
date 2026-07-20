"""
run_keyword_backfill.py — Incremental keyword backfill for existing promotions.

Each run:
  1. Loads/builds a queue of brands that lack new-schema keywords.
  2. Takes the next --batch brands from the queue.
  3. Calls Groq or Ollama with a lightweight keyword-only prompt per brand.
  4. Patches product_keywords_explicit / product_keywords_contextual / product_categories
     directly into all_promotions.json (and merged_promotions.json if present).
  5. Saves progress to keyword_backfill_queue.json.

Usage:
  python run_keyword_backfill.py [--batch 10] [--rebuild-queue] [--ollama] [--ollama-model MODEL]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import httpx
from groq import Groq

# ── Paths ─────────────────────────────────────────────────────────────────────

ROOT = Path(__file__).resolve().parents[1]
SRC  = Path(__file__).resolve().parent

RAW_TEXT_DIR   = ROOT / "raw_text"
QUEUE_FILE     = ROOT / "keyword_backfill_queue.json"
KEYWORD_STORE  = ROOT / "keyword_store.json"
ASSETS_DIR     = ROOT.parent / "promo_viewer" / "assets"
ALL_PROMOS     = ASSETS_DIR / "all_promotions.json"
MERGED_PROMOS  = ASSETS_DIR / "merged_promotions.json"

GROQ_MODEL   = "llama-3.3-70b-versatile"
OLLAMA_MODEL = "qwen2.5:14b"
OLLAMA_HOST  = "http://localhost:11434"

# ── Env ───────────────────────────────────────────────────────────────────────

def _load_env() -> None:
    env_path = ROOT / ".env"
    if not env_path.exists():
        return
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip())

_load_env()

# ── Queue ─────────────────────────────────────────────────────────────────────

def _slugify(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return s or "unknown"


def _latest_raw_text(brand: str) -> Optional[Path]:
    """Return the most recent .txt file for this brand, or None."""
    slug = _slugify(brand)
    candidates = sorted(RAW_TEXT_DIR.glob(f"{slug}_*.txt"), reverse=True)
    return candidates[0] if candidates else None


def _brands_missing_keywords(promos: list[dict]) -> list[str]:
    """Return unique brand names whose promotions lack new-schema keyword fields."""
    missing: dict[str, int] = {}
    for p in promos:
        brand = p.get("brand", "")
        if not brand:
            continue
        has_new = bool(p.get("product_keywords_explicit") or p.get("product_keywords_contextual"))
        if not has_new:
            missing[brand] = missing.get(brand, 0) + 1
    # Sort by promotion count desc so high-impact brands come first
    return [b for b, _ in sorted(missing.items(), key=lambda x: -x[1])]


def load_queue(promos: list[dict], rebuild: bool = False) -> dict:
    if QUEUE_FILE.exists() and not rebuild:
        q = json.loads(QUEUE_FILE.read_text(encoding="utf-8"))
        # Prune done/failed from pending in case of file edits
        done_set   = set(q.get("done", []))
        failed_set = set(q.get("failed", []))
        q["pending"] = [b for b in q.get("pending", []) if b not in done_set and b not in failed_set]
        return q

    pending = _brands_missing_keywords(promos)
    q = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "pending": pending,
        "done": [],
        "failed": [],
    }
    QUEUE_FILE.write_text(json.dumps(q, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Queue built: {len(pending)} brands need keyword backfill.")
    return q


def save_queue(q: dict) -> None:
    QUEUE_FILE.write_text(json.dumps(q, indent=2, ensure_ascii=False), encoding="utf-8")

# ── Groq call ─────────────────────────────────────────────────────────────────

_KEYWORD_PROMPT = """\
You are analyzing a deals/promotions page for the brand "{brand}" (category: {category}).

Your task is to identify what types of products this brand sells, based ONLY on the page content below.

Rules:
- product_keywords: up to 20 specific product-type nouns visible on this page (e.g. "running shoes", "moisturizer", "laptops"). Use only product-type nouns — no colors, sizes, fit descriptors, gender words, or promo words like "sale", "new", "clearance".
- product_categories: up to 5 broad buckets from this list ONLY: footwear, clothing, accessories, beauty, food, electronics, home, fitness, travel, other.
- Leave product_keywords [] if the page is purely a restaurant/food-service brand with no physical products to search.

Page content:
---
{text}
---

Return ONLY a JSON object with exactly these two keys:
{{
  "product_keywords": [...],
  "product_categories": [...]
}}"""


def call_groq_keywords(
    client: Groq,
    brand: str,
    category: str,
    text: str,
) -> Optional[dict]:
    """Call Groq with a keyword-only prompt. Returns dict or None on error."""
    safe_text = text[:5000]
    prompt = _KEYWORD_PROMPT.format(
        brand=brand,
        category=category or "retail",
        text=safe_text,
    )
    try:
        response = client.chat.completions.create(
            model=GROQ_MODEL,
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
            max_tokens=512,
            timeout=60,
        )
        raw = response.choices[0].message.content or ""
        data = json.loads(raw)
        return {
            "product_keywords": [s for s in data.get("product_keywords", []) if isinstance(s, str)],
            "product_categories": [s for s in data.get("product_categories", []) if isinstance(s, str)],
        }
    except Exception as exc:
        raise exc


def call_ollama_keywords(
    brand: str,
    category: str,
    text: str,
    model: str = OLLAMA_MODEL,
) -> Optional[dict]:
    """Call local Ollama with a keyword-only prompt. Returns dict or raises on error."""
    import requests as _requests
    safe_text = text[:5000]
    prompt = _KEYWORD_PROMPT.format(
        brand=brand,
        category=category or "retail",
        text=safe_text,
    )
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "format": "json",
        "options": {"num_predict": 512, "num_ctx": 8192},
    }
    response = _requests.post(f"{OLLAMA_HOST}/api/chat", json=payload, timeout=120, verify=False)
    response.raise_for_status()
    raw = response.json().get("message", {}).get("content", "")
    data = json.loads(raw)
    return {
        "product_keywords": [s for s in data.get("product_keywords", []) if isinstance(s, str)],
        "product_categories": [s for s in data.get("product_categories", []) if isinstance(s, str)],
    }

# ── Promotions patching ───────────────────────────────────────────────────────

def patch_promotions_file(path: Path, brand: str, keywords: list[str], categories: list[str]) -> int:
    """Patch keyword fields for all promotions of this brand in a JSON file. Returns count patched."""
    if not path.exists():
        return 0
    data = json.loads(path.read_text(encoding="utf-8"))
    promos = data.get("promotions", data) if isinstance(data, dict) else data
    if not isinstance(promos, list):
        return 0

    patched = 0
    for p in promos:
        if p.get("brand") != brand:
            continue
        # Only fill if missing new-schema fields
        if p.get("product_keywords_explicit") or p.get("product_keywords_contextual"):
            continue
        p["product_keywords_contextual"] = keywords[:25]
        p["product_keywords_explicit"]   = []
        if categories:
            p.setdefault("product_categories", categories[:5])
        patched += 1

    if isinstance(data, dict):
        data["promotions"] = promos
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    else:
        path.write_text(json.dumps(promos, indent=2, ensure_ascii=False), encoding="utf-8")
    return patched

# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Incremental keyword backfill (Groq or Ollama).")
    parser.add_argument("--batch", type=int, default=10, help="Brands to process per run (default: 10)")
    parser.add_argument("--rebuild-queue", action="store_true", help="Rebuild queue from scratch")
    parser.add_argument("--ollama", action="store_true", help="Use local Ollama instead of Groq")
    parser.add_argument("--ollama-model", default=OLLAMA_MODEL, help=f"Ollama model to use (default: {OLLAMA_MODEL})")
    args = parser.parse_args()

    use_ollama = args.ollama
    api_key = os.environ.get("GROQ_API_KEY", "")
    if not use_ollama and not api_key:
        print("No GROQ_API_KEY set — falling back to Ollama.")
        use_ollama = True

    # Load promotions
    if not ALL_PROMOS.exists():
        print(f"ERROR: {ALL_PROMOS} not found.")
        return

    data = json.loads(ALL_PROMOS.read_text(encoding="utf-8"))
    promos = data.get("promotions", [])

    # Load/build queue
    q = load_queue(promos, rebuild=args.rebuild_queue)
    pending = q["pending"]

    if not pending:
        print("All brands already have keywords. Nothing to do.")
        return

    batch = pending[: args.batch]
    print(f"Backfill batch: {len(batch)} brands ({len(pending)} total pending)")
    print(f"Queue: {len(q['done'])} done, {len(q['failed'])} failed\n")

    client = None if use_ollama else Groq(
        api_key=api_key,
        http_client=httpx.Client(verify=False),
    )
    backend = f"Ollama ({args.ollama_model})" if use_ollama else f"Groq ({GROQ_MODEL})"
    print(f"Backend: {backend}\n")

    results = {"done": 0, "failed": 0, "no_text": 0, "quota_hit": False}

    for i, brand in enumerate(batch):
        txt_path = _latest_raw_text(brand)
        if txt_path is None:
            print(f"  [{i+1}/{len(batch)}] {brand} — no raw text file, skipping")
            q["pending"].remove(brand)
            q["failed"].append(brand)
            results["no_text"] += 1
            continue

        # Get category from promotions
        cat = next((p.get("category", "") for p in promos if p.get("brand") == brand), "")
        text = txt_path.read_text(encoding="utf-8", errors="replace")

        print(f"  [{i+1}/{len(batch)}] {brand} ...", end=" ", flush=True)
        try:
            if use_ollama:
                kw_data = call_ollama_keywords(brand, cat, text, model=args.ollama_model)
            else:
                kw_data = call_groq_keywords(client, brand, cat, text)
            kws = kw_data["product_keywords"]
            cats = kw_data["product_categories"]

            # Persist to keyword store so nightly pipeline re-applies after re-extraction
            store = json.loads(KEYWORD_STORE.read_text(encoding="utf-8")) if KEYWORD_STORE.exists() else {}
            store[brand] = {
                "contextual": kws,
                "categories": cats,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
            KEYWORD_STORE.write_text(json.dumps(store, indent=2, ensure_ascii=False), encoding="utf-8")

            n = patch_promotions_file(ALL_PROMOS, brand, kws, cats)
            patch_promotions_file(MERGED_PROMOS, brand, kws, cats)

            print(f"{n} promo(s) patched — kws: {kws[:5]}{'…' if len(kws) > 5 else ''}")
            q["pending"].remove(brand)
            q["done"].append(brand)
            results["done"] += 1

        except Exception as exc:
            msg = str(exc).lower()
            if any(k in msg for k in ("rate_limit", "429", "quota", "resource_exhausted")):
                print(f"QUOTA HIT — stopping. Will resume from {brand} next run.")
                results["quota_hit"] = True
                save_queue(q)
                break
            print(f"FAILED: {exc}")
            q["pending"].remove(brand)
            q["failed"].append(brand)
            results["failed"] += 1

        if i < len(batch) - 1 and not use_ollama:
            time.sleep(2)  # rate limit buffer for Groq

    save_queue(q)

    print("\n-- Summary ----------------------------------")
    print(f"  Done:     {results['done']}")
    print(f"  Failed:   {results['failed']}")
    print(f"  No text:  {results['no_text']}")
    print(f"  Quota hit: {results['quota_hit']}")
    print(f"  Remaining in queue: {len(q['pending'])}")
    if results["quota_hit"]:
        print("  Run again tomorrow to continue.")


if __name__ == "__main__":
    main()
