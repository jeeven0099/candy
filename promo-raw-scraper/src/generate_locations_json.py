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
OUTPUT_FILE = ROOT / "brand_locations.json"


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
    files = sorted(f for f in LOCATIONS_DIR.glob("*.json") if f.is_file())
    brands: dict[str, list] = {}

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
                compact.append([round(lat, 4), round(lng, 4)])

            if compact:
                brands[brand] = compact
        except Exception as exc:
            print(f"  [WARN] {path.stem}: {exc}")

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
