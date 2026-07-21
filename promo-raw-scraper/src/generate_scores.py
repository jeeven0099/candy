"""
generate_scores.py — compute global_quality_score for every promotion.

Runs after generate_fast_redemption.py (needs fast_redemption data).

Formula
-------
global_quality_score =
    (economic_value_score + presentation_strength_score) × reliability_multiplier
    + fast_redeem_score
    + source_freshness_score
    + urgency_effect
    - friction_penalty

economic_value_score  (0–80):
    0.55 × relative_discount_score(effective_pct, 0–30)
  + 0.45 × absolute_savings_score(savings, cat, 0–50)
  − required_spend_penalty(savings, min_spend, 0–12)
  − quantity_burden_penalty(promo, 0–10)

presentation_strength_score  (0–8):
    free_framing (+4), clear_price (+2), promo_code (+2)

reliability_multiplier (0.65–1.00):
    confidence acts as a multiplicative quality gate, not an additive bonus.
    Confidence < 0.60 → flagged low-confidence, heavily discounted.

source_freshness_score (−8 to +8):
    How recently was this scraped?

expiration_urgency_score (0–5):
    How soon does it expire?

urgency_effect = expiration_urgency_score × min(economic_value_score / 35, 1.0)
    Urgency amplifies worthwhile deals; it cannot rescue weak ones.
"""
from __future__ import annotations

import json
import math
import re
from datetime import date, datetime, timezone
from pathlib import Path

ROOT       = Path(__file__).resolve().parents[1]
ALL_PROMOS = ROOT / "all_promotions.json"


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


# ---------------------------------------------------------------------------
# Item value tables
# ---------------------------------------------------------------------------

_CATEGORY_ITEM_VALUE: dict[str, float] = {
    "food":          10.0,
    "fast_food":      9.0,
    "coffee":         6.0,
    "restaurant":    18.0,
    "grocery":        5.0,
    "supermarket":    5.0,
    "beauty":        22.0,
    "personal_care": 15.0,
    "fashion":       65.0,
    "clothing":      55.0,
    "apparel":       55.0,
    "retail":        45.0,
    "shoes":         95.0,
    "footwear":      95.0,
    "tech":         250.0,
    "electronics":  250.0,
    "home":          90.0,
    "home_goods":    90.0,
    "furniture":    200.0,
    "travel":       200.0,
    "hotels":       180.0,
    "airlines":     280.0,
    "automotive":    75.0,
    "gas":           55.0,
    "entertainment": 14.0,
    "movies":        14.0,
}

_BRAND_ITEM_VALUE_RAW: dict[str, float] = {
    "mcdonalds": 8.0, "burger king": 8.0, "wendys": 9.0,
    "chickfila": 10.0, "popeyes": 10.0, "kfc": 9.0,
    "taco bell": 8.0, "del taco": 8.0,
    "chipotle": 12.0, "qdoba": 12.0,
    "subway": 10.0, "jersey mikes": 11.0, "jimmy johns": 10.0,
    "panera bread": 13.0, "shake shack": 13.0, "five guys": 13.0,
    "sonic": 9.0, "raising canes": 10.0, "whataburger": 10.0,
    "jack in the box": 9.0, "wingstop": 12.0, "buffalo wild wings": 15.0,
    "ihop": 14.0, "dennys": 13.0, "cracker barrel": 15.0,
    "outback steakhouse": 28.0, "texas roadhouse": 20.0,
    "longhorn steakhouse": 28.0, "red lobster": 28.0,
    "applebees": 16.0, "chilis": 16.0,
    "starbucks": 6.5, "dunkin": 5.0, "dutch bros": 5.5,
    "peets coffee": 6.0, "caribou coffee": 6.0,
    "einstein bros bagels": 6.0, "krispy kreme": 4.0,
    "jamba": 7.0, "smoothie king": 7.0, "tropical smoothie cafe": 7.0,
    "whole foods market": 8.0, "trader joes": 6.0,
    "costco": 80.0, "sams club": 60.0, "bjs wholesale club": 60.0,
    "sephora": 35.0, "ulta beauty": 28.0,
    "mac cosmetics": 32.0, "charlotte tilbury": 48.0,
    "fenty beauty": 36.0, "nars": 42.0, "tarte cosmetics": 32.0,
    "too faced": 28.0, "urban decay": 30.0, "benefit cosmetics": 28.0,
    "elf cosmetics": 12.0, "colourpop": 14.0, "nyx": 12.0,
    "il makiage": 42.0, "the ordinary": 12.0,
    "kiehls": 35.0,
    "gap": 40.0, "old navy": 35.0, "banana republic": 75.0,
    "jcrew": 65.0, "ann taylor": 80.0, "loft": 55.0,
    "abercrombie fitch": 70.0, "hollister": 45.0,
    "american eagle": 50.0, "aerie": 35.0,
    "zara": 55.0, "hm": 35.0, "uniqlo": 40.0,
    "madewell": 80.0, "free people": 90.0, "anthropologie": 90.0,
    "coach": 380.0, "kate spade": 280.0, "michael kors": 220.0,
    "tory burch": 260.0, "vera bradley": 60.0,
    "lululemon": 85.0, "fabletics": 65.0, "gymshark": 55.0,
    "alo yoga": 90.0, "vuori": 80.0,
    "patagonia": 120.0, "the north face": 120.0,
    "columbia": 90.0, "eddie bauer": 90.0, "llbean": 80.0,
    "nike": 105.0, "adidas": 95.0, "new balance": 115.0,
    "hoka": 145.0, "asics": 125.0, "brooks running": 135.0,
    "saucony": 125.0, "allbirds": 120.0,
    "ugg": 160.0, "timberland": 135.0,
    "dr martens": 150.0, "crocs": 55.0, "hey dude": 55.0,
    "sperry": 85.0, "clarks": 90.0, "aldo": 80.0, "steve madden": 90.0,
    "cole haan": 150.0, "converse": 70.0, "vans": 70.0,
    "foot locker": 100.0, "finish line": 100.0, "dsw": 80.0,
    "skechers": 75.0,
    "best buy": 280.0, "dell": 800.0,
    "newegg": 250.0, "micro center": 300.0,
    "bh photo": 400.0, "adorama": 400.0,
    "amc theatres": 14.0, "cinemark": 13.0, "regal": 13.0, "fandango": 15.0,
    "marriott": 190.0, "hilton": 175.0, "wyndham hotels": 120.0,
    "delta air lines": 320.0, "southwest airlines": 250.0,
    "jetblue": 210.0, "spirit airlines": 120.0, "frontier airlines": 100.0,
    "enterprise": 60.0, "avis": 65.0,
}

_BRAND_VALUE_LOOKUP: dict[str, float] = {
    _slugify(k): v for k, v in _BRAND_ITEM_VALUE_RAW.items()
}

_BRAND_CONSERVATIVE_RAW: dict[str, float] = {
    "coach": 75.0, "kate spade": 60.0, "michael kors": 55.0,
    "tory burch": 65.0, "vera bradley": 30.0,
    "lululemon": 45.0, "fabletics": 35.0, "gymshark": 35.0,
    "alo yoga": 50.0, "vuori": 40.0,
    "the north face": 65.0, "patagonia": 70.0,
    "columbia": 50.0, "eddie bauer": 50.0, "llbean": 45.0,
    "nike": 50.0, "adidas": 45.0, "new balance": 60.0,
    "hoka": 80.0, "asics": 65.0, "brooks running": 70.0,
    "saucony": 65.0, "ugg": 80.0, "timberland": 70.0,
    "dr martens": 80.0, "allbirds": 60.0, "cole haan": 75.0,
    "banana republic": 40.0, "jcrew": 38.0, "ann taylor": 42.0,
    "madewell": 45.0, "free people": 50.0, "anthropologie": 50.0,
    "abercrombie fitch": 38.0, "gap": 28.0, "old navy": 22.0,
    "sephora": 18.0, "ulta beauty": 15.0,
    "mac cosmetics": 18.0, "charlotte tilbury": 28.0,
    "fenty beauty": 20.0, "nars": 22.0,
    "best buy": 50.0, "dell": 150.0,
    "newegg": 60.0, "micro center": 80.0,
    "marriott": 100.0, "hilton": 90.0, "wyndham hotels": 70.0,
    "delta air lines": 140.0, "southwest airlines": 110.0, "jetblue": 100.0,
}

_BRAND_CONSERVATIVE_LOOKUP: dict[str, float] = {
    _slugify(k): v for k, v in _BRAND_CONSERVATIVE_RAW.items()
}

_CATEGORY_CONSERVATIVE_VALUE: dict[str, float] = {
    "fashion": 28.0, "clothing": 25.0, "apparel": 25.0, "retail": 20.0,
    "shoes": 50.0, "footwear": 50.0,
    "beauty": 14.0, "personal_care": 12.0,
    "tech": 60.0, "electronics": 60.0,
    "home": 35.0, "home_goods": 30.0, "furniture": 80.0,
    "travel": 80.0, "hotels": 80.0, "airlines": 100.0,
}

# Category-specific savings caps for the log-scale absolute savings score.
# Represents the maximum realistic savings in each category; scores are
# capped at 50 points when savings equal or exceed this threshold.
_CATEGORY_SAVINGS_CAP: dict[str, float] = {
    "food":          15.0,  "fast_food":    12.0,
    "coffee":         8.0,  "restaurant":   25.0,
    "grocery":       25.0,  "supermarket":  25.0,
    "beauty":        50.0,  "personal_care":30.0,
    "fashion":       60.0,  "clothing":     50.0,
    "apparel":       50.0,  "retail":       40.0,
    "shoes":         80.0,  "footwear":     80.0,
    "tech":         150.0,  "electronics": 150.0,
    "home":         100.0,  "home_goods":   80.0,
    "furniture":    200.0,
    "travel":       200.0,  "hotels":      150.0,  "airlines":    250.0,
    "automotive":   100.0,  "gas":          25.0,
    "entertainment": 20.0,  "movies":       15.0,
}

# Categories where multi-buy deals have low burden (consumers buy repeatedly).
_REPEAT_PURCHASE_CATS = frozenset({
    "food", "fast_food", "coffee", "grocery", "supermarket",
    "restaurant", "beauty", "personal_care",
})
# Categories where multi-buy creates high burden (infrequent, expensive purchases).
_SINGLE_PURCHASE_CATS = frozenset({
    "tech", "electronics", "furniture", "travel", "hotels", "airlines", "automotive",
})

_ITEM_TYPE_HINTS: list[tuple[re.Pattern, float]] = [
    (re.compile(r"\bfries?\b|\bchips?\b|\bside\b", re.I),                              3.5),
    (re.compile(r"\bcoffee\b|\bteas?\b|\bespresso\b|\bamericano\b", re.I),              5.5),
    (re.compile(r"\blattes?\b|\bcappuccino\b|\bmacchiato\b|\bfrapp", re.I),             6.5),
    (re.compile(r"\bsmoothies?\b|\bshakes?\b|\bmilkshake\b", re.I),                    7.0),
    (re.compile(r"\bdrinks?\b|\bbeverages?\b|\bsodas?\b|\bfountain\b", re.I),           4.0),
    (re.compile(r"\bdonuts?\b|\bdoughnuts?\b|\bmuffins?\b|\bbagels?\b|\bpastries?\b", re.I), 3.5),
    (re.compile(r"\bcookies?\b|\bbrownies?\b", re.I),                                  2.5),
    (re.compile(r"\bburgers?\b|\bwhopper\b|\bbig mac\b", re.I),                        9.0),
    (re.compile(r"\bsandwiches?\b|\bsubs?\b|\bwraps?\b|\bhoagies?\b", re.I),          10.0),
    (re.compile(r"\btacos?\b|\bburritos?\b|\bquesadillas?\b|\bbowls?\b", re.I),        10.0),
    (re.compile(r"\bentr[eé]es?\b|\bmeals?\b|\bcombos?\b", re.I),                     11.0),
    (re.compile(r"\bpizzas?\b", re.I),                                                 13.0),
    (re.compile(r"\bscoops?\b|\bice\s+cream\b|\bgelato\b", re.I),                      5.0),
    (re.compile(r"\blipsticks?\b|\blip\s+colors?\b|\blip\s+gloss\b", re.I),           18.0),
    (re.compile(r"\bmascaras?\b|\beyeliners?\b|\bconcealers?\b|\beyeshadows?\b", re.I),16.0),
    (re.compile(r"\bfoundations?\b", re.I),                                            28.0),
    (re.compile(r"\bserums?\b|\bmoisturizers?\b|\bface\s+cream\b", re.I),              25.0),
    (re.compile(r"\bhoodies?\b|\bsweaters?\b|\bsweatshirts?\b", re.I),                55.0),
    (re.compile(r"\bjackets?\b|\bcoats?\b|\bvests?\b|\bparkas?\b", re.I),             75.0),
    (re.compile(r"\bjeans?\b|\bdenim\b|\bpants?\b|\btrousers?\b|\bleggings?\b", re.I),55.0),
    (re.compile(r"\bdresses?\b|\bblouses?\b|\bskirts?\b|\bgowns?\b", re.I),           60.0),
    (re.compile(r"\bshirts?\b|\btees?\b|\btops?\b|\btanks?\b", re.I),                 30.0),
    (re.compile(r"\bsneakers?\b|\bshoes?\b|\bboots?\b|\bsandals?\b|\bheels?\b", re.I),90.0),
    (re.compile(r"\bhandbags?\b|\bpurses?\b|\btotes?\b", re.I),                      120.0),
    (re.compile(r"\bwallets?\b|\bcard\s+holders?\b|\bwristlets?\b", re.I),             55.0),
    (re.compile(r"\bbags?\b", re.I),                                                  100.0),
]

_BOGO_RE       = re.compile(r'\bbogo\b|buy.one.get.one', re.IGNORECASE)
_BUY_X_GET_Y   = re.compile(r'buy\s+(\d+)\s+get\s+(\d+)', re.IGNORECASE)
_TRIAL_RE      = re.compile(r'\bfree\s+trial\b|\btrial\b|\d+\s+(?:months?|weeks?|days?)\s+free', re.IGNORECASE)
_SITEWIDE_RE   = re.compile(r'\bsitewide\b', re.IGNORECASE)
_VAGUE_RE      = re.compile(
    r'\bselect\s+(?:styles?|items?|products?)\b'
    r'|\bsitewide\b'
    r'|\byour\s+(?:order|purchase)\b'
    r'|\beverything\b'
    r'|\ball\s+(?:items?|styles?|orders?|purchases?)\b'
    r'|\bfull[\s-]price\b'
    r'|\bregular[\s-]price\b',
    re.IGNORECASE,
)


# ---------------------------------------------------------------------------
# Estimation helpers
# ---------------------------------------------------------------------------

def _estimate_item_value(promo: dict) -> float:
    brand_slug = _slugify(promo.get("brand") or "")
    if brand_slug in _BRAND_VALUE_LOOKUP:
        return _BRAND_VALUE_LOOKUP[brand_slug]
    if len(brand_slug) >= 5:
        for slug, val in _BRAND_VALUE_LOOKUP.items():
            if len(slug) >= 5 and brand_slug[:7] == slug[:7]:
                return val
    cat = (promo.get("category") or "").lower().strip()
    return _CATEGORY_ITEM_VALUE.get(cat, 30.0)


def _infer_item_value_from_title(title: str) -> float | None:
    for pattern, val in _ITEM_TYPE_HINTS:
        if pattern.search(title):
            return val
    return None


def _estimate_free_item_value(promo: dict) -> float:
    title = promo.get("promotion_title") or ""
    title_val = _infer_item_value_from_title(title)
    if title_val is not None:
        return title_val
    return min(_estimate_item_value(promo), 15.0)


def _conservative_item_value(promo: dict) -> float:
    brand_slug = _slugify(promo.get("brand") or "")
    if brand_slug in _BRAND_CONSERVATIVE_LOOKUP:
        return _BRAND_CONSERVATIVE_LOOKUP[brand_slug]
    if len(brand_slug) >= 5:
        for slug, val in _BRAND_CONSERVATIVE_LOOKUP.items():
            if len(slug) >= 5 and brand_slug[:7] == slug[:7]:
                return val
    cat = (promo.get("category") or "").lower().strip()
    if cat in _CATEGORY_CONSERVATIVE_VALUE:
        return _CATEGORY_CONSERVATIVE_VALUE[cat]
    return _estimate_item_value(promo) * 0.5


def _compute_estimated_savings(promo: dict) -> tuple[float, float, str]:
    """Returns (item_value, estimated_savings_dollars, reason_snippet)."""
    dtype  = (promo.get("discount_type") or "").strip()
    dvalue = promo.get("discount_value") or ""
    title  = promo.get("promotion_title") or ""
    ptype  = (promo.get("promotion_type") or "").strip()

    item_val = _estimate_item_value(promo)

    if ptype == "birthday_reward" or promo.get("birthday_related"):
        free_val = _estimate_free_item_value(promo)
        return item_val, free_val, f"birthday reward, est. free item ≈ ${free_val:.0f}"

    if _BOGO_RE.search(title):
        # B1G1F: you pay for 1 item, get 1 free — savings = full item value
        savings = item_val
        return item_val, savings, f"BOGO (B1G1F), free item ≈ ${savings:.0f} savings"

    bxy_m = _BUY_X_GET_Y.search(title)
    if bxy_m:
        # e.g. "buy 2 get 1 free" — savings = one item free regardless of quantity
        savings = item_val
        get_n_m = int(bxy_m.group(2))
        return item_val, savings, f"buy X get {get_n_m} free, free item ≈ ${savings:.0f} savings"

    if dtype == "free_item":
        if _TRIAL_RE.search(title):
            return item_val, 5.0, "free trial, nominal value ≈ $5"
        free_val = _estimate_free_item_value(promo)
        return item_val, free_val, f"free item, est. ≈ ${free_val:.0f} savings"

    if dtype == "percentage_off":
        pct         = _extract_percent(dvalue)
        is_vague    = bool(_VAGUE_RE.search(title))
        title_val   = _infer_item_value_from_title(title)
        if pct:
            if title_val is not None:
                item_val_used = title_val
                tier = f"specific item in title (${title_val:.0f})"
            elif is_vague:
                item_val_used = _conservative_item_value(promo)
                tier = f"vague deal, conservative est. (${item_val_used:.0f})"
            else:
                item_val_used = item_val
                tier = f"brand/cat est. (${item_val_used:.0f})"
            savings = round(item_val_used * pct / 100.0, 2)
            return item_val, savings, f"{pct:.0f}% off, {tier} ≈ ${savings:.0f} savings"
        if is_vague or _SITEWIDE_RE.search(title):
            conservative = _conservative_item_value(promo)
            savings = round(conservative * 0.20, 2)
            return item_val, savings, f"vague/sitewide % off, conservative est. ${conservative:.0f} ≈ ${savings:.0f} savings"
        return item_val, round(item_val * 0.15, 2), "% off (unparseable), est. 15% of brand/cat value"

    if dtype == "amount_off":
        amt = _extract_dollars(dvalue)
        if amt:
            return item_val, amt, f"${amt:.0f} off"
        return item_val, 8.0, "$ off (no amount parsed), est. $8"

    if dtype == "sale_price":
        base = _conservative_item_value(promo) if _VAGUE_RE.search(title) else item_val
        savings = round(base * 0.20, 2)
        return item_val, savings, f"sale price, est. 20% off ${base:.0f} ≈ ${savings:.0f} savings"

    if dtype == "free_shipping":
        cat = (promo.get("category") or "").lower()
        shipping_est = 10.0 if cat in ("tech", "electronics", "furniture", "home", "home_goods") else \
                        8.0 if cat in ("fashion", "clothing", "shoes", "footwear", "apparel", "retail") else 5.0
        return item_val, shipping_est, f"free shipping ≈ ${shipping_est:.0f} savings"

    if dtype == "points":
        return item_val, 2.0, "points/rewards, nominal value ≈ $2"

    return item_val, 5.0, "unknown deal type, est. $5 savings"


def _compute_effective_discount_pct(promo: dict, savings: float, item_val: float) -> float:
    """Effective discount percentage for relative_discount_score."""
    dtype = (promo.get("discount_type") or "").strip()
    dvalue = promo.get("discount_value") or ""
    title  = promo.get("promotion_title") or ""

    if dtype == "free_item" and not _TRIAL_RE.search(title):
        return 100.0

    if _BOGO_RE.search(title):
        return 50.0  # B1G1F: 2 items received, 1 paid → 50% off received value

    bxy = _BUY_X_GET_Y.search(title)
    if bxy:
        buy_n = int(bxy.group(1))
        get_n = int(bxy.group(2))
        # e.g. buy 2 get 1 free → 1/(2+1) = 33.3%
        return round(get_n / (buy_n + get_n) * 100.0, 1)

    if dtype == "percentage_off":
        pct = _extract_percent(dvalue)
        return pct if pct else 15.0

    if dtype == "amount_off" and item_val > 0:
        return min(savings / item_val * 100.0, 100.0)

    if dtype == "sale_price":
        return 20.0

    if dtype == "free_shipping":
        return 8.0  # ~8% relative to a typical order

    if dtype == "points":
        return 1.5  # points rarely return >1.5%

    return 10.0


def _parse_minimum_spend(promo: dict) -> float | None:
    """Parse minimum_spend field to a dollar amount, or None if absent/unparseable."""
    ms = promo.get("minimum_spend")
    if not ms:
        return None
    if isinstance(ms, (int, float)):
        return float(ms) if ms > 0 else None
    if isinstance(ms, str):
        amt = _extract_dollars(ms)
        if amt is not None:
            return amt
        try:
            return float(ms.replace(",", "").strip())
        except ValueError:
            return None  # truthy string but unparseable — treat as friction only
    return None


def _bogo_intrinsic_spend(promo: dict, item_val: float) -> float | None:
    """
    Intrinsic spend requirement embedded in BOGO / multi-buy deal structures.
    Used alongside required_spend_penalty so threshold efficiency is computed
    correctly even when no explicit minimum_spend field exists.

    B1G1F ("bogo", "buy one get one"): you pay for 1 item → efficiency = 100% → no penalty.
    B2G1F ("buy 2 get 1 free"): you pay for 2 items → efficiency = 50% → moderate penalty.
    Other multi-buy: scaled by the number of units that must be purchased.
    """
    title = promo.get("promotion_title") or ""
    if _BOGO_RE.search(title):
        return item_val  # pay for 1 item to receive 2
    bxy = _BUY_X_GET_Y.search(title)
    if bxy:
        buy_n = int(bxy.group(1))
        return item_val * buy_n  # pay for buy_n items to receive buy_n + get_n
    return None


def _quantity_burden_weight(category: str) -> float:
    """
    How much does requiring multiple units burden the user?
    Repeat-purchase categories (coffee, groceries) → low burden.
    Single-purchase categories (tech, furniture) → high burden.
    """
    cat = category.lower()
    if cat in _REPEAT_PURCHASE_CATS: return 0.1
    if cat in _SINGLE_PURCHASE_CATS: return 0.85
    return 0.4  # fashion, retail, shoes: moderate


# ---------------------------------------------------------------------------
# Sub-scores
# ---------------------------------------------------------------------------

def relative_discount_score(effective_pct: float) -> float:
    """Map effective discount % to 0–30 using a log curve (sub-linear at high %)."""
    if effective_pct <= 0:
        return 0.0
    p = min(effective_pct, 100.0) / 100.0
    # 10% → 5.4,  20% → 9.3,  30% → 12.9,  50% → 18.2,  75% → 23.1,  100% → 27
    score = 27.0 * math.log(1 + p * 3.5) / math.log(4.5)
    return round(min(score, 27.0), 2)


def absolute_savings_score(savings: float, category: str) -> float:
    """Dollar savings → 0–50, log-scaled relative to category savings cap."""
    if savings <= 0:
        return 0.0
    cat_cap = _CATEGORY_SAVINGS_CAP.get(category.lower(), 50.0)
    score = 50.0 * math.log(1 + savings) / math.log(1 + cat_cap)
    return round(min(score, 50.0), 2)


def presentation_strength_score(promo: dict) -> float:
    """
    Small bonus for deal framing that improves consumer attention:
    free framing, clear stated price/percentage, promo code available.
    Capped at 8 — presentation cannot substitute for economic value.
    """
    dtype  = (promo.get("discount_type") or "").strip()
    dvalue = promo.get("discount_value") or ""
    title  = promo.get("promotion_title") or ""
    score  = 0.0

    if dtype == "free_item" and not _TRIAL_RE.search(title):
        score += 4.0
    elif _BOGO_RE.search(title):
        score += 3.0

    if promo.get("promo_code"):
        score += 2.0

    if _extract_dollars(dvalue) or _extract_percent(dvalue):
        score += 2.0

    return min(score, 8.0)


def required_spend_penalty(savings: float, min_spend: float | None) -> float:
    """
    Penalty for low-efficiency minimum-spend requirements.
    threshold_efficiency = savings / required_spend.
    A $20 saving on a $25 spend (80% efficiency) gets minimal penalty.
    A $5 saving on a $100 spend (5% efficiency) gets near-maximum penalty.
    """
    """
    Squared penalty curve — softens penalties for reasonably efficient thresholds
    while still punishing poor ones.

    Examples (savings / min_spend → penalty):
        $20 / $25  (80% eff) → 0.48
        $20 / $50  (40% eff) → 4.32
        $5  / $100 ( 5% eff) → 10.83
    """
    if min_spend is None or min_spend <= 0:
        return 0.0
    efficiency = min(savings / min_spend, 1.0)
    return round((1.0 - efficiency) ** 2 * 12.0, 2)


def quantity_burden_penalty(promo: dict) -> float:
    """
    Penalty for offers that require purchasing more units than a typical user needs.
    BOGO at a coffee shop: low burden (repeat purchase).
    Buy 2 pairs of shoes: moderate. Buy 2 laptops: near-maximum.
    """
    title    = promo.get("promotion_title") or ""
    category = promo.get("category") or ""
    weight   = _quantity_burden_weight(category)

    if _BOGO_RE.search(title):
        return round(10.0 * weight, 2)

    bxy = _BUY_X_GET_Y.search(title)
    if bxy:
        buy_n = int(bxy.group(1))
        # More items required → higher burden scalar (buy 1 = 0.5×, buy 2+ = 1.0×)
        burden_scale = min(buy_n / 2.0, 1.0)
        return round(10.0 * weight * burden_scale, 2)

    return 0.0


def clarity_score(promo: dict) -> float:
    """
    How precisely can a consumer understand what they save and what qualifies,
    before reading fine print?

    0 = highly vague ("Save on select styles")
    5 = perfectly precise ("$15 off orders over $30", "Free latte with any purchase")

    Kept at ≤5 points — clarity is a positive signal, not a substitute for value.
    Assessed independently of LLM confidence (clarity is a property of the offer text,
    not of extraction accuracy).
    """
    dtype  = promo.get("discount_type") or ""
    dvalue = promo.get("discount_value") or ""
    title  = promo.get("promotion_title") or ""

    if _BOGO_RE.search(title) or _BUY_X_GET_Y.search(title):
        return 5.0  # universally understood multi-buy format

    if dtype == "free_shipping":
        return 4.0  # mechanism is clear; dollar value varies by order size

    if dtype == "free_item" and not _TRIAL_RE.search(title):
        # Clearest when the specific item is named ("Free Latte"), less so when vague
        return 4.0 if _infer_item_value_from_title(title) else 2.0

    has_exact_amount = bool(_extract_percent(dvalue) or _extract_dollars(dvalue))
    is_vague         = bool(_VAGUE_RE.search(title))

    if not is_vague and has_exact_amount:
        return 5.0  # exact discount + clear eligibility

    if is_vague and has_exact_amount:
        return 1.0  # know the depth, but eligibility is unclear ("30% off select items")

    if not is_vague and not has_exact_amount:
        return 2.0  # deal type is clear but amount is unstated

    return 0.0  # highly vague, no stated amount


def reliability_multiplier(promo: dict) -> float:
    """
    Confidence acts as a reliability multiplier on economic value — not an
    additive bonus. Low confidence means Candy is uncertain the extraction
    is correct; high confidence means the deal is as described.

    Confidence < 0.60 flags the deal as low-confidence (sets a separate field).
    """
    c = promo.get("confidence_score") or 0.0
    if c <= 0:    return 0.75   # unknown — conservative
    if c < 0.60:  return 0.65   # flagged low confidence
    if c < 0.70:  return 0.80
    if c < 0.75:  return 0.87
    if c < 0.80:  return 0.92
    if c < 0.90:  return 0.96
    return 1.00


def fast_redeem_score(promo: dict) -> float:
    fr = promo.get("fast_redemption") or {}
    if not fr.get("eligible"):
        return 0.0
    return {
        "copy_code_and_open_url": 12.0,
        "copy_code":              10.0,
        "open_app":                8.0,
        "open_rewards":            8.0,
        "show_barcode_or_code":    7.0,
        "open_url":                6.0,
        "open_maps":               6.0,
        "show_steps":              2.0,
    }.get(fr.get("action_type", ""), 0.0)


def source_freshness_score(promo: dict) -> float:
    """
    Measures how recently the deal was scraped — not how urgently it expires.
    A deal scraped two weeks ago and expiring today is urgent but stale.
    A deal scraped yesterday valid for a month is fresh but not urgent.
    """
    scraped_raw = promo.get("scraped_at") or promo.get("checked_at") or ""
    if not scraped_raw:
        return 0.0
    try:
        scraped_dt = datetime.fromisoformat(scraped_raw.replace("Z", "+00:00"))
        days_old = (datetime.now(timezone.utc) - scraped_dt).days
        if days_old == 0:   return  8.0
        if days_old <= 1:   return  6.0
        if days_old <= 3:   return  4.0
        if days_old <= 7:   return  1.0
        if days_old <= 14:  return -3.0
        return -8.0
    except ValueError:
        return 0.0


def expiration_urgency_score(promo: dict) -> float:
    """
    Raw urgency from expiration proximity. Capped at 5 — urgency alone should
    not convert a weak deal into a strong one (see urgency_effect below).
    Expired deals return 0 (handled by pipeline status filtering).
    """
    today = date.today()
    end   = (promo.get("end_date") or "").strip()
    if not end:
        return 0.0
    try:
        end_date = date.fromisoformat(end[:10])
        delta    = (end_date - today).days
        if delta < 0:   return 0.0   # expired
        if delta == 0:  return 5.0
        if delta == 1:  return 4.0
        if delta <= 3:  return 2.0
        return 0.0
    except ValueError:
        return 0.0


def urgency_effect(urgency: float, economic_score: float) -> float:
    """
    Urgency amplifies deals that are already worthwhile; it cannot rescue
    genuinely weak deals. A bad deal expiring today remains bad.
    At economic_score ≥ 35 the multiplier is 1.0 (full urgency applies).
    """
    normalized_value = min(economic_score / 35.0, 1.0)
    return round(urgency * normalized_value, 2)


def friction_penalty(promo: dict) -> float:
    """
    Friction penalty for barriers to redemption that reduce expected realized value.
    Minimum-spend threshold efficiency is handled separately in required_spend_penalty.
    """
    penalty = 0.0

    if promo.get("requires_membership"):
        cost = (promo.get("membership_cost") or "").lower()
        if "paid" in cost:    penalty += 15.0
        elif "free" in cost:  penalty +=  2.0
        else:                 penalty +=  8.0

    if promo.get("requires_app"):
        penalty += 5.0

    terms = (promo.get("terms_text") or "").lower()
    if "participating" in terms:
        penalty += 4.0

    fr     = promo.get("fast_redemption") or {}
    effort = (fr.get("effort_level") or "unknown").lower()
    if effort == "high":     penalty += 6.0
    elif effort == "medium": penalty += 3.0
    # "unknown" effort is no longer penalized — absence of data ≠ high friction

    return penalty


def _value_explanation_codes(
    promo: dict,
    eff_pct: float,
    econ_score: float,
    savings: float,
    urgency: float,
    spend_pen: float,
    qty_pen: float,
    fr_score: float,
    low_conf: bool,
) -> list[str]:
    """
    Machine-readable tags the Flutter app maps to human-readable deal copy,
    without calling an LLM at runtime. Extend this list freely — the app only
    renders codes it recognises; unknown codes are silently ignored.

    Usage in Flutter:
        final codes = promo.valueExplanationCodes;
        if (codes.contains('HIGH_EFFECTIVE_DISCOUNT')) { ... }
    """
    codes: list[str] = []

    # Discount depth
    if eff_pct >= 50:   codes.append("HIGH_EFFECTIVE_DISCOUNT")
    elif eff_pct >= 30: codes.append("STRONG_DISCOUNT")
    elif eff_pct >= 15: codes.append("MODERATE_DISCOUNT")

    # Dollar value of savings
    if savings >= 50:   codes.append("HIGH_VALUE_SAVINGS")
    elif savings >= 20: codes.append("GOOD_VALUE_SAVINGS")

    # Expiry urgency
    if urgency >= 4:   codes.append("EXPIRES_TODAY")
    elif urgency >= 2: codes.append("EXPIRES_SOON")

    # Redemption accessibility
    if not promo.get("requires_membership") and not promo.get("requires_app"):
        codes.append("NO_MEMBERSHIP_REQUIRED")
    elif promo.get("requires_membership"):
        cost = (promo.get("membership_cost") or "").lower()
        if "paid" in cost:   codes.append("PAID_MEMBERSHIP_REQUIRED")
        elif "free" in cost: codes.append("FREE_MEMBERSHIP_REQUIRED")
        else:                codes.append("MEMBERSHIP_REQUIRED")
    if fr_score >= 10: codes.append("LOW_REDEMPTION_FRICTION")

    # Purchase requirements
    if spend_pen <= 0.5 and qty_pen <= 0.5:
        codes.append("NO_PURCHASE_MINIMUM")
    elif spend_pen >= 8:
        codes.append("HIGH_SPEND_REQUIRED")

    # Overall quality signals
    if econ_score >= 40: codes.append("STRONG_ECONOMIC_VALUE")
    if low_conf:         codes.append("LOW_CONFIDENCE_WARNING")

    return codes


# ---------------------------------------------------------------------------
# Main scorer
# ---------------------------------------------------------------------------

def compute_global_quality_score(promo: dict) -> dict:
    """
    Computes and annotates global_quality_score and all sub-scores. Exported fields:
        economic_value_score, effective_discount_pct, clarity_score,
        expiration_urgency_score, source_freshness_score,
        low_confidence_flagged, estimated_item_value, estimated_savings,
        value_explanation_codes, value_reason, global_quality_score.
    """
    item_val, savings, reason_snippet = _compute_estimated_savings(promo)
    category = promo.get("category") or ""

    # Economic value — relative discount + absolute savings, minus penalties
    eff_pct   = _compute_effective_discount_pct(promo, savings, item_val)
    rel_score = relative_discount_score(eff_pct)
    abs_score = absolute_savings_score(savings, category)

    # Required-spend penalty: BOGO/multi-buy deals carry an intrinsic spend
    # requirement that is separate from (and takes priority over) any explicit
    # minimum_spend field. The two denominators serve different purposes:
    #   intrinsic spend → threshold efficiency (savings / required payment)
    #   quantity_burden → unit-count burden (how many do you need to buy?)
    bogo_spend     = _bogo_intrinsic_spend(promo, item_val)
    explicit_spend = _parse_minimum_spend(promo)
    effective_spend = bogo_spend if bogo_spend is not None else explicit_spend

    spend_pen  = required_spend_penalty(savings, effective_spend)
    qty_pen    = quantity_burden_penalty(promo)

    econ_score = max(rel_score + abs_score - spend_pen - qty_pen, 0.0)

    # Presentation bonus (capped at 8 — framing cannot substitute for value)
    pres_score = presentation_strength_score(promo)

    # Reliability multiplier: confidence discounts extraction-dependent estimates.
    # Applied to economic value + presentation only — clarity and fast_redeem are
    # assessed from deal structure and text, independently of extraction accuracy.
    rel_mult   = reliability_multiplier(promo)
    low_conf   = (promo.get("confidence_score") or 0.0) < 0.60
    raw_value  = (econ_score + pres_score) * rel_mult

    # Clarity: assessed independently of confidence multiplier
    clr_score  = clarity_score(promo)

    fr_score   = fast_redeem_score(promo)
    fresh      = source_freshness_score(promo)
    urgency    = expiration_urgency_score(promo)
    urg_eff    = urgency_effect(urgency, econ_score)
    friction   = friction_penalty(promo)

    gqs = round(raw_value + clr_score + fr_score + fresh + urg_eff - friction, 2)

    codes = _value_explanation_codes(
        promo, eff_pct, econ_score, savings, urgency,
        spend_pen, qty_pen, fr_score, low_conf,
    )

    promo["estimated_item_value"]     = round(item_val, 2)
    promo["estimated_savings"]        = round(savings, 2)
    promo["effective_discount_pct"]   = round(eff_pct, 1)
    promo["clarity_score"]            = clr_score
    promo["value_reason"]             = (
        f"{reason_snippet} | "
        f"rel={rel_score:.1f} abs={abs_score:.1f} spend_pen={spend_pen:.1f} "
        f"qty_pen={qty_pen:.1f} pres={pres_score:.1f} clr={clr_score:.1f} "
        f"mult={rel_mult:.2f} fr={fr_score:.1f} fresh={fresh:.1f} "
        f"urg={urg_eff:.1f} fric={friction:.1f}"
    )
    promo["economic_value_score"]     = round(econ_score, 2)
    promo["expiration_urgency_score"] = round(urgency, 2)
    promo["source_freshness_score"]   = round(fresh, 2)
    promo["low_confidence_flagged"]   = low_conf
    promo["value_explanation_codes"]  = codes
    promo["global_quality_score"]     = gqs
    return promo


def main() -> None:
    data   = json.loads(ALL_PROMOS.read_text(encoding="utf-8"))
    promos = data.get("promotions", []) if isinstance(data, dict) else data

    scores: list[float] = []
    for p in promos:
        compute_global_quality_score(p)
        scores.append(p["global_quality_score"])

    if isinstance(data, dict):
        data["promotions"] = promos
    ALL_PROMOS.write_text(
        json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    if scores:
        print(f"global_quality_score computed for {len(scores)} promotions")
        print(f"  min={min(scores):.1f}  max={max(scores):.1f}  "
              f"avg={sum(scores)/len(scores):.1f}")
    print(f"Wrote -> {ALL_PROMOS}")


if __name__ == "__main__":
    main()
