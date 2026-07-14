"""
apply_keyword_store.py — Re-apply backfill keyword patches after nightly pipeline runs.

The nightly pipeline regenerates all_promotions.json from normalized_outputs, which
overwrites any manual keyword patches from run_keyword_backfill.py. This script reads
keyword_store.json (built by the backfill) and patches back any promotion whose
keyword fields are still empty, without overwriting LLM-filled keywords.

Run this after each pipeline pass (wired into run_nightly.ps1).
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT         = Path(__file__).resolve().parents[1]
KEYWORD_STORE = ROOT / "keyword_store.json"
NORM_DIR     = ROOT / "normalized_outputs"
ASSETS_DIR   = ROOT.parent / "promo_viewer" / "assets"
ALL_PROMOS   = ASSETS_DIR / "all_promotions.json"
MERGED_PROMOS = ASSETS_DIR / "merged_promotions.json"


def _patch_file(path: Path, store: dict) -> tuple[int, int]:
    """Patch keyword fields in a promotions JSON file. Returns (files_patched, promos_patched)."""
    if not path.exists():
        return 0, 0
    data = json.loads(path.read_text(encoding="utf-8"))
    promos = data.get("promotions", data) if isinstance(data, dict) else data
    if not isinstance(promos, list):
        return 0, 0

    patched = 0
    for p in promos:
        brand = p.get("brand", "")
        if brand not in store:
            continue
        if p.get("product_keywords_explicit") or p.get("product_keywords_contextual"):
            continue  # LLM already filled — don't overwrite
        entry = store[brand]
        p["product_keywords_contextual"] = entry.get("contextual", [])[:25]
        p["product_keywords_explicit"]   = []
        if entry.get("categories"):
            p.setdefault("product_categories", entry["categories"][:5])
        patched += 1

    if patched:
        if isinstance(data, dict):
            data["promotions"] = promos
            path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
        else:
            path.write_text(json.dumps(promos, indent=2, ensure_ascii=False), encoding="utf-8")

    return 1 if patched else 0, patched


def main() -> None:
    if not KEYWORD_STORE.exists():
        print("No keyword_store.json found — nothing to apply.")
        return

    store = json.loads(KEYWORD_STORE.read_text(encoding="utf-8"))
    print(f"Keyword store: {len(store)} brand(s)")

    total_patched = 0

    # Patch normalized_outputs per brand
    norm_patched = 0
    for brand, entry in store.items():
        safe = "".join(c.lower() if c.isalnum() else "_" for c in brand).strip("_")
        while "__" in safe:
            safe = safe.replace("__", "_")
        norm_file = NORM_DIR / f"{safe}.json"
        _, n = _patch_file(norm_file, store)
        norm_patched += n

    print(f"  normalized_outputs: {norm_patched} promotion(s) patched")

    # Patch asset files
    _, n = _patch_file(ALL_PROMOS, store)
    print(f"  all_promotions.json: {n} promotion(s) patched")
    total_patched += n

    _, n = _patch_file(MERGED_PROMOS, store)
    print(f"  merged_promotions.json: {n} promotion(s) patched")
    total_patched += n

    print(f"Done. {total_patched} promotion(s) re-patched in asset files.")


if __name__ == "__main__":
    main()
