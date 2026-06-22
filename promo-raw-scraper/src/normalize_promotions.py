"""
normalize_promotions.py — Post-process structured_outputs/ into normalized_outputs/

Fixes applied to every promotion:
  1. Empty category            — filled from urls.json brand lookup
  2. Brand name                — normalized to canonical name from urls.json
  3. free_item → free_shipping — when title/summary/terms mention FREE shipping/delivery
  4. Missing promotion_title   — generated from discount fields, summary, or brand+type
  5. Unknown redemption_method — inferred from requires_app, steps, scope, discount type
  6. Scope/redemption mismatch — online method → online_only scope, etc.
  7. Confidence score          — penalized for missing key fields or unknown types
  8. Duplicate promotions      — deduplicated by normalized title + discount key
  9. Encoding/typography       — mojibake repaired; curly quotes/dashes replaced with ASCII
"""
from __future__ import annotations

import argparse
import json
import re
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
STRUCTURED_DIR = ROOT / "structured_outputs"
NORMALIZED_DIR = ROOT / "normalized_outputs"
SOURCES_FILE = ROOT / "sources" / "urls.json"
RAW_TEXT_DIR = ROOT / "raw_text"

_TIMESTAMP_RE = re.compile(r"(\d{8}T\d{6}Z)")
_DATE_FORMATS = [
    "%Y-%m-%dT%H:%M:%S",   # ISO datetime: 2026-05-31T23:59:00
    "%Y-%m-%dT%H:%M:%SZ",  # ISO datetime UTC: 2026-05-31T23:59:00Z
    "%Y-%m-%d",             # ISO date: 2026-05-31
    "%m/%d/%Y",
    "%B %d, %Y",
    "%b %d, %Y",
    "%d %B %Y",
    "%b. %d, %Y",
]

# Requires "free" adjacent to shipping/delivery so "w/ Delivery" isn't a false positive
_SHIPPING_RE = re.compile(
    r"\bfree\s+(?:standard\s+|ground\s+|express\s+|2-day\s+)?(?:ship(?:ping|s)?|delivery)\b"
    r"|\bship(?:ping|s)?\s+(?:is\s+)?free\b",
    re.IGNORECASE,
)
_IN_APP_RE = re.compile(r"\bapp\b|\bdownload\b|\bmobile\b", re.IGNORECASE)
_IN_STORE_RE = re.compile(r"\bin[-\s]store\b|\bat\s+(the\s+)?store\b|\bin\s+person\b", re.IGNORECASE)
_CODE_RE = re.compile(r"\bpromo\s+code\b|\bcoupon\s+code\b|\benter\s+(the\s+)?code\b", re.IGNORECASE)
_ONLINE_RE = re.compile(r"\bonline\s+only\b|\bweb\s+only\b|\bwebsite\s+only\b", re.IGNORECASE)
# Matches subscription prices like "$6.99/month", "$18.99 per month", "$99/year"
_SUBSCRIPTION_PRICE_RE = re.compile(
    r"\$\d+(?:\.\d+)?\s*(?:/\s*mo(?:nth)?|per\s+mo(?:nth)?|/\s*yr|/\s*year|per\s+year)\b",
    re.IGNORECASE,
)
# Matches "70% off", "up to 50% off", "$30 off", "save $10" — group(1) is the value
_PERCENT_OFF_RE = re.compile(r"((?:up\s+to\s+)?\d+(?:\.\d+)?%)\s+off\b", re.IGNORECASE)
_AMOUNT_OFF_RE  = re.compile(r"(\$\d+(?:\.\d+)?)\s+off\b", re.IGNORECASE)
_AMOUNT_SAVE_RE = re.compile(r"\bsave\s+(?:up\s+to\s+)?(\$\d+(?:\.\d+)?)\b", re.IGNORECASE)
# Explicit "free shipping/delivery" in title (distinct from any mention of "delivery")
_FREE_SHIPPING_TITLE_RE = re.compile(r"\bfree\s+(?:standard\s+)?(?:shipping|delivery)\b", re.IGNORECASE)
# Placeholder/error titles that the LLM emits when nothing is found
_PLACEHOLDER_RE = re.compile(
    r"^(?:no\s+promotions?\s+found|an\s+error\s+occurred|[a-z\s]+\s+promotion\s*$)",
    re.IGNORECASE,
)


# ---------------------------------------------------------------------------
# Brand / category lookup
# ---------------------------------------------------------------------------

def _extract_domain(url: str) -> str:
    try:
        host = urlparse(url).netloc or ""
        return host.removeprefix("www.")
    except Exception:
        return ""


def load_brand_lookup(sources_file: Path) -> Dict[str, Dict[str, str]]:
    if not sources_file.exists():
        return {}
    sources = json.loads(sources_file.read_text(encoding="utf-8"))
    lookup: Dict[str, Dict[str, str]] = {}
    for entry in sources:
        brand = entry.get("brand", "")
        domain = _extract_domain(entry.get("url", ""))
        info = {
            "brand": brand,
            "category": entry.get("category", ""),
            "website_domain": domain,
            "online_only": bool(entry.get("online_only", False)),
        }
        lookup[_slugify(brand)] = info
        lookup[brand.lower()] = info
    return lookup


def _slugify(value: str) -> str:
    value = value.lower().strip()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    return value.strip("_") or "unknown"


# ---------------------------------------------------------------------------
# Individual fix passes
# ---------------------------------------------------------------------------

def _text_fields(promo: dict) -> str:
    return " ".join(filter(None, [
        promo.get("promotion_title") or "",
        promo.get("short_summary") or "",
        promo.get("terms_text") or "",
        " ".join(promo.get("redemption_steps") or []),
    ]))


_BOGO_RE = re.compile(r"\bbuy\s+one\s+get\s+one\b|\bbogo\b", re.IGNORECASE)


def fix_free_shipping(promo: dict) -> dict:
    dtype = promo.get("discount_type")
    combined = _text_fields(promo)
    title = promo.get("promotion_title") or ""
    # BOGO promos are free_item, not free_shipping — correct LLM misclassification
    if dtype == "free_shipping" and _BOGO_RE.search(title):
        promo["discount_type"] = "free_item"
        promo["discount_value"] = ""
        return promo
    if dtype == "free_item" and _SHIPPING_RE.search(combined):
        promo["discount_type"] = "free_shipping"
        if promo.get("promotion_type") in ("unknown", None):
            promo["promotion_type"] = "sale"
    elif dtype == "unknown" and _FREE_SHIPPING_TITLE_RE.search(title):
        promo["discount_type"] = "free_shipping"
        if promo.get("promotion_type") in ("unknown", None):
            promo["promotion_type"] = "sale"
    return promo


def fix_unknown_type_from_title(promo: dict) -> dict:
    """Recover discount_type from title/summary when LLM left it as unknown."""
    if promo.get("discount_type") != "unknown":
        return promo
    combined = _text_fields(promo)
    m = _PERCENT_OFF_RE.search(combined)
    if m:
        promo["discount_type"] = "percentage_off"
        if not promo.get("discount_value"):
            promo["discount_value"] = m.group(1).strip()
        return promo
    m = _AMOUNT_OFF_RE.search(combined) or _AMOUNT_SAVE_RE.search(combined)
    if m:
        promo["discount_type"] = "amount_off"
        if not promo.get("discount_value"):
            promo["discount_value"] = m.group(1).strip()
        return promo
    return promo


def fix_zero_pct_discount(promo: dict) -> dict:
    """Fix LLM artifacts: 0%/0 discount and $0 value both map to free_item when applicable."""
    dtype = promo.get("discount_type")
    val = (promo.get("discount_value") or "").strip()
    title = (promo.get("promotion_title") or "").lower()

    if dtype == "percentage_off" and val in ("0%", "0"):
        if "free" in title:
            promo["discount_type"] = "free_item"
        else:
            promo["discount_type"] = "unknown"
        promo["discount_value"] = ""

    elif val in ("$0", "0", "$0.00") and "free" in title:
        promo["discount_type"] = "free_item"
        promo["discount_value"] = ""

    elif dtype == "free_shipping" and val in ("0%", "0", "0.0"):
        promo["discount_value"] = ""

    return promo


def is_placeholder(promo: dict) -> bool:
    """Return True for LLM-emitted placeholder/error entries that aren't real promotions."""
    title = (promo.get("promotion_title") or "").strip()
    return bool(_PLACEHOLDER_RE.match(title))


def fix_rewards_program_title(promo: dict) -> dict:
    """Replace generic points-program titles with 'Rewards Program: {Brand}'."""
    if promo.get("discount_type") != "points" or promo.get("discount_value"):
        return promo
    title = promo.get("promotion_title") or ""
    if not title.lower().startswith("rewards program:"):
        promo["promotion_title"] = f"Rewards Program: {promo.get('brand', '')}"
    return promo


_THIRD_PARTY_MEMBERSHIPS = [
    ("aarp",       "AARP",       "paid"),
    ("aaa",        "AAA",        "paid"),
    ("costco",     "Costco",     "paid"),
    ("sam's club", "Sam's Club", "paid"),
    ("bj's",       "BJ's",       "paid"),
]
_MEMBER_TITLE_RE = re.compile(r"\bmembers?\b", re.IGNORECASE)

def fix_third_party_membership(promo: dict) -> dict:
    """Detect known paid third-party memberships (AARP, AAA, etc.) in the title
    when the LLM missed them, and set requires_membership + membership_name accordingly."""
    if promo.get("requires_membership"):
        return promo
    combined = " ".join(filter(None, [
        promo.get("promotion_title", ""),
        promo.get("short_summary", ""),
    ])).lower()
    if not _MEMBER_TITLE_RE.search(combined):
        return promo
    for keyword, name, cost in _THIRD_PARTY_MEMBERSHIPS:
        if keyword in combined:
            promo["requires_membership"] = True
            promo["membership_name"] = name
            promo["membership_cost"] = cost
            break
    return promo


def fix_requires_membership_type(promo: dict) -> dict:
    """Upgrade promotion_type to membership_benefit when the deal explicitly requires membership."""
    if not promo.get("requires_membership"):
        return promo
    if promo.get("promotion_type") in ("reward", "membership_benefit"):
        return promo
    promo["promotion_type"] = "membership_benefit"
    return promo


def fix_subscription_pricing(promo: dict) -> dict:
    """Promote unknown-typed promos that mention a recurring price to sale_price."""
    if promo.get("discount_type") != "unknown":
        return promo
    combined = _text_fields(promo)
    m = _SUBSCRIPTION_PRICE_RE.search(combined)
    if m:
        promo["discount_type"] = "sale_price"
        if not promo.get("discount_value"):
            promo["discount_value"] = m.group(0).strip()
        if promo.get("promotion_type") in ("unknown", None):
            promo["promotion_type"] = "membership_benefit"
    return promo


_DISCOUNT_LABELS: Dict[str, str] = {
    "percentage_off": "{value} Off",
    "amount_off":     "{value} Off",
    "free_item":      "Free {value}",
    "free_shipping":  "Free Shipping",
    "points":         "{value} Points",
    "sale_price":     "{value} Sale",
}


_CURLY_QUOTE_MAP = str.maketrans({
    '‘': "'", '’': "'",   # ' '
    '“': '"', '”': '"',   # " "
    '–': '-', '—': '-',   # – —
    '…': '...',                # …
    '®': '',                   # ®
    '™': '',                   # ™
})

def _fix_str(s: str) -> str:
    """Repair latin-1/utf-8 mojibake then normalize fancy typography to ASCII."""
    try:
        s = s.encode('latin-1').decode('utf-8')
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass
    return s.translate(_CURLY_QUOTE_MAP)


def fix_encoding(promo: dict) -> dict:
    """Fix encoding on all human-visible text fields."""
    for field in ('promotion_title', 'short_summary', 'terms_text', 'membership_name'):
        val = promo.get(field)
        if isinstance(val, str):
            promo[field] = _fix_str(val)
    return promo


def fix_promotion_title(promo: dict, brand: str) -> dict:
    if promo.get("promotion_title"):
        return promo

    dtype = promo.get("discount_type", "unknown")
    dvalue = promo.get("discount_value")
    summary = (promo.get("short_summary") or "").strip()
    ptype = (promo.get("promotion_type") or "unknown").replace("_", " ").title()

    if dvalue and dtype in _DISCOUNT_LABELS:
        promo["promotion_title"] = _DISCOUNT_LABELS[dtype].format(value=dvalue)
    elif dtype == "free_shipping":
        promo["promotion_title"] = "Free Shipping"
    elif summary:
        end = summary.find(". ")
        promo["promotion_title"] = summary[:end].strip() if 0 < end <= 80 else summary[:80].strip()
    else:
        promo["promotion_title"] = f"{brand} {ptype}"

    return promo


def fix_redemption_method(promo: dict) -> dict:
    if promo.get("redemption_method") not in ("unknown", None):
        return promo

    combined = _text_fields(promo)
    steps = " ".join(promo.get("redemption_steps") or [])

    if promo.get("requires_app") or _IN_APP_RE.search(steps):
        promo["redemption_method"] = "in_app"
    elif _CODE_RE.search(combined):
        promo["redemption_method"] = "show_code"
    elif _IN_STORE_RE.search(steps):
        promo["redemption_method"] = "in_store"
    elif promo.get("deal_scope") == "online_only" or _ONLINE_RE.search(combined):
        promo["redemption_method"] = "online"

    return promo


def fix_deal_scope(promo: dict) -> dict:
    method = promo.get("redemption_method")
    scope = promo.get("deal_scope", "unknown")

    # Only mark online_only when the text explicitly says so — don't infer from
    # redemption_method=online, since the model sets that for any web-scraped deal
    # even when the offer is redeemable in-store too.
    if method in ("in_app", "in_store") and scope == "online_only":
        promo["deal_scope"] = "brand_level"
    elif method == "in_app" and scope == "unknown":
        promo["deal_scope"] = "brand_level"

    return promo


def fix_confidence(promo: dict) -> dict:
    score = float(promo.get("confidence_score") or 0.0)

    if promo.get("extraction_status") != "success":
        score = min(score, 0.4)
    if promo.get("discount_type") == "unknown" and promo.get("promotion_type") == "unknown":
        score -= 0.2
    # No concrete discount value AND unknown type = menu item / feature highlight, not a deal
    if promo.get("discount_type") == "unknown" and not promo.get("discount_value"):
        score = min(score, 0.6)
    if not promo.get("promotion_title"):
        score -= 0.15
    if not promo.get("short_summary"):
        score -= 0.1
    if not promo.get("discount_value") and promo.get("discount_type") not in (
        "free_item", "free_shipping", "points"
    ):
        score -= 0.05

    promo["confidence_score"] = round(max(0.0, min(1.0, score)), 3)
    return promo


# ---------------------------------------------------------------------------
# Deduplication
# ---------------------------------------------------------------------------

_CARD_PARTNER_RE = re.compile(
    r"\b(with|using|via)\s+the\s+.{5,60}(card|credit|debit|rewards)\b",
    re.IGNORECASE,
)


def _dedup_key(promo: dict) -> tuple:
    title = (promo.get("promotion_title") or "").lower()
    # Strip credit-card/bank suffixes before hashing so card-variant duplicates collapse
    title = _CARD_PARTNER_RE.sub("", title)
    title = re.sub(r"[^a-z0-9]", "", title)
    return (title, promo.get("discount_type"), promo.get("discount_value"))


def deduplicate(promotions: List[dict]) -> List[dict]:
    seen: Dict[tuple, int] = {}
    result: List[dict] = []

    for promo in promotions:
        key = _dedup_key(promo)
        if not key[0]:
            result.append(promo)
            continue

        if key in seen:
            idx = seen[key]
            if (promo.get("confidence_score") or 0) > (result[idx].get("confidence_score") or 0):
                result[idx] = promo
        else:
            seen[key] = len(result)
            result.append(promo)

    return result


# ---------------------------------------------------------------------------
# Status computation
# ---------------------------------------------------------------------------

def _parse_end_date(date_str: str) -> Optional[date]:
    for fmt in _DATE_FORMATS:
        try:
            return datetime.strptime(date_str.strip(), fmt).date()
        except ValueError:
            continue
    return None


def _scrape_age_days(source_path: str, now: datetime) -> Optional[float]:
    m = _TIMESTAMP_RE.search(source_path)
    if not m:
        return None
    try:
        ts = datetime.strptime(m.group(1), "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
        return (now - ts).total_seconds() / 86400
    except ValueError:
        return None


def compute_status(promo: dict, now: datetime) -> str:
    """
    Priority order:
      expired       — end_date parsed and in the past
      low_confidence — confidence < 0.4
      needs_review  — source > 30 days old, OR confidence < 0.6, OR source 14-30 days old
      online_only   — deal_scope == online_only
      probably_active — no end_date, freshly scraped (< 14 days)
      active        — end_date in future, all checks passed
    """
    confidence = float(promo.get("confidence_score") or 0.0)
    end_date_str = promo.get("end_date") or ""
    source_path = promo.get("source_path", "")
    deal_scope = promo.get("deal_scope", "unknown")

    if end_date_str:
        parsed = _parse_end_date(end_date_str)
        if parsed is not None and parsed < now.date():
            return "expired"

    if confidence < 0.4:
        return "low_confidence"

    age = _scrape_age_days(source_path, now)

    if age is not None and age > 30:
        return "needs_review"

    if confidence < 0.6:
        return "needs_review"

    if age is not None and age > 14:
        return "needs_review"

    if deal_scope == "online_only":
        return "online_only"

    if not end_date_str:
        return "probably_active"

    return "active"


# ---------------------------------------------------------------------------
# File-level processing
# ---------------------------------------------------------------------------

def normalize_file(
    input_path: Path,
    brand_lookup: Dict[str, Dict[str, str]],
    now: Optional[datetime] = None,
) -> Optional[dict]:
    if now is None:
        now = datetime.now(timezone.utc)

    data = json.loads(input_path.read_text(encoding="utf-8", errors="replace"))

    raw_brand = data.get("brand", "")
    brand_info = brand_lookup.get(_slugify(raw_brand)) or brand_lookup.get(raw_brand.lower()) or {}
    canonical_brand = brand_info.get("brand") or raw_brand
    category = brand_info.get("category") or ""
    website_domain = brand_info.get("website_domain") or ""

    # Load og:image and source URL from the scrape meta.json if available
    og_image: Optional[str] = None
    source_url: Optional[str] = None
    source_path = data.get("source_path", "")
    if source_path:
        meta_path = RAW_TEXT_DIR / (Path(source_path).stem + ".meta.json")
        if meta_path.exists():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
                og_image = meta.get("og_image")
                source_url = meta.get("final_url") or meta.get("url")
            except Exception:
                pass

    promotions = data.get("promotions")
    if not isinstance(promotions, list):
        return None

    normalized: List[dict] = []
    for promo in promotions:
        if not isinstance(promo, dict):
            continue
        if is_placeholder(promo):
            continue
        promo["brand"] = canonical_brand
        if not promo.get("category") and category:
            promo["category"] = category
        if website_domain:
            promo["website_domain"] = website_domain
        if og_image:
            promo["og_image_url"] = og_image
        if source_url:
            promo["source_url"] = source_url
        promo = fix_zero_pct_discount(promo)
        promo = fix_free_shipping(promo)
        promo = fix_subscription_pricing(promo)
        promo = fix_unknown_type_from_title(promo)
        promo = fix_third_party_membership(promo)
        promo = fix_requires_membership_type(promo)
        promo = fix_rewards_program_title(promo)
        promo = fix_promotion_title(promo, canonical_brand)
        promo = fix_encoding(promo)
        promo = fix_redemption_method(promo)
        promo = fix_deal_scope(promo)
        # Force online routing for DTC/online-only brands regardless of LLM output
        if brand_info.get("online_only"):
            promo["deal_scope"] = "online_only"
            if promo.get("redemption_method") not in ("online", "show_code"):
                promo["redemption_method"] = "online"
        promo = fix_confidence(promo)
        promo["status"] = compute_status(promo, now)
        normalized.append(promo)

    normalized = deduplicate(normalized)

    return {
        "brand": canonical_brand,
        "category": category,
        "website_domain": website_domain,
        "source_path": data.get("source_path", ""),
        "last_updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "promotion_count": len(normalized),
        "promotions": normalized,
    }


# ---------------------------------------------------------------------------
# Stale file pruning
# ---------------------------------------------------------------------------

def prune_stale_normalized(output_dir: Path, max_age_days: int = 30) -> int:
    """Remove normalized output files whose source scrape is older than max_age_days.

    Brands that are scraped daily but whose content hasn't changed (skipped_duplicate_hash
    or skipped_similar) keep old source_path timestamps. Before pruning, check whether a
    recent raw text file exists for the brand — if so, the brand is actively being scraped
    and should not be removed.
    """
    now = datetime.now(timezone.utc)
    removed = 0
    for path in sorted(output_dir.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
            source_path = data.get("source_path", "")
            age = _scrape_age_days(source_path, now)
            if age is None or age <= max_age_days:
                continue

            # The embedded source_path is stale, but brands whose content hasn't changed
            # (skipped_duplicate_hash) get their raw file touched on each successful scrape.
            # Check the raw file's mtime rather than its filename timestamp.
            slug = path.stem  # e.g. "nike" or "chick_fil_a"
            recent_files = sorted(RAW_TEXT_DIR.glob(f"{slug}_*.txt"))
            if recent_files:
                mtime = datetime.fromtimestamp(recent_files[-1].stat().st_mtime, tz=timezone.utc)
                mtime_age = (now - mtime).total_seconds() / 86400
                if mtime_age <= max_age_days:
                    continue  # raw file touched recently = brand was verified today

            path.unlink()
            removed += 1
            print(f"  [PRUNED] {path.stem} — scrape is {age:.0f} days old (no recent raw file found)")
        except Exception:
            pass
    return removed


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Normalize structured_outputs/ → normalized_outputs/"
    )
    parser.add_argument("--brand", type=str, default=None, help="Filter by brand substring")
    parser.add_argument("--input-dir", type=str, default=None, help="Override input directory")
    parser.add_argument("--output-dir", type=str, default=None, help="Override output directory")
    parser.add_argument("--stale-days", type=int, default=30,
                        help="Remove normalized files older than this many days (default: 30)")
    args = parser.parse_args()

    input_dir = Path(args.input_dir) if args.input_dir else STRUCTURED_DIR
    output_dir = Path(args.output_dir) if args.output_dir else NORMALIZED_DIR
    output_dir.mkdir(parents=True, exist_ok=True)

    brand_lookup = load_brand_lookup(SOURCES_FILE)
    now = datetime.now(timezone.utc)

    files = sorted(f for f in input_dir.glob("*.json") if f.is_file())
    if args.brand:
        files = [f for f in files if args.brand.lower() in f.stem.lower()]

    ok = failed = skipped = 0

    for path in files:
        try:
            result = normalize_file(path, brand_lookup, now)
            if result is None:
                print(f"  [SKIP] {path.stem} — no promotions array")
                skipped += 1
                continue

            out_path = output_dir / path.name
            out_path.write_text(
                json.dumps(result, indent=2, ensure_ascii=False),
                encoding="utf-8",
            )
            before = len(json.loads(path.read_text(encoding="utf-8")).get("promotions", []))
            after = result["promotion_count"]
            dedup_note = f" (deduped {before - after})" if before != after else ""
            print(f"  {path.stem}: {after} promotions{dedup_note} -> {out_path.name}")
            ok += 1
        except Exception as exc:
            print(f"  [ERROR] {path.stem}: {exc}")
            failed += 1

    print(f"\nDone: {ok} normalized, {skipped} skipped, {failed} failed -> {output_dir}/")

    pruned = prune_stale_normalized(output_dir, max_age_days=args.stale_days)
    if pruned:
        print(f"Pruned {pruned} stale normalized file(s) (>{args.stale_days} days old)")


if __name__ == "__main__":
    main()
