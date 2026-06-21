"""
scrape_neighborhood_directory.py

Fetches neighborhood business directories and extracts local business listings.
Outputs: local_business_candidates.json

Usage:
    python scrape_neighborhood_directory.py [--ollama-host http://localhost:11434]
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

SOURCES_FILE = ROOT / "sources" / "neighborhood_sources.json"
OUTPUT_FILE  = ROOT / "local_business_candidates.json"

_MAX_TEXT = 8000

_EXTRACT_PROMPT = """\
You are extracting local business listings from a neighborhood directory web page.

Directory URL: {url}
Neighborhood: {neighborhood}, {city}, {state}

Page content:
{text}

Extract every local business you can identify. For each business return an object with:
- "name": business name (string, required)
- "address": full street address if visible (string or null)
- "website": website URL if visible (string or null)
- "phone": phone number if visible (string or null)
- "category": one of: food, coffee, retail, beauty, services, entertainment, fitness, grocery, other
- "description": brief description if available (string or null)

Rules:
- Only include actual local businesses, NOT navigation links, ads, or generic page text
- If a URL belongs to the directory site itself, set website to null
- Return a valid JSON array and nothing else

If no businesses are found, return [].

JSON array:"""


def html_to_text(html: str) -> str:
    if not _BS4:
        text = re.sub(r'<[^>]+>', ' ', html)
        return re.sub(r'\s+', ' ', text).strip()
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["script", "style", "nav", "footer", "head"]):
        tag.decompose()
    return soup.get_text(separator="\n", strip=True)


def call_ollama(prompt: str, host: str, model: str, timeout: int = 120) -> str | None:
    try:
        r = _req.post(
            f"{host}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=timeout,
        )
        if r.status_code != 200:
            print(f"  [WARN] Ollama returned {r.status_code}")
            return None
        return r.json().get("response", "")
    except Exception as e:
        print(f"  [WARN] Ollama error: {e}")
        return None


def extract_businesses(
    url: str, html: str,
    neighborhood: str, city: str, state: str,
    host: str, model: str,
) -> list[dict]:
    text = html_to_text(html)[:_MAX_TEXT]
    if len(text.strip()) < 50:
        return []

    prompt = _EXTRACT_PROMPT.format(
        url=url, neighborhood=neighborhood, city=city, state=state, text=text
    )
    response = call_ollama(prompt, host, model)
    if not response:
        return []

    m = re.search(r'\[.*\]', response, re.DOTALL)
    if not m:
        return []
    try:
        businesses = json.loads(m.group(0))
    except json.JSONDecodeError:
        return []
    if not isinstance(businesses, list):
        return []

    directory_host = urlparse(url).netloc.replace("www.", "")
    valid = []
    for b in businesses:
        name = (b.get("name") or "").strip()
        if not name or len(name) < 2:
            continue
        website = b.get("website") or None
        if website:
            site_host = urlparse(website).netloc.replace("www.", "")
            if directory_host and site_host and directory_host in site_host:
                website = None
        valid.append({
            "name": name,
            "address": b.get("address") or None,
            "website": website,
            "phone": b.get("phone") or None,
            "category": b.get("category") or "other",
            "description": b.get("description") or None,
            "neighborhood": neighborhood,
            "city": city,
            "state": state,
            "source_directory": url,
        })
    return valid


def fetch_with_fallback(url: str) -> str | None:
    result = fetch_page(url)
    if result.ok and result.html:
        return result.html
    print(f"  Plain fetch failed ({result.error}), trying Playwright...")
    try:
        with PlaywrightSession(timeout_ms=25000) as session:
            r = session.fetch(url)
            if r.ok and r.html:
                return r.html
    except Exception as e:
        print(f"  Playwright error: {e}")
    return None


def main() -> None:
    parser = argparse.ArgumentParser(description="Scrape neighborhood business directories")
    parser.add_argument("--ollama-host", default="http://localhost:11434")
    parser.add_argument("--ollama-model", default="qwen2.5:14b")
    parser.add_argument("--sources", type=Path, default=SOURCES_FILE)
    parser.add_argument("--output", type=Path, default=OUTPUT_FILE)
    args = parser.parse_args()

    if not args.sources.exists():
        print(f"[ERROR] Sources file not found: {args.sources}")
        sys.exit(1)

    sources = json.loads(args.sources.read_text(encoding="utf-8"))
    print(f"Loaded {len(sources)} neighborhood config(s)")

    # Preserve existing candidates, merging new discoveries
    existing: dict[str, dict] = {}
    if args.output.exists():
        data = json.loads(args.output.read_text(encoding="utf-8"))
        for b in data.get("businesses", []):
            key = (b.get("name") or "").lower().strip()
            if key:
                existing[key] = b
        print(f"  Loaded {len(existing)} existing candidates")

    new_count = 0

    for cfg in sources:
        if not cfg.get("enabled", True):
            continue
        nbhd, city, state = cfg["neighborhood"], cfg["city"], cfg["state"]
        print(f"\n=== {nbhd}, {city} ===")

        for directory in cfg.get("directories", []):
            dir_url  = directory["url"]
            dir_name = directory.get("name", dir_url)
            print(f"\n  Directory: {dir_name}")
            print(f"  Fetching {dir_url}...")

            html = fetch_with_fallback(dir_url)
            if not html:
                print(f"  [SKIP] Could not fetch page")
                continue

            time.sleep(1.5)
            businesses = extract_businesses(dir_url, html, nbhd, city, state, args.ollama_host, args.ollama_model)
            print(f"  Extracted {len(businesses)} business(es)")

            for b in businesses:
                # Embed neighborhood centroid coordinates for distance calculation in app
                b.setdefault("lat", cfg.get("lat"))
                b.setdefault("lon", cfg.get("lon"))
                key = b["name"].lower().strip()
                if key not in existing:
                    existing[key] = b
                    new_count += 1
                else:
                    old = existing[key]
                    if not old.get("website") and b.get("website"):
                        old["website"] = b["website"]
                    if not old.get("address") and b.get("address"):
                        old["address"] = b["address"]

    all_businesses = list(existing.values())
    output = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "business_count": len(all_businesses),
        "businesses": all_businesses,
    }
    args.output.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nTotal candidates: {len(all_businesses)} ({new_count} new)")
    print(f"Written to {args.output.name}")


if __name__ == "__main__":
    main()
