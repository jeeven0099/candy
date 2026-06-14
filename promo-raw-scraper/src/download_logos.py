"""
download_logos.py — download and cache brand logos locally.

Reads all_promotions.json, fetches a logo for each unique root domain,
saves to logos/{root_domain}.png. Skips already-downloaded valid logos.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
ALL_PROMOS = ROOT / "all_promotions.json"
LOGOS_DIR = ROOT / "logos"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    )
}

# Brands whose root domain points to a parent/sub-site — fetch from a better URL
_DOMAIN_OVERRIDES: dict[str, str] = {
    "fuelrewards.com": "shell.com",   # Shell loyalty sub-site
}

_SOURCES = [
    "https://icon.horse/icon/{domain}",
    "https://{domain}/apple-touch-icon.png",
    "https://www.{domain}/apple-touch-icon.png",
    # Google's high-res favicon API used by Google Search — returns PNG
    "https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://{domain}&size=256",
    "https://www.google.com/s2/favicons?domain={domain}&sz=128",
]

# Valid image magic bytes — ICO intentionally excluded (Flutter Web can't decode it)
_IMAGE_MAGIC = [
    b"\x89PNG",   # PNG
    b"\xff\xd8",  # JPEG
    b"RIFF",      # WebP
    b"GIF87a",    # GIF
    b"GIF89a",    # GIF
]


def is_valid_image(data: bytes) -> bool:
    return any(data[:len(magic)] == magic for magic in _IMAGE_MAGIC)


def root_domain(domain: str) -> str:
    parts = domain.strip().split(".")
    if len(parts) <= 2:
        return domain
    return ".".join(parts[-2:])


def fetch_logo(domain: str) -> bytes | None:
    for url_tpl in _SOURCES:
        url = url_tpl.format(domain=domain)
        try:
            r = requests.get(url, headers=HEADERS, timeout=12, allow_redirects=True)
            if r.status_code == 200 and len(r.content) >= 500 and is_valid_image(r.content):
                return r.content
        except Exception:
            pass
        time.sleep(0.3)
    return None


def main() -> None:
    LOGOS_DIR.mkdir(exist_ok=True)

    raw = ALL_PROMOS.read_text(encoding="utf-8")
    data = json.loads(raw)
    promos = data.get("promotions", []) if isinstance(data, dict) else data

    # Collect unique root domains
    domains: dict[str, str] = {}  # root_domain -> brand name (for display)
    for p in promos:
        domain = (p.get("website_domain") or "").strip()
        if not domain:
            continue
        rd = root_domain(domain)
        if rd not in domains:
            domains[rd] = p.get("brand", rd)

    # Delete any existing files that are not valid images (icon.horse HTML responses)
    invalid_deleted = 0
    for f in LOGOS_DIR.glob("*.png"):
        data_bytes = f.read_bytes()
        if not is_valid_image(data_bytes):
            f.unlink()
            invalid_deleted += 1

    if invalid_deleted:
        print(f"Deleted {invalid_deleted} invalid cached files (HTML responses masquerading as images)\n")

    total = len(domains)
    print(f"Downloading logos for {total} unique domains...\n")

    downloaded = skipped = failed = 0
    for i, (rd, brand) in enumerate(sorted(domains.items()), 1):
        fetch_domain = _DOMAIN_OVERRIDES.get(rd, rd)
        out_path = LOGOS_DIR / f"{rd}.png"
        if out_path.exists():
            skipped += 1
            continue

        display = f"{rd}" if fetch_domain == rd else f"{rd} → {fetch_domain}"
        sys.stdout.write(f"[{i}/{total}] {brand} ({display})... ")
        sys.stdout.flush()

        logo_bytes = fetch_logo(fetch_domain)
        if logo_bytes:
            out_path.write_bytes(logo_bytes)
            print(f"OK ({len(logo_bytes) // 1024} KB)")
            downloaded += 1
        else:
            print("FAIL")
            failed += 1

        time.sleep(0.5)

    print(f"\nDone: {downloaded} downloaded, {skipped} already cached, {failed} failed")
    print(f"Logos saved to: {LOGOS_DIR}")


if __name__ == "__main__":
    main()
