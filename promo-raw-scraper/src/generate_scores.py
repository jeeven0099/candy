"""
generate_scores.py — compute global_quality_score for every promotion.

Runs after generate_fast_redemption.py (needs fast_redemption data).

global_quality_score = value_score
                     + fast_redeem_score
                     + confidence_score_pts
                     + freshness_score
                     - friction_penalty

NO user preferences, NO email affinity — those are pure per-user signals
and must be applied at runtime in Flutter (feed_ranker.dart / search_utils.dart).
Distance and membership bonuses are also added at runtime because they require
live geolocation and user membership data.
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
# Sub-scores
# ---------------------------------------------------------------------------

_BOGO_RE      = re.compile(r'\bbogo\b|buy.one.get.one', re.IGNORECASE)
_TRIAL_RE     = re.compile(r'\bfree\s+trial\b|\btrial\b|\d+\s+(?:months?|weeks?|days?)\s+free', re.IGNORECASE)
_SITEWIDE_RE  = re.compile(r'\bsitewide\b', re.IGNORECASE)


def value_score(promo: dict) -> float:
    dtype  = (promo.get("discount_type") or "").strip()
    dvalue = promo.get("discount_value")
    title  = (promo.get("promotion_title") or "")
    ptype  = (promo.get("promotion_type") or "").strip()

    # ── Birthday reward ───────────────────────────────────────────────────────
    if ptype == "birthday_reward" or promo.get("birthday_related"):
        return 45.0

    # ── BOGO (keyword in title, regardless of encoded discount_type) ──────────
    if _BOGO_RE.search(title):
        return 50.0

    # ── Free item (but not a trial) ───────────────────────────────────────────
    if dtype == "free_item":
        if _TRIAL_RE.search(title):
            return 18.0   # free trial — valuable but requires sign-up
        return 65.0

    # ── Percentage off ────────────────────────────────────────────────────────
    if dtype == "percentage_off":
        pct = _extract_percent(dvalue)
        if pct is None:
            # Sitewide with no parseable % — still meaningful
            return 15.0 if _SITEWIDE_RE.search(title) else 14.0
        if pct >= 50:    return 45.0
        if pct >= 30:    return 35.0
        if pct >= 20:    return 26.0
        if pct >= 10:    return 18.0
        return 10.0

    # ── Dollar amount off ─────────────────────────────────────────────────────
    if dtype == "amount_off":
        amt = _extract_dollars(dvalue)
        if amt is None:  return 18.0
        if amt >= 50:    return 42.0
        if amt >= 10:    return round(24.0 + (amt - 10.0) * (36.0 - 24.0) / (49.0 - 10.0), 1)
        return round(max(10.0, 16.0 + amt * 0.4), 1)   # < $10

    if dtype == "sale_price":
        return 16.0

    if dtype == "free_shipping":
        return 10.0

    if dtype == "points":
        return 5.0

    return 10.0


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
            if delta < 0:     return -15.0  # expired
            if delta == 0:    return 18.0   # expires today — urgent
            if delta == 1:    return 14.0   # expires tomorrow
            if delta <= 3:    return 8.0    # expires in 2-3 days
            return 4.0                      # known future end_date
        except ValueError:
            pass

    # No end_date — fall back to scrape age
    scraped_raw = promo.get("scraped_at") or promo.get("checked_at") or ""
    if scraped_raw:
        try:
            scraped_dt = datetime.fromisoformat(scraped_raw.replace("Z", "+00:00"))
            days_old = (datetime.now(timezone.utc) - scraped_dt).days
            if days_old == 0:   return 5.0
            if days_old <= 7:   return 2.0
            if days_old <= 14:  return -5.0
            return -15.0
        except ValueError:
            pass

    return 0.0  # age unknown — neutral


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

def compute_global_quality_score(promo: dict) -> float:
    return round(
        value_score(promo)
        + fast_redeem_score(promo)
        + confidence_score_pts(promo)
        + freshness_score(promo)
        - friction_penalty(promo),
        2,
    )


def main() -> None:
    data   = json.loads(ALL_PROMOS.read_text(encoding="utf-8"))
    promos = data.get("promotions", []) if isinstance(data, dict) else data

    scores: list[float] = []
    for p in promos:
        s = compute_global_quality_score(p)
        p["global_quality_score"] = s
        scores.append(s)

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
