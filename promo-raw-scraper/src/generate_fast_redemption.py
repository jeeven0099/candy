"""
generate_fast_redemption.py — add fast_redemption objects to all_promotions.json.

Rule-based (no LLM) — runs in seconds over all promotions.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALL_PROMOS = ROOT / "all_promotions.json"

# Known app deep-link schemes for popular brands
_APP_DEEP_LINKS: dict[str, str] = {
    "starbucks":    "starbucks://",
    "mcdonald":     "mcdonalds://",
    "chipotle":     "chipotle://",
    "wendy":        "wendys://",
    "doordash":     "doordash://",
    "uber eats":    "ubereats://",
    "walmart":      "walmart://",
    "target":       "target://",
    "dunkin":       "dunkin://",
    "dutch bros":   "dutchbros://",
    "domino":       "dominos://",
    "chick-fil-a":  "cfa://",
    "taco bell":    "tacobell://",
    "pizza hut":    "pizzahut://",
    "sonic":        "sonic://",
    "shake shack":  "shakeshack://",
    "panera":       "panerabread://",
    "subway":       "subway://",
    "sweetgreen":   "sweetgreen://",
    "wingstop":     "wingstop://",
}

_APP_WEB_FALLBACKS: dict[str, str] = {
    "starbucks":    "https://www.starbucks.com/rewards",
    "mcdonald":     "https://www.mcdonalds.com/us/en-us/mobile-app.html",
    "chipotle":     "https://www.chipotle.com/order",
    "wendy":        "https://www.wendys.com/order",
    "doordash":     "https://www.doordash.com",
    "uber eats":    "https://www.ubereats.com",
    "walmart":      "https://www.walmart.com",
    "target":       "https://www.target.com",
    "dunkin":       "https://www.dunkindonuts.com/en/mobile-app",
    "dutch bros":   "https://www.dutchbros.com",
    "domino":       "https://www.dominos.com/en/",
    "chick-fil-a":  "https://www.chick-fil-a.com/one",
    "taco bell":    "https://www.tacobell.com/order",
    "pizza hut":    "https://www.pizzahut.com/order",
    "sonic":        "https://www.sonicdrivein.com/app",
    "shake shack":  "https://order.shakeshack.com",
    "panera":       "https://www.panerabread.com/en-us/app/panera-app.html",
    "subway":       "https://www.subway.com/en-us/menunutrition/menu",
    "sweetgreen":   "https://order.sweetgreen.com",
    "wingstop":     "https://www.wingstop.com/order",
}

_FOOD_CATS = {"food", "fast_food", "restaurant", "coffee"}


def _brand_lower(brand: str) -> str:
    return re.sub(r"[^a-z0-9 ]", "", brand.lower()).strip()


def _primary_url(promo: dict) -> str | None:
    url = (promo.get("source_url") or "").strip()
    if url:
        return url
    domain = (promo.get("website_domain") or "").strip()
    if domain:
        return f"https://www.{domain}"
    return None


def _app_info(brand: str) -> tuple[str | None, str | None]:
    slug = _brand_lower(brand)
    for key in _APP_DEEP_LINKS:
        if key in slug:
            return _APP_DEEP_LINKS[key], _APP_WEB_FALLBACKS.get(key)
    return None, None


def _steps_code_url(promo: dict, code: str) -> list[str]:
    steps = [f'Paste code "{code}" at checkout.']
    mp = promo.get("minimum_purchase")
    if mp:
        steps.append(f"Minimum spend: {mp}.")
    steps.append("Confirm the discount is applied before paying.")
    return steps


def _steps_app(promo: dict) -> list[str]:
    if (promo.get("category") or "").lower() in _FOOD_CATS:
        return [
            "Go to Offers or Deals in the app.",
            "Activate the deal and add qualifying items.",
            "Complete your order in-app.",
        ]
    return [
        "Find this promotion in the app.",
        "Add qualifying items to your cart.",
        "Complete checkout in-app.",
    ]


_ACTIVE_STATUSES = {"active", "probably_active", "online_only"}
_NOT_ELIGIBLE: dict = dict(
    eligible=False,
    action_type="not_supported",
    button_label="",
    primary_value=None,
    primary_url=None,
    app_deep_link=None,
    web_fallback_url=None,
    steps_after_click=[],
    eliminates_steps=[],
    effort_level="high",
    confidence=0.0,
)


def _has_real_action(promo: dict) -> bool:
    """True if there's at least one concrete thing the app can do."""
    return bool(
        promo.get("promo_code")
        or promo.get("requires_app")
        or promo.get("source_url")
        or promo.get("website_domain")
    )


def _is_expired(promo: dict) -> bool:
    end = (promo.get("end_date") or "").strip()
    if not end:
        return False
    from datetime import date
    try:
        return date.fromisoformat(end[:10]) < date.today()
    except ValueError:
        return False


def _is_eligible(promo: dict) -> bool:
    status = (promo.get("status") or "").strip()
    if status not in _ACTIVE_STATUSES:
        return False
    if status == "needs_review":
        return False
    if (promo.get("confidence_score") or 0.0) < 0.65:
        return False
    if not (promo.get("promotion_title") or promo.get("title") or "").strip():
        return False
    if _is_expired(promo):
        return False
    if not _has_real_action(promo):
        return False
    return True


def build(promo: dict) -> dict:
    if not _is_eligible(promo):
        return dict(_NOT_ELIGIBLE)

    code        = (promo.get("promo_code") or "").strip() or None
    needs_app   = promo.get("requires_app", False)
    redemption  = (promo.get("redemption_method") or "").strip()
    promo_type  = (promo.get("promotion_type") or "").strip()
    brand       = promo.get("brand", "Brand")
    url         = _primary_url(promo)
    is_food     = (promo.get("category") or "").lower() in _FOOD_CATS

    # 1 ─ Requires app
    if needs_app:
        deep, fallback = _app_info(brand)
        return dict(
            eligible=True,
            action_type="open_app",
            button_label=f"Open {brand} App",
            primary_value=None,
            primary_url=fallback or url,
            app_deep_link=deep,
            web_fallback_url=fallback or url,
            steps_after_click=_steps_app(promo),
            eliminates_steps=["Searching for the offer manually in the app"],
            effort_level="medium",
            confidence=0.80,
        )

    # 2 ─ Code + URL (best case)
    if code and url:
        label = "Order & Apply Code" if is_food else "Copy Code & Shop"
        return dict(
            eligible=True,
            action_type="copy_code_and_open_url",
            button_label=label,
            primary_value=code,
            primary_url=url,
            app_deep_link=None,
            web_fallback_url=None,
            steps_after_click=_steps_code_url(promo, code),
            eliminates_steps=[
                "Manually copying the promo code",
                "Searching for the brand website",
            ],
            effort_level="low",
            confidence=0.95,
        )

    # 3 ─ Code only
    if code:
        return dict(
            eligible=True,
            action_type="copy_code",
            button_label="Copy Code",
            primary_value=code,
            primary_url=url,
            app_deep_link=None,
            web_fallback_url=None,
            steps_after_click=[
                f"Visit {brand}'s website.",
                f'Paste code "{code}" at checkout.',
                "Confirm the discount before paying.",
            ],
            eliminates_steps=["Manually copying the promo code"],
            effort_level="low",
            confidence=0.90,
        )

    # 4 ─ Online deal with URL
    if redemption == "online" and url:
        label = "Order Now" if is_food else "Shop Now"
        steps = (
            ["Add qualifying items and complete your order."]
            if is_food
            else ["Browse the sale.", "Discount applies automatically at checkout."]
        )
        return dict(
            eligible=True,
            action_type="open_url",
            button_label=label,
            primary_value=None,
            primary_url=url,
            app_deep_link=None,
            web_fallback_url=None,
            steps_after_click=steps,
            eliminates_steps=["Searching for the brand website"],
            effort_level="low",
            confidence=0.85,
        )

    # 5 ─ Show code / barcode in store
    if redemption in ("show_code", "in_store") and code:
        return dict(
            eligible=True,
            action_type="show_barcode_or_code",
            button_label="Show In Store",
            primary_value=code,
            primary_url=url,
            app_deep_link=None,
            web_fallback_url=None,
            steps_after_click=[
                "Show this screen to the cashier.",
                "Mention the code if prompted.",
            ],
            eliminates_steps=["Printing a coupon", "Searching for the code"],
            effort_level="low",
            confidence=0.85,
        )

    # 6 ─ In-store (navigate)
    if redemption == "in_store" and url:
        return dict(
            eligible=True,
            action_type="open_maps",
            button_label="Find Nearest Store",
            primary_value=brand,
            primary_url=url,
            app_deep_link=None,
            web_fallback_url=None,
            steps_after_click=[
                "Go to the nearest store.",
                "Mention this promotion at checkout.",
            ],
            eliminates_steps=["Searching for the nearest location"],
            effort_level="medium",
            confidence=0.70,
        )

    # 7 ─ Rewards / membership
    if promo_type in ("reward", "membership_benefit") and url:
        return dict(
            eligible=True,
            action_type="open_rewards",
            button_label="View Rewards",
            primary_value=None,
            primary_url=url,
            app_deep_link=None,
            web_fallback_url=None,
            steps_after_click=[
                "Sign in to your rewards account.",
                "Find and activate this offer.",
            ],
            eliminates_steps=["Searching for the rewards page"],
            effort_level="medium",
            confidence=0.75,
        )

    # 8 ─ Generic steps (has URL at minimum)
    if url:
        return dict(
            eligible=True,
            action_type="show_steps",
            button_label="How to Redeem",
            primary_value=None,
            primary_url=url,
            app_deep_link=None,
            web_fallback_url=None,
            steps_after_click=[
                f"Visit {brand}'s website or store.",
                "Mention this promotion at checkout.",
            ],
            eliminates_steps=[],
            effort_level="high",
            confidence=0.50,
        )

    # 9 ─ Not supported
    return dict(
        eligible=False,
        action_type="not_supported",
        button_label="",
        primary_value=None,
        primary_url=None,
        app_deep_link=None,
        web_fallback_url=None,
        steps_after_click=[],
        eliminates_steps=[],
        effort_level="high",
        confidence=0.0,
    )


def main() -> None:
    data = json.loads(ALL_PROMOS.read_text(encoding="utf-8"))
    promos = data.get("promotions", []) if isinstance(data, dict) else data

    counts: dict[str, int] = {}
    for p in promos:
        fr = build(p)
        p["fast_redemption"] = fr
        counts[fr["action_type"]] = counts.get(fr["action_type"], 0) + 1

    if isinstance(data, dict):
        data["promotions"] = promos

    ALL_PROMOS.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")

    total = len(promos)
    eligible = sum(1 for p in promos if p["fast_redemption"]["eligible"])
    print(f"Fast redemption added to {total} promotions")
    print(f"  Eligible: {eligible}/{total} ({eligible * 100 // total}%)")
    print()
    for action, count in sorted(counts.items(), key=lambda x: -x[1]):
        print(f"  {action}: {count}")
    print(f"\nWrote -> {ALL_PROMOS}")


if __name__ == "__main__":
    main()
