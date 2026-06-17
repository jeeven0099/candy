from __future__ import annotations

import argparse
import json
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional

import urllib3
import requests

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

from models import StoreLocation
from source_loader import filter_sources, load_sources


ROOT = Path(__file__).resolve().parents[1]
LOCATIONS_DIR = ROOT / "locations"
SOURCES_FILE = ROOT / "sources" / "urls.json"
ALIASES_FILE = ROOT / "sources" / "osm_aliases.json"

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
CONTIGUOUS_US_BBOX = "24.396308,-124.848974,49.384358,-66.885444"

# Seconds to wait before retrying after a 429 or 504
_RETRY_DELAY = 30

# Overpass-level filters to exclude obviously closed stores
_CLOSED_FILTERS = (
    '["disused"!="yes"]'
    '["abandoned"!="yes"]'
    '["shop"!="vacant"]'
    '["shop"!="no"]'
)

# OSM key prefixes that mark a feature as closed/removed
_CLOSED_KEY_PREFIXES = ("disused:", "abandoned:", "demolished:", "razed:", "was:")


def slugify(value: str) -> str:
    safe = "".join(ch.lower() if ch.isalnum() else "_" for ch in value)
    while "__" in safe:
        safe = safe.replace("__", "_")
    return safe.strip("_") or "unknown"


def load_aliases() -> Dict[str, dict]:
    if ALIASES_FILE.exists():
        return json.loads(ALIASES_FILE.read_text(encoding="utf-8"))
    return {}


def build_overpass_query(
    osm_name: Optional[str],
    osm_name_regex: Optional[str],
    extra_tags: Optional[Dict[str, str]] = None,
    case_insensitive: bool = False,
) -> str:
    if osm_name_regex:
        pattern = osm_name_regex if ("^" in osm_name_regex or "$" in osm_name_regex) else f"^{osm_name_regex}$"
        ci_flag = ",i" if case_insensitive else ""
        name_filter = f'["name"~"{pattern}"{ci_flag}]'
    else:
        escaped = (osm_name or "").replace("\\", "\\\\").replace('"', '\\"')
        name_filter = f'["name"="{escaped}"]'

    tag_filters = name_filter
    for key, val in (extra_tags or {}).items():
        val_escaped = val.replace('"', '\\"')
        tag_filters += f'["{key}"="{val_escaped}"]'

    return (
        f'[out:json][timeout:180];\n'
        f'(\n'
        f'  node{tag_filters}{_CLOSED_FILTERS}({CONTIGUOUS_US_BBOX});\n'
        f'  way{tag_filters}{_CLOSED_FILTERS}({CONTIGUOUS_US_BBOX});\n'
        f');\n'
        f'out center;'
    )


def fetch_overpass(
    brand_name: str,
    aliases: Dict[str, dict],
    timeout: int = 210,
) -> List[StoreLocation]:
    alias = aliases.get(brand_name, {})
    osm_name = alias.get("osm_name", brand_name if not alias.get("osm_name_regex") else None)
    osm_name_regex = alias.get("osm_name_regex")
    extra_tags = alias.get("extra_tags")
    case_insensitive = bool(alias.get("case_insensitive", False))

    query = build_overpass_query(osm_name, osm_name_regex, extra_tags, case_insensitive)

    for attempt in (1, 2):
        try:
            response = requests.post(
                OVERPASS_URL,
                data={"data": query},
                timeout=timeout,
                headers={"User-Agent": "promo-scraper-location/1.0"},
                verify=False,
            )
        except requests.Timeout:
            raise RuntimeError(f"Overpass API timed out for '{brand_name}'")
        except requests.RequestException as exc:
            raise RuntimeError(f"Overpass API error for '{brand_name}': {exc}")

        if response.status_code in (429, 504):
            if attempt == 1:
                print(f"  [{response.status_code}] retrying in {_RETRY_DELAY}s ...", end=" ", flush=True)
                time.sleep(_RETRY_DELAY)
                continue
            raise RuntimeError(f"Overpass API {response.status_code} for '{brand_name}' after retry")

        try:
            response.raise_for_status()
        except requests.RequestException as exc:
            raise RuntimeError(f"Overpass API request failed for '{brand_name}': {exc}")

        return _parse_elements(response.json(), brand_name)

    raise RuntimeError(f"Overpass API failed for '{brand_name}' after retries")


def _is_closed(tags: dict) -> bool:
    """Return True if OSM tags indicate a permanently or temporarily closed store."""
    if any(k.startswith(p) for k in tags for p in _CLOSED_KEY_PREFIXES):
        return True
    if tags.get("disused") == "yes" or tags.get("abandoned") == "yes":
        return True
    if tags.get("shop") in ("vacant", "no"):
        return True
    return False


def _parse_elements(data: dict, brand: str) -> List[StoreLocation]:
    locations: List[StoreLocation] = []

    for element in data.get("elements", []):
        tags = element.get("tags", {})

        if _is_closed(tags):
            continue

        if element["type"] == "node":
            lat = element.get("lat")
            lng = element.get("lon")
        elif "center" in element:
            lat = element["center"].get("lat")
            lng = element["center"].get("lon")
        else:
            continue

        if lat is None or lng is None:
            continue

        locations.append(StoreLocation(
            osm_id=str(element.get("id")),
            name=tags.get("name", brand),
            address=tags.get("addr:street"),
            city=tags.get("addr:city"),
            state=tags.get("addr:state"),
            zip=tags.get("addr:postcode"),
            lat=lat,
            lng=lng,
            phone=tags.get("phone") or tags.get("contact:phone"),
        ))

    return locations


def save_locations(brand: str, locations: List[StoreLocation], source_url: str) -> Path:
    LOCATIONS_DIR.mkdir(parents=True, exist_ok=True)

    output_path = LOCATIONS_DIR / f"{slugify(brand)}.json"

    payload = {
        "brand": brand,
        "last_updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "location_count": len(locations),
        "locations": [loc.model_dump() for loc in locations],
    }

    output_path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    return output_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch US store locations for brands via OpenStreetMap Overpass API."
    )
    parser.add_argument("--brand", type=str, default=None, help="Filter by brand substring")
    parser.add_argument("--category", type=str, default=None, help="Filter by category")
    parser.add_argument("--limit", type=int, default=None, help="Max brands to process")
    parser.add_argument(
        "--delay",
        type=float,
        default=8.0,
        help="Seconds between requests. Default: 8",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-fetch brands that already have a location file.",
    )
    args = parser.parse_args()

    aliases = load_aliases()

    sources = load_sources(SOURCES_FILE)
    selected = filter_sources(
        sources,
        brand=args.brand,
        category=args.category,
        limit=args.limit,
        allowed_only=False,
    )

    seen: set[str] = set()
    unique = []
    for source in selected:
        if source.brand not in seen:
            seen.add(source.brand)
            unique.append(source)

    # Filter out brands that already have a location file unless --force is set
    if not args.force:
        pending = [s for s in unique if not (LOCATIONS_DIR / f"{slugify(s.brand)}.json").exists()]
        skipped = len(unique) - len(pending)
        if skipped:
            print(f"Skipping {skipped} brand(s) with existing location files (use --force to re-fetch).")
        unique = pending

    print(f"Fetching locations for {len(unique)} brand(s) via Overpass API...")

    for i, source in enumerate(unique):
        if i > 0:
            time.sleep(args.delay)

        print(f"[{i + 1}/{len(unique)}] {source.brand} ...", end=" ", flush=True)

        try:
            locations = fetch_overpass(source.brand, aliases)
            output_path = save_locations(source.brand, locations, source.url)
            print(f"{len(locations)} locations → {output_path.name}")
        except Exception as exc:
            print(f"FAILED: {exc}")


if __name__ == "__main__":
    main()
