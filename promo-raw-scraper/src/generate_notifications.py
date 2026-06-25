"""
generate_notifications.py — compute notification candidates after scoring.

Runs after generate_scores.py. Reads all_promotions.json, user_memberships.json,
brand_affinity.json, and user_preferences.json; writes notification_candidates.json
to the Flutter app assets.

Signal groups (require ≥ 2 distinct groups to fire):
  personal — favorite brand, high inbox affinity (10+ emails), private email deal,
             confirmed member, birthday-related deal
  value    — free item (non-trial), BOGO, ≥50% off, expiring today/tomorrow
  context  — today-only deal, low friction (no membership/app/spend required)

Hard disqualifiers:
  - confidence_score < 0.75
  - discount_type == "points"
  - requires paid membership AND user is not a confirmed member
  - new_user_only AND user is evidently an existing customer
  - global_quality_score < 75

Near Me signals are intentionally excluded for beta.
"""
from __future__ import annotations

import json
import re
from datetime import date, datetime, timezone
from pathlib import Path

ROOT           = Path(__file__).resolve().parents[1]
ALL_PROMOS     = ROOT / "all_promotions.json"
AFFINITY_FILE  = ROOT / "email_pipeline" / "logs" / "brand_affinity.json"
USER_PREFS     = ROOT / "user_preferences.json"
MEMBERSHIPS_IN = ROOT.parent / "promo_viewer" / "assets" / "user_memberships.json"
ASSETS_DIR     = ROOT.parent / "promo_viewer" / "assets"
OUTPUT         = ASSETS_DIR / "notification_candidates.json"

NOTIFY_THRESHOLD    = 75.0
MIN_SIGNAL_GROUPS   = 2

_BOGO_RE   = re.compile(r'\bbogo\b|buy.one.get.one', re.IGNORECASE)
_TRIAL_RE  = re.compile(
    r'\bfree\s+trial\b|\btrial\b|\d+\s+(?:months?|weeks?|days?)\s+free',
    re.IGNORECASE,
)


def _slugify(s: str) -> str:
    return re.sub(r'[^a-z0-9]', '', (s or '').lower())


def _extract_percent(value: str | None) -> float | None:
    if not value:
        return None
    m = re.search(r'(\d+(?:\.\d+)?)\s*%', value)
    return float(m.group(1)) if m else None


# ---------------------------------------------------------------------------
# Signal detection helpers
# ---------------------------------------------------------------------------

def _is_expiring_soon(promo: dict) -> bool:
    """Returns True if deal expires today or tomorrow."""
    end = (promo.get('end_date') or '').strip()
    if not end:
        return False
    try:
        delta = (date.fromisoformat(end[:10]) - date.today()).days
        return 0 <= delta <= 1
    except ValueError:
        return False


def _is_today_only(promo: dict) -> bool:
    """Returns True if deal is only valid today."""
    valid_days = promo.get('valid_days') or []
    if len(valid_days) == 1:
        today_name = date.today().strftime('%A').lower()
        if valid_days[0].lower() in (today_name, today_name[:3]):
            return True
    end = (promo.get('end_date') or '').strip()
    if end:
        try:
            return date.fromisoformat(end[:10]) == date.today()
        except ValueError:
            pass
    return False


def _is_low_friction(promo: dict) -> bool:
    return (
        not promo.get('requires_membership')
        and not promo.get('requires_app')
        and not promo.get('minimum_spend')
        and not promo.get('purchase_required')
    )


def _is_email_exclusive(promo: dict) -> bool:
    """Deal came from a private email (not a public web scrape)."""
    return (
        promo.get('email_date') is not None
        or promo.get('source_type') == 'email'
        or promo.get('visibility') == 'private_user_offer'
    )


# ---------------------------------------------------------------------------
# Core classification
# ---------------------------------------------------------------------------

def get_signal_groups(
    promo: dict,
    member_brands: set[str],
    affinity: dict,
    user_prefs: dict,
) -> set[str]:
    groups: set[str] = set()
    brand_slug = _slugify(promo.get('brand', ''))
    title = promo.get('promotion_title') or ''
    dtype = promo.get('discount_type') or ''

    # ── Personal ─────────────────────────────────────────────────────────────
    fav_slugs = {_slugify(b) for b in user_prefs.get('favorite_brands', [])}
    if brand_slug in fav_slugs:
        groups.add('personal')

    for aff_brand, data in affinity.items():
        if _slugify(aff_brand) == brand_slug and data.get('email_count', 0) >= 10:
            groups.add('personal')
            break

    if _is_email_exclusive(promo):
        groups.add('personal')

    if brand_slug in member_brands:
        groups.add('personal')

    if promo.get('birthday_related'):
        groups.add('personal')

    # ── Value ─────────────────────────────────────────────────────────────────
    if dtype == 'free_item' and not _TRIAL_RE.search(title):
        groups.add('value')

    if _BOGO_RE.search(title):
        groups.add('value')

    if dtype == 'percentage_off':
        pct = _extract_percent(promo.get('discount_value'))
        if pct is not None and pct >= 50:
            groups.add('value')

    if _is_expiring_soon(promo):
        groups.add('value')

    # ── Context ──────────────────────────────────────────────────────────────
    if _is_today_only(promo):
        groups.add('context')

    if _is_low_friction(promo):
        groups.add('context')

    return groups


def is_disqualified(
    promo: dict,
    member_brands: set[str],
    affinity: dict,
) -> tuple[bool, str]:
    dtype = promo.get('discount_type') or ''
    brand_slug = _slugify(promo.get('brand', ''))

    if (promo.get('confidence_score') or 0.0) < 0.75:
        return True, 'low_confidence'

    if dtype == 'points':
        return True, 'points'

    if promo.get('requires_membership'):
        cost = (promo.get('membership_cost') or '').lower()
        if 'paid' in cost and brand_slug not in member_brands:
            return True, 'paid_membership_not_member'

    # new_user_only skipped when user is clearly an existing customer
    if promo.get('new_user_only'):
        is_member = brand_slug in member_brands
        has_affinity = any(
            _slugify(b) == brand_slug and data.get('email_count', 0) >= 3
            for b, data in affinity.items()
        )
        if is_member or has_affinity:
            return True, 'new_user_only_existing_customer'

    return False, ''


def make_notification_text(promo: dict) -> tuple[str, str]:
    """Returns (notification_title, notification_body)."""
    brand = promo.get('brand', '')
    title = (promo.get('promotion_title') or '')
    dtype = promo.get('discount_type') or ''
    end   = (promo.get('end_date') or '').strip()

    expires_today = False
    if end:
        try:
            expires_today = date.fromisoformat(end[:10]) == date.today()
        except ValueError:
            pass

    if expires_today:
        body = f'Expires today: {title}'
    elif promo.get('birthday_related'):
        body = f'Birthday deal: {title}'
    elif dtype == 'free_item':
        body = f'Free: {title}'
    elif _BOGO_RE.search(title):
        body = title
    else:
        body = title

    notif_title = brand if brand else 'New deal'
    return notif_title, body[:120]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    promos_raw = json.loads(ALL_PROMOS.read_text(encoding='utf-8'))
    promos: list[dict] = promos_raw.get('promotions', promos_raw) if isinstance(promos_raw, dict) else promos_raw

    affinity: dict = {}
    if AFFINITY_FILE.exists():
        raw = json.loads(AFFINITY_FILE.read_text(encoding='utf-8'))
        affinity = raw.get('brands', raw) if isinstance(raw, dict) else {}

    user_prefs: dict = {}
    if USER_PREFS.exists():
        user_prefs = json.loads(USER_PREFS.read_text(encoding='utf-8'))

    member_brands: set[str] = set()
    if MEMBERSHIPS_IN.exists():
        raw = json.loads(MEMBERSHIPS_IN.read_text(encoding='utf-8'))
        for m in raw.get('memberships', []):
            member_brands.add(_slugify(m.get('brand', '')))

    candidates = []
    skip_counts: dict[str, int] = {}

    for promo in promos:
        score = promo.get('global_quality_score', 0.0)
        if score < NOTIFY_THRESHOLD:
            skip_counts['below_threshold'] = skip_counts.get('below_threshold', 0) + 1
            continue

        disq, reason = is_disqualified(promo, member_brands, affinity)
        if disq:
            skip_counts[reason] = skip_counts.get(reason, 0) + 1
            continue

        groups = get_signal_groups(promo, member_brands, affinity, user_prefs)
        if len(groups) < MIN_SIGNAL_GROUPS:
            skip_counts['insufficient_signal_diversity'] = skip_counts.get('insufficient_signal_diversity', 0) + 1
            continue

        notif_title, notif_body = make_notification_text(promo)
        brand_slug = _slugify(promo.get('brand', ''))
        promo_id = f"{brand_slug}_{_slugify(promo.get('promotion_title', ''))}"
        if len(promo_id) > 100:
            promo_id = promo_id[:100]

        candidates.append({
            'promo_id':           promo_id,
            'brand':              promo.get('brand', ''),
            'title':              promo.get('promotion_title', ''),
            'notify_score':       score,
            'signal_groups':      sorted(groups),
            'notification_title': notif_title,
            'notification_body':  notif_body,
            'discount_type':      promo.get('discount_type'),
            'discount_value':     promo.get('discount_value'),
            'end_date':           promo.get('end_date'),
            'website_domain':     promo.get('website_domain'),
            'source_url':         promo.get('source_url'),
        })

    candidates.sort(key=lambda c: c['notify_score'], reverse=True)

    output = {
        'generated_at': datetime.now(timezone.utc).isoformat(),
        'threshold':    NOTIFY_THRESHOLD,
        'total':        len(candidates),
        'candidates':   candidates,
    }
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False), encoding='utf-8')

    print(f'Notification candidates: {len(candidates)} of {len(promos)} deals qualify')
    print(f'Skip reasons: {skip_counts}')
    if candidates:
        print('Top candidates:')
        for c in candidates[:5]:
            print(f'  {c["notify_score"]:5.1f}  [{c["brand"]}]  {c["title"][:55]}')
            print(f'         groups={c["signal_groups"]}')
    print(f'Wrote -> {OUTPUT}')


if __name__ == '__main__':
    main()
