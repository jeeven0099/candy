"""
generate_scores.py — compute rank_base_score for every promotion.

Runs after generate_fast_redemption.py (needs fast_redemption data).

rank_base_score = value_score
               + fast_redeem_score
               + confidence_score_pts
               + freshness_score
               + preference_score      (from brand_affinity.json)
               - friction_penalty

Distance and membership bonuses are added at runtime in Flutter because
they require live geolocation and user membership data.
"""
from __future__ import annotations

import json
import re
from datetime import date, datetime, timezone
from pathlib import Path

ROOT         = Path(__file__).resolve().parents[1]
ALL_PROMOS   = ROOT / "all_promotions.json"
AFFINITY_LOG = ROOT / "email_pipeline" / "logs" / "brand_affinity.json"
USER_PREFS   = ROOT / "user_preferences.json"

# Category aliases — maps a user favourite to the raw category values in JSON
_CAT_ALIASES: dict[str, list[str]] = {
    "food":    ["food", "fast_food", "restaurant", "coffee", "grocery", "supermarket"],
    "travel":  ["travel", "hotels", "airlines", "automotive"],
    "fashion": ["fashion", "clothing", "apparel"],
    "tech":    ["tech", "electronics"],
    "beauty":  ["beauty", "personal_care"],
    "home":    ["home", "home_goods", "furniture"],
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _extract_percent(value: str | None) -> float | None:
    if not value:
        return None
    m = re.search(r"(\d+(?:\.\d+)?)\s*%", value)
    return float(m.group(1)) if m else None


def _extract_dollars(value: str | None) -> float | None:
    if not value:
        return None
    m = re.search(r"\$\s*(\d+(?:\.\d+)?)", value)
    return float(m.group(1)) if m else None


def _slugify(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def _brand_affinity_score(brand: str, affinity: dict) -> float:
    slug = _slugify(brand)
    for aff_brand, data in affinity.items():
        aff_slug = _slugify(aff_brand)
        if slug == aff_slug or slug in aff_slug or aff_slug in slug:
            count = data.get("email_count", 0)
            # 1–4 emails → +5, 5–9 → +10, 10+ → +15
            if count >= 10: return 15.0
            if count >= 5:  return 10.0
            if count >= 1:  return 5.0
    return 0.0


# ---------------------------------------------------------------------------
# Sub-scores
# ---------------------------------------------------------------------------

def value_score(promo: dict) -> float:
    dtype  = (promo.get("discount_type") or "").strip()
    dvalue = promo.get("discount_value")

    if dtype == "free_item":
        return 40.0

    if dtype == "percentage_off":
        pct = _extract_percent(dvalue)
        if pct is None:  return 20.0
        if pct >= 50:    return 38.0
        if pct >= 30:    return 30.0
        if pct >= 20:    return 24.0
        if pct >= 10:    return 18.0
        return 12.0

    if dtype == "amount_off":
        amt = _extract_dollars(dvalue)
        if amt is None:  return 18.0
        # $5→18  $10→20  $20→25  $50→33  cap at 35
        return min(35.0, 16.0 + amt * 0.38)

    if dtype == "sale_price":
        return 18.0

    if dtype == "free_shipping":
        return 12.0

    if dtype == "points":
        return 8.0

    return 10.0


def fast_redeem_score(promo: dict) -> float:
    fr = promo.get("fast_redemption") or {}
    if not fr.get("eligible"):
        return 0.0
    return {
        "copy_code_and_open_url": 20.0,
        "copy_code":              16.0,
        "open_url":               14.0,
        "open_app":               12.0,
        "open_rewards":            8.0,
        "show_barcode_or_code":    8.0,
        "open_maps":               6.0,
        "show_steps":              3.0,
    }.get(fr.get("action_type", ""), 0.0)


def confidence_score_pts(promo: dict) -> float:
    c = promo.get("confidence_score") or 0.0
    if c >= 0.90: return 18.0
    if c >= 0.80: return 16.0
    if c >= 0.75: return 15.0
    if c >= 0.65: return 13.0
    return 0.0


def freshness_score(promo: dict) -> float:
    today = date.today()

    # Explicit future expiry is the strongest freshness signal
    end = (promo.get("end_date") or "").strip()
    if end:
        try:
            if date.fromisoformat(end[:10]) >= today:
                return 25.0
        except ValueError:
            pass

    # Fall back to scrape timestamp
    scraped_raw = promo.get("scraped_at") or promo.get("checked_at") or ""
    if scraped_raw:
        try:
            scraped_dt = datetime.fromisoformat(
                scraped_raw.replace("Z", "+00:00")
            )
            days_old = (datetime.now(timezone.utc) - scraped_dt).days
            if days_old == 0:   return 20.0
            if days_old <= 7:   return 15.0
            if days_old <= 14:  return 8.0
            return -5.0
        except ValueError:
            pass

    return 5.0  # age unknown — neutral


def preference_score(promo: dict, affinity: dict, user_prefs: dict) -> float:
    score = 0.0
    brand    = promo.get("brand", "")
    category = (promo.get("category") or "").lower().strip()

    # Favourite brand match (+15)
    fav_brands = [_slugify(b) for b in user_prefs.get("favorite_brands", [])]
    brand_slug = _slugify(brand)
    if any(brand_slug == fb or brand_slug in fb or fb in brand_slug
           for fb in fav_brands if fb):
        score += 15.0

    # Favourite category match (+10)
    fav_cats = [c.lower() for c in user_prefs.get("favorite_categories", [])]
    for fav_cat in fav_cats:
        aliases = _CAT_ALIASES.get(fav_cat, [fav_cat])
        if category in aliases:
            score += 10.0
            break

    # Brand affinity from email (+5–15)
    score += _brand_affinity_score(brand, affinity)

    # Birthday-month boost (+25) — lasts the whole calendar month
    birthday_str = user_prefs.get("birthday", "")
    if birthday_str:
        try:
            bday = date.fromisoformat(birthday_str)
            if date.today().month == bday.month:
                score += 25.0
        except ValueError:
            pass

    return score


def friction_penalty(promo: dict) -> float:
    penalty = 0.0

    # Membership friction
    if promo.get("requires_membership"):
        cost = (promo.get("membership_cost") or "").lower()
        if "paid" in cost:
            penalty += 15.0
        elif "free" in cost:
            penalty += 2.0
        else:
            penalty += 8.0   # unknown membership type

    # App required
    if promo.get("requires_app"):
        penalty += 5.0

    # Minimum spend creates friction
    if promo.get("minimum_spend"):
        penalty += 4.0

    # Participating-locations language
    terms = (promo.get("terms_text") or "").lower()
    if "participating" in terms:
        penalty += 4.0

    # Redemption effort from fast_redemption
    fr = promo.get("fast_redemption") or {}
    effort = (fr.get("effort_level") or "unknown").lower()
    if effort == "high":
        penalty += 8.0
    elif effort == "medium":
        penalty += 4.0
    elif effort == "unknown":
        penalty += 5.0

    return penalty


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def compute_base_score(promo: dict, affinity: dict, user_prefs: dict) -> float:
    return round(
        value_score(promo)
        + fast_redeem_score(promo)
        + confidence_score_pts(promo)
        + freshness_score(promo)
        + preference_score(promo, affinity, user_prefs)
        - friction_penalty(promo),
        2,
    )


def main() -> None:
    data   = json.loads(ALL_PROMOS.read_text(encoding="utf-8"))
    promos = data.get("promotions", []) if isinstance(data, dict) else data

    affinity: dict = {}
    if AFFINITY_LOG.exists():
        raw = json.loads(AFFINITY_LOG.read_text(encoding="utf-8"))
        affinity = raw.get("brands", raw) if isinstance(raw, dict) else {}

    user_prefs: dict = {}
    if USER_PREFS.exists():
        user_prefs = json.loads(USER_PREFS.read_text(encoding="utf-8"))
        print(f"  User prefs: birthday={user_prefs.get('birthday')} "
              f"brands={user_prefs.get('favorite_brands')} "
              f"cats={user_prefs.get('favorite_categories')}")

    scores: list[float] = []
    for p in promos:
        s = compute_base_score(p, affinity, user_prefs)
        p["rank_base_score"] = s
        scores.append(s)

    if isinstance(data, dict):
        data["promotions"] = promos
    ALL_PROMOS.write_text(
        json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    if scores:
        print(f"Scores computed for {len(scores)} promotions")
        print(f"  min={min(scores):.1f}  max={max(scores):.1f}  "
              f"avg={sum(scores)/len(scores):.1f}")
    print(f"Wrote -> {ALL_PROMOS}")


if __name__ == "__main__":
    main()
