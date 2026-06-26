"""
generate_scores.py — compute global_quality_score for every promotion.

Runs after generate_fast_redemption.py (needs fast_redemption data).

global_quality_score = value_score
                     + fast_redeem_score
                     + confidence_score_pts
                     + freshness_score
                     - friction_penalty

value_score = deal_type_score + estimated_savings_score

deal_type_score  — psychological appeal (free > BOGO > % off > $ off)
estimated_savings_score — real economic value:
    free fries ≈ $3.5  → savings_score  3
    free drink ≈ $6    → savings_score  8
    50% off Nike ≈ $52 → savings_score 35
    $100 off laptop    → savings_score 45

This prevents "free fries" from always beating "50% off Nike shoes."
For a food-focused user, food deals still rank high via runtime personalization
(feed_ranker.dart) — but globally/objectively, dollar value is reflected.

Adds estimated_item_value, estimated_savings, value_reason to each promo.
"""
from __future__ import annotations

import json
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

# Median typical purchase value per category
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

# Brand-specific overrides where category alone is insufficient.
# Keys are canonical brand names; lookup is done via slugify for robustness.
_BRAND_ITEM_VALUE_RAW: dict[str, float] = {
    # Fast food — small items
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
    # Coffee / bakery
    "starbucks": 6.5, "dunkin": 5.0, "dutch bros": 5.5,
    "peets coffee": 6.0, "caribou coffee": 6.0,
    "einstein bros bagels": 6.0, "krispy kreme": 4.0,
    "jamba": 7.0, "smoothie king": 7.0, "tropical smoothie cafe": 7.0,
    # Grocery / wholesale
    "whole foods market": 8.0, "trader joes": 6.0,
    "costco": 80.0, "sams club": 60.0, "bjs wholesale club": 60.0,
    # Beauty — mid-range
    "sephora": 35.0, "ulta beauty": 28.0,
    "mac cosmetics": 32.0, "charlotte tilbury": 48.0,
    "fenty beauty": 36.0, "nars": 42.0, "tarte cosmetics": 32.0,
    "too faced": 28.0, "urban decay": 30.0, "benefit cosmetics": 28.0,
    "elf cosmetics": 12.0, "colourpop": 14.0, "nyx": 12.0,
    "il makiage": 42.0, "the ordinary": 12.0,
    "kiehls": 35.0,
    # Fashion — budget to mid
    "gap": 40.0, "old navy": 35.0, "banana republic": 75.0,
    "jcrew": 65.0, "ann taylor": 80.0, "loft": 55.0,
    "abercrombie fitch": 70.0, "hollister": 45.0,
    "american eagle": 50.0, "aerie": 35.0,
    "zara": 55.0, "hm": 35.0, "uniqlo": 40.0,
    "madewell": 80.0, "free people": 90.0, "anthropologie": 90.0,
    # Fashion — luxury
    "coach": 380.0, "kate spade": 280.0, "michael kors": 220.0,
    "tory burch": 260.0, "vera bradley": 60.0,
    # Activewear
    "lululemon": 85.0, "fabletics": 65.0, "gymshark": 55.0,
    "alo yoga": 90.0, "vuori": 80.0,
    # Outdoor
    "patagonia": 120.0, "the north face": 120.0,
    "columbia": 90.0, "eddie bauer": 90.0, "llbean": 80.0,
    # Shoes — high value
    "nike": 105.0, "adidas": 95.0, "new balance": 115.0,
    "hoka": 145.0, "asics": 125.0, "brooks running": 135.0,
    "saucony": 125.0, "allbirds": 120.0,
    "ugg": 160.0, "timberland": 135.0,
    "dr martens": 150.0, "crocs": 55.0, "hey dude": 55.0,
    "sperry": 85.0, "clarks": 90.0, "aldo": 80.0, "steve madden": 90.0,
    "cole haan": 150.0, "converse": 70.0, "vans": 70.0,
    "foot locker": 100.0, "finish line": 100.0, "dsw": 80.0,
    "skechers": 75.0,
    # Tech — high value
    "best buy": 280.0, "dell": 800.0,
    "newegg": 250.0, "micro center": 300.0,
    "bh photo": 400.0, "adorama": 400.0,
    # Entertainment
    "amc theatres": 14.0, "cinemark": 13.0, "regal": 13.0, "fandango": 15.0,
    # Travel
    "marriott": 190.0, "hilton": 175.0, "wyndham hotels": 120.0,
    "delta air lines": 320.0, "southwest airlines": 250.0,
    "jetblue": 210.0, "spirit airlines": 120.0, "frontier airlines": 100.0,
    "enterprise": 60.0, "avis": 65.0,
}

# Pre-slugify brand keys for fast lookup
_BRAND_VALUE_LOOKUP: dict[str, float] = {
    _slugify(k): v for k, v in _BRAND_ITEM_VALUE_RAW.items()
}

# Conservative item value for vague deals ("select styles", "sitewide").
# Represents the lower end of what the brand actually sells — e.g. a wallet
# at Coach rather than a full bag, a t-shirt at Nike rather than shoes.
_BRAND_CONSERVATIVE_RAW: dict[str, float] = {
    # Luxury fashion — accessories/entry items, not hero items
    "coach": 75.0, "kate spade": 60.0, "michael kors": 55.0,
    "tory burch": 65.0, "vera bradley": 30.0,
    # Activewear — could be shorts or top, not full leggings set
    "lululemon": 45.0, "fabletics": 35.0, "gymshark": 35.0,
    "alo yoga": 50.0, "vuori": 40.0,
    # Outdoor/sportswear — could be accessory, not full jacket
    "the north face": 65.0, "patagonia": 70.0,
    "columbia": 50.0, "eddie bauer": 50.0, "llbean": 45.0,
    # Shoes — could be socks or sandals, not flagship shoes
    "nike": 50.0, "adidas": 45.0, "new balance": 60.0,
    "hoka": 80.0, "asics": 65.0, "brooks running": 70.0,
    "saucony": 65.0, "ugg": 80.0, "timberland": 70.0,
    "dr martens": 80.0, "allbirds": 60.0, "cole haan": 75.0,
    # Mid fashion — basics/accessories
    "banana republic": 40.0, "jcrew": 38.0, "ann taylor": 42.0,
    "madewell": 45.0, "free people": 50.0, "anthropologie": 50.0,
    "abercrombie fitch": 38.0, "gap": 28.0, "old navy": 22.0,
    # Beauty — could be lip gloss, not full foundation kit
    "sephora": 18.0, "ulta beauty": 15.0,
    "mac cosmetics": 18.0, "charlotte tilbury": 28.0,
    "fenty beauty": 20.0, "nars": 22.0,
    # Tech — could be cable or case, not full device
    "best buy": 50.0, "dell": 150.0,
    "newegg": 60.0, "micro center": 80.0,
    # Travel — conservative room/fare estimate
    "marriott": 100.0, "hilton": 90.0, "wyndham hotels": 70.0,
    "delta air lines": 140.0, "southwest airlines": 110.0, "jetblue": 100.0,
}

_BRAND_CONSERVATIVE_LOOKUP: dict[str, float] = {
    _slugify(k): v for k, v in _BRAND_CONSERVATIVE_RAW.items()
}

# Category conservative fallbacks
_CATEGORY_CONSERVATIVE_VALUE: dict[str, float] = {
    "fashion": 28.0, "clothing": 25.0, "apparel": 25.0, "retail": 20.0,
    "shoes": 50.0, "footwear": 50.0,
    "beauty": 14.0, "personal_care": 12.0,
    "tech": 60.0, "electronics": 60.0,
    "home": 35.0, "home_goods": 30.0, "furniture": 80.0,
    "travel": 80.0, "hotels": 80.0, "airlines": 100.0,
}

# Title keywords for inferring the value of a specific item type.
# Used for free-item value and for anchoring percent-off estimates when the
# title names a concrete item ("20% off sneakers" vs "20% off select styles").
_ITEM_TYPE_HINTS: list[tuple[re.Pattern, float]] = [
    # Food — small items (patterns handle common plurals)
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
    # Beauty
    (re.compile(r"\blipsticks?\b|\blip\s+colors?\b|\blip\s+gloss\b", re.I),           18.0),
    (re.compile(r"\bmascaras?\b|\beyeliners?\b|\bconcealers?\b|\beyeshadows?\b", re.I),16.0),
    (re.compile(r"\bfoundations?\b", re.I),                                            28.0),
    (re.compile(r"\bserums?\b|\bmoisturizers?\b|\bface\s+cream\b", re.I),              25.0),
    # Apparel — sorted from most specific to most general to avoid mis-matching
    (re.compile(r"\bhoodies?\b|\bsweaters?\b|\bsweatshirts?\b", re.I),                55.0),
    (re.compile(r"\bjackets?\b|\bcoats?\b|\bvests?\b|\bparkas?\b", re.I),             75.0),
    (re.compile(r"\bjeans?\b|\bdenim\b|\bpants?\b|\btrousers?\b|\bleggings?\b", re.I),55.0),
    (re.compile(r"\bdresses?\b|\bblouses?\b|\bskirts?\b|\bgowns?\b", re.I),           60.0),
    (re.compile(r"\bshirts?\b|\btees?\b|\btops?\b|\btanks?\b", re.I),                 30.0),
    # Footwear
    (re.compile(r"\bsneakers?\b|\bshoes?\b|\bboots?\b|\bsandals?\b|\bheels?\b", re.I),90.0),
    # Accessories / bags
    (re.compile(r"\bhandbags?\b|\bpurses?\b|\btotes?\b", re.I),                      120.0),
    (re.compile(r"\bwallets?\b|\bcard\s+holders?\b|\bwristlets?\b", re.I),             55.0),
    (re.compile(r"\bbags?\b", re.I),                                                  100.0),
]

_BOGO_RE     = re.compile(r'\bbogo\b|buy.one.get.one', re.IGNORECASE)
_TRIAL_RE    = re.compile(r'\bfree\s+trial\b|\btrial\b|\d+\s+(?:months?|weeks?|days?)\s+free', re.IGNORECASE)
_SITEWIDE_RE = re.compile(r'\bsitewide\b', re.IGNORECASE)

# Vague deal language — signals that the offer applies broadly and the stated
# brand item price is likely too high (e.g. "select styles" at Coach could mean
# a wallet, not a full bag). Triggers conservative savings estimation.
_VAGUE_RE = re.compile(
    r'\bselect\s+(?:styles?|items?|products?)\b'
    r'|\bsitewide\b'
    r'|\byour\s+(?:order|purchase)\b'
    r'|\beverything\b'
    r'|\ball\s+(?:items?|styles?|orders?|purchases?)\b'
    r'|\bfull[\s-]price\b'
    r'|\bregular[\s-]price\b',
    re.IGNORECASE
)


# ---------------------------------------------------------------------------
# Estimation helpers
# ---------------------------------------------------------------------------

def _estimate_item_value(promo: dict) -> float:
    """Typical price of one item/purchase for this brand/category."""
    brand_slug = _slugify(promo.get("brand") or "")

    # Exact slug match
    if brand_slug in _BRAND_VALUE_LOOKUP:
        return _BRAND_VALUE_LOOKUP[brand_slug]

    # Prefix match (handles slight name variations)
    if len(brand_slug) >= 5:
        for slug, val in _BRAND_VALUE_LOOKUP.items():
            if len(slug) >= 5 and brand_slug[:7] == slug[:7]:
                return val

    # Category fallback
    cat = (promo.get("category") or "").lower().strip()
    return _CATEGORY_ITEM_VALUE.get(cat, 30.0)


def _infer_item_value_from_title(title: str) -> float | None:
    """Scans the title for a specific item type and returns its estimated price.
    Returns None if no recognized item type is found."""
    for pattern, val in _ITEM_TYPE_HINTS:
        if pattern.search(title):
            return val
    return None


def _estimate_free_item_value(promo: dict) -> float:
    """Estimate the value of the free item being offered, using title keywords."""
    title = promo.get("promotion_title") or ""
    title_val = _infer_item_value_from_title(title)
    if title_val is not None:
        return title_val
    # Unknown free item: use brand/category price, capped at $15
    return min(_estimate_item_value(promo), 15.0)


def _conservative_item_value(promo: dict) -> float:
    """Conservative item price for vague deals (select styles, sitewide, etc.)."""
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

    # Final fallback: 50% of full estimate (unknown brand/category)
    return _estimate_item_value(promo) * 0.5


def _compute_estimated_savings(promo: dict) -> tuple[float, float, str]:
    """
    Returns (item_value, estimated_savings_dollars, reason_snippet).
    """
    dtype  = (promo.get("discount_type") or "").strip()
    dvalue = promo.get("discount_value") or ""
    title  = promo.get("promotion_title") or ""
    ptype  = (promo.get("promotion_type") or "").strip()

    item_val = _estimate_item_value(promo)

    # Birthday reward — treat as a moderate free item
    if ptype == "birthday_reward" or promo.get("birthday_related"):
        free_val = _estimate_free_item_value(promo)
        return item_val, free_val, f"birthday reward, est. free item ≈ ${free_val:.0f}"

    # BOGO: buy one get one free = 50% of order value saved
    if _BOGO_RE.search(title):
        savings = round(item_val * 0.5, 2)
        return item_val, savings, f"BOGO, est. 50% of ${item_val:.0f} order ≈ ${savings:.0f} savings"

    # Free item (not a trial)
    if dtype == "free_item":
        if _TRIAL_RE.search(title):
            return item_val, 5.0, "free trial, nominal value ≈ $5"
        free_val = _estimate_free_item_value(promo)
        return item_val, free_val, f"free item, est. ≈ ${free_val:.0f} savings"

    # Percentage off — confidence tier determines which item price to use:
    #   Tier 1 (stated dollar off)     → already handled above as amount_off
    #   Tier 2 (% off + specific item) → use title-inferred item price
    #   Tier 3 (% off + brand/cat)     → use full brand/category estimate
    #   Tier 4 (% off + vague)         → conservative estimate
    if dtype == "percentage_off":
        pct = _extract_percent(dvalue)
        is_vague    = bool(_VAGUE_RE.search(title))
        title_val   = _infer_item_value_from_title(title)

        if pct:
            if title_val is not None:
                # Tier 2: specific item type named in title
                item_val_used = title_val
                tier = f"specific item in title (${title_val:.0f})"
            elif is_vague:
                # Tier 4: vague language — use conservative estimate
                item_val_used = _conservative_item_value(promo)
                tier = f"vague deal, conservative est. (${item_val_used:.0f})"
            else:
                # Tier 3: brand/category known, item not specified
                item_val_used = item_val
                tier = f"brand/cat est. (${item_val_used:.0f})"
            savings = round(item_val_used * pct / 100.0, 2)
            return item_val, savings, f"{pct:.0f}% off, {tier} ≈ ${savings:.0f} savings"

        # No parseable percentage — sitewide or unknown
        if is_vague or _SITEWIDE_RE.search(title):
            conservative = _conservative_item_value(promo)
            savings = round(conservative * 0.20, 2)
            return item_val, savings, f"vague/sitewide % off, conservative est. ${conservative:.0f} ≈ ${savings:.0f} savings"
        return item_val, round(item_val * 0.15, 2), "% off (unparseable), est. 15% of brand/cat value"

    # Dollar amount off — use stated amount directly
    if dtype == "amount_off":
        amt = _extract_dollars(dvalue)
        if amt:
            return item_val, amt, f"${amt:.0f} off"
        return item_val, 8.0, "$ off (no amount parsed), est. $8"

    # Sale price — hard to know original; assume ~20% savings.
    # Use conservative estimate when language is vague.
    if dtype == "sale_price":
        base = _conservative_item_value(promo) if _VAGUE_RE.search(title) else item_val
        savings = round(base * 0.20, 2)
        return item_val, savings, f"sale price, est. 20% off ${base:.0f} ≈ ${savings:.0f} savings"

    # Free shipping
    if dtype == "free_shipping":
        return item_val, 5.0, "free shipping ≈ $5 savings"

    # Points / rewards — minimal direct value
    if dtype == "points":
        return item_val, 2.0, "points/rewards, nominal value ≈ $2"

    return item_val, 5.0, "unknown deal type, est. $5 savings"


# ---------------------------------------------------------------------------
# Sub-scores
# ---------------------------------------------------------------------------

def _deal_type_score(promo: dict) -> float:
    """Psychological appeal score — independent of dollar value."""
    dtype  = (promo.get("discount_type") or "").strip()
    dvalue = promo.get("discount_value") or ""
    title  = promo.get("promotion_title") or ""
    ptype  = (promo.get("promotion_type") or "").strip()

    if ptype == "birthday_reward" or promo.get("birthday_related"):
        return 18.0

    if _BOGO_RE.search(title):
        return 18.0

    if dtype == "free_item":
        return 8.0 if _TRIAL_RE.search(title) else 20.0

    if dtype == "percentage_off":
        pct = _extract_percent(dvalue)
        if pct is None:
            return 8.0 if _SITEWIDE_RE.search(title) else 6.0
        if pct >= 50: return 16.0
        if pct >= 30: return 12.0
        if pct >= 20: return  8.0
        if pct >= 10: return  5.0
        return 3.0

    if dtype == "amount_off":
        amt = _extract_dollars(dvalue)
        if amt is None: return 8.0
        if amt >= 100:  return 15.0
        if amt >= 50:   return 13.0
        if amt >= 10:   return 10.0
        return 8.0

    if dtype == "sale_price":    return 6.0
    if dtype == "free_shipping": return 5.0
    if dtype == "points":        return 3.0

    return 5.0


def _savings_score(estimated_savings: float) -> float:
    """Convert estimated dollar savings into a score bucket."""
    if estimated_savings >= 100: return 45.0
    if estimated_savings >= 51:  return 35.0
    if estimated_savings >= 26:  return 25.0
    if estimated_savings >= 11:  return 15.0
    if estimated_savings >= 6:   return  8.0
    if estimated_savings >= 1:   return  3.0
    return 0.0


def value_score(promo: dict) -> tuple[float, float, float, str]:
    """
    Returns (value_score, estimated_item_value, estimated_savings, value_reason).
    value_score = deal_type_score + estimated_savings_score
    """
    item_val, savings, reason_snippet = _compute_estimated_savings(promo)
    dt_score = _deal_type_score(promo)
    sv_score = _savings_score(savings)
    total    = dt_score + sv_score
    reason   = f"{reason_snippet} | type={dt_score:.0f} + savings={sv_score:.0f} = {total:.0f}"
    return total, round(item_val, 2), round(savings, 2), reason


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


def confidence_score_pts(promo: dict) -> float:
    c = promo.get("confidence_score") or 0.0
    if c >= 0.90: return 18.0
    if c >= 0.80: return 16.0
    if c >= 0.75: return 15.0
    if c >= 0.65: return 13.0
    return 0.0


def freshness_score(promo: dict) -> float:
    today = date.today()

    end = (promo.get("end_date") or "").strip()
    if end:
        try:
            end_date = date.fromisoformat(end[:10])
            delta = (end_date - today).days
            if delta < 0:     return -15.0
            if delta == 0:    return  18.0
            if delta == 1:    return  14.0
            if delta <= 3:    return   8.0
            return 4.0
        except ValueError:
            pass

    scraped_raw = promo.get("scraped_at") or promo.get("checked_at") or ""
    if scraped_raw:
        try:
            scraped_dt = datetime.fromisoformat(scraped_raw.replace("Z", "+00:00"))
            days_old = (datetime.now(timezone.utc) - scraped_dt).days
            if days_old == 0:   return  5.0
            if days_old <= 7:   return  2.0
            if days_old <= 14:  return -5.0
            return -15.0
        except ValueError:
            pass

    return 0.0


def friction_penalty(promo: dict) -> float:
    penalty = 0.0

    if promo.get("requires_membership"):
        cost = (promo.get("membership_cost") or "").lower()
        if "paid" in cost:    penalty += 15.0
        elif "free" in cost:  penalty +=  2.0
        else:                 penalty +=  8.0

    if promo.get("requires_app"):
        penalty += 5.0

    if promo.get("minimum_spend"):
        penalty += 4.0

    terms = (promo.get("terms_text") or "").lower()
    if "participating" in terms:
        penalty += 4.0

    fr     = promo.get("fast_redemption") or {}
    effort = (fr.get("effort_level") or "unknown").lower()
    if effort == "high":       penalty += 8.0
    elif effort == "medium":   penalty += 4.0
    elif effort == "unknown":  penalty += 5.0

    return penalty


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def compute_global_quality_score(promo: dict) -> dict:
    """
    Returns a dict of score components. Sets estimated_item_value,
    estimated_savings, value_reason, and global_quality_score on the promo.
    """
    vs, item_val, savings, reason = value_score(promo)
    fr_score  = fast_redeem_score(promo)
    conf_pts  = confidence_score_pts(promo)
    fresh     = freshness_score(promo)
    friction  = friction_penalty(promo)

    gqs = round(vs + fr_score + conf_pts + fresh - friction, 2)

    promo["estimated_item_value"] = item_val
    promo["estimated_savings"]    = savings
    promo["value_reason"]         = reason
    promo["global_quality_score"] = gqs
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
