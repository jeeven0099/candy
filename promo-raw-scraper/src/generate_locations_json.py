"""
generate_locations_json.py — Merge all locations/*.json into a single
compact brand_locations.json for the Flutter app.

Output format:
{
  "generated_at": "...",
  "brands": {
    "Starbucks": [{"lat": 47.6, "lng": -122.3, "city": "Seattle", "state": "WA"}, ...]
  }
}
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCATIONS_DIR = ROOT / "locations"
NORMALIZED_DIR = ROOT / "normalized_outputs"
OUTPUT_FILE = ROOT.parent / "promo_viewer" / "assets" / "brand_locations.json"
CLOSED_FILE = ROOT / "closed_locations.json"


def _load_excluded() -> set[tuple[float, float]]:
    """Load manually curated closed-location coordinates to exclude."""
    if not CLOSED_FILE.exists():
        return set()
    try:
        data = json.loads(CLOSED_FILE.read_text(encoding="utf-8"))
        result = set()
        for entry in data.get("excluded", []):
            lat = entry.get("lat")
            lng = entry.get("lng")
            if lat is not None and lng is not None:
                result.add((round(float(lat), 4), round(float(lng), 4)))
        return result
    except Exception as exc:
        print(f"  [WARN] Could not load closed_locations.json: {exc}")
        return set()


def _brands_with_promotions() -> set[str]:
    brands: set[str] = set()
    for path in NORMALIZED_DIR.glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if data.get("promotions"):
                brands.add(data.get("brand", ""))
        except Exception:
            pass
    return brands


def main() -> None:
    active_brands = _brands_with_promotions()
    excluded = _load_excluded()
    files = sorted(f for f in LOCATIONS_DIR.glob("*.json") if f.is_file())
    brands: dict[str, list] = {}
    excluded_count = 0

    for path in files:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            brand = data.get("brand", "")
            locations = data.get("locations", [])
            if not brand or not locations or brand not in active_brands:
                continue

            # Keep only lat/lng at 4dp precision — sufficient for nearest-store lookup
            compact = []
            for loc in locations:
                lat = loc.get("lat")
                lng = loc.get("lng")
                if lat is None or lng is None:
                    continue
                coord = (round(lat, 4), round(lng, 4))
                if coord in excluded:
                    excluded_count += 1
                    continue
                compact.append(list(coord))

            if compact:
                brands[brand] = compact
        except Exception as exc:
            print(f"  [WARN] {path.stem}: {exc}")

    if excluded_count:
        print(f"Excluded {excluded_count} closed location(s) from closed_locations.json.")

    output = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "brand_count": len(brands),
        "brands": brands,
    }

    OUTPUT_FILE.write_text(
        json.dumps(output, indent=None, separators=(",", ":"), ensure_ascii=False),
        encoding="utf-8",
    )

    total_stores = sum(len(v) for v in brands.values())
    size_kb = OUTPUT_FILE.stat().st_size // 1024
    print(f"Wrote {len(brands)} brands, {total_stores} total stores -> {OUTPUT_FILE} ({size_kb} KB)")


if __name__ == "__main__":
    main()
