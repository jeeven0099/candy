"""Conservative, offline grounding against text already captured by the scraper."""
from __future__ import annotations

import ipaddress
import hashlib
import re
from datetime import datetime
from urllib.parse import urlsplit


OFFER_FIELDS = (
    "brand", "promotion_title", "promotion_type", "discount_type", "discount_value", "promo_code",
    "minimum_spend", "requires_membership", "membership_name", "requires_app",
    "purchase_required", "new_user_only", "start_date", "end_date",
    "redemption_method", "redemption_steps", "birthday_related",
    "terms_text", "valid_days", "time_start", "time_end", "timezone",
)
_BOOLEAN_FIELDS = {
    "requires_membership", "requires_app", "purchase_required", "new_user_only",
    "birthday_related",
}
_STOP_WORDS = set(
    "a an the and or on in at to for of with your you our off save up get buy "
    "free discount offer deal sale code promo online only all items select "
    "purchase order orders first use extra plus exclusive".split()
)


def offer_snapshot(promo: dict) -> dict:
    snapshot = {key: promo.get(key) for key in OFFER_FIELDS}
    for key in _BOOLEAN_FIELDS:
        snapshot[key] = bool(promo.get(key))
    for key in ("redemption_steps", "valid_days"):
        snapshot[key] = list(promo.get(key) or [])
    if snapshot["timezone"] is None:
        snapshot["timezone"] = "America/New_York"
    return snapshot


def public_http_url(value: object) -> str | None:
    if not isinstance(value, str) or re.search(r"[\s\\]", value):
        return None
    try:
        url = urlsplit(value)
        if (url.scheme not in {"http", "https"} or not url.hostname
                or url.username is not None or url.password is not None
                or url.port not in {None, 80 if url.scheme == "http" else 443}):
            return None
        host = url.hostname.lower()
        if "." not in host or not re.fullmatch(r"[a-z0-9.-]+", host):
            return None
        try:
            ipaddress.ip_address(host)
            return None
        except ValueError:
            pass
        if any(not part or part.startswith("-") or part.endswith("-")
               for part in host.split(".")):
            return None
        return value
    except ValueError:
        return None


def matches_domain(url: object, domain: object) -> bool:
    if not public_http_url(url) or not isinstance(domain, str):
        return False
    domain_url = public_http_url(f"https://{domain}")
    if (not domain_url or urlsplit(domain_url).path or urlsplit(domain_url).query
            or urlsplit(domain_url).fragment):
        return False
    expected = urlsplit(domain_url).hostname.removeprefix("www.")
    host = urlsplit(url).hostname.removeprefix("www.")
    return host == expected or host.endswith("." + expected)


def _norm(text: object) -> str:
    return re.sub(r"\s+", " ", str(text or "").casefold()).strip()


def _contains_value(text: str, value: str) -> bool:
    value = _norm(value)
    number = re.search(r"\d+(?:\.\d+)?", value)
    if number and ("%" in value or "$" in value):
        raw = number.group().removesuffix(".00")
        pattern = re.escape(raw) + (r"(?:\.00)?" if "." not in raw else "")
        if "%" in value:
            pattern = r"(?<![\d.])" + pattern + r"\s*%"
        else:
            pattern = r"\$\s*" + pattern + r"(?!\d|\.\d)"
        return re.search(pattern, text) is not None
    return bool(value) and value in text


def _supports_date(raw: str, text: str) -> bool:
    try:
        day = datetime.fromisoformat(raw).date()
    except (TypeError, ValueError):
        return False
    month = day.strftime("%b").lower()
    full = day.strftime("%B").lower()
    pattern = (
        rf"\b(?:{month}\.?|{full})\s+0?{day.day}(?:st|nd|rd|th)?[,\s]+{day.year}\b"
        rf"|\b{day.year}-0?{day.month}-0?{day.day}\b"
        rf"|\b0?{day.month}/0?{day.day}/{day.year}\b"
    )
    return re.search(pattern, text) is not None


def build_source_evidence(
    promo: dict, text: str, *, source_url: str | None,
    checked_at: str | None, trusted_domain: str | None,
) -> dict:
    result = {
        "schema_version": 1, "validator": "captured_text_v1",
        "status": "unverified", "source_url": source_url,
        "checked_at": checked_at, "excerpt": None,
        "content_hash": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "offer": offer_snapshot(promo), "reasons": [],
    }
    reasons = result["reasons"]
    if not matches_domain(source_url, trusted_domain):
        reasons.append("untrusted_source_url")
    try:
        captured = datetime.fromisoformat(checked_at or "")
        if captured.tzinfo is None:
            reasons.append("capture_timezone_missing")
    except (ValueError, TypeError):
        reasons.append("capture_date_missing")
    if not text.strip():
        reasons.append("source_text_missing")
    if promo.get("synthesized"):
        reasons.append("synthesized_offer_needs_review")
    if promo.get("discount_type") in {None, "unknown"}:
        reasons.append("unknown_discount")
    if not any(isinstance(step, str) and step.strip() for step in promo.get("redemption_steps") or []):
        reasons.append("missing_redemption_steps")
    if promo.get("requires_membership") and not promo.get("membership_name"):
        reasons.append("missing_membership_name")
    if (promo.get("promotion_type") == "coupon" or promo.get("redemption_method") == "show_code") and not promo.get("promo_code"):
        reasons.append("missing_promo_code")
    if reasons:
        return result

    title = _norm(promo.get("promotion_title"))
    anchors = set(re.findall(r"[a-z]{3,}", title)) - _STOP_WORDS
    value = promo.get("discount_value")
    code = _norm(promo.get("promo_code"))
    minimum = promo.get("minimum_spend")
    # Evidence must come from one nearby passage, not unrelated page-wide matches.
    lines = text.splitlines()
    page_url = source_url
    for index, line in enumerate(lines):
        header = re.fullmatch(r"=== (https?://\S+) ===", line.strip())
        if header:
            page_url = header.group(1)
            continue
        if not line.strip():
            continue
        if not matches_domain(page_url, trusted_domain):
            continue
        passage = lines[index:index + 4]
        # Never combine evidence from different pages in a multi-URL scrape.
        for offset, candidate in enumerate(passage[1:], start=1):
            if candidate.startswith("=== "):
                passage = passage[:offset]
                break
        excerpt = "\n".join(passage).strip()[:700]
        normalized = _norm(excerpt)
        dtype = promo.get("discount_type")
        if dtype == "free_shipping":
            value_matches = re.search(r"\bfree\s+(?:standard\s+)?(?:shipping|delivery)\b", normalized)
        elif dtype == "free_item":
            value_matches = re.search(r"\bfree\b|\bcomplimentary\b", normalized)
        else:
            value_matches = _contains_value(normalized, value)
        if not value_matches:
            continue
        if dtype == "percentage_off" and "up to" in normalized and "up to" not in _norm(value):
            continue
        if dtype in {"amount_off", "percentage_off"} and not re.search(
            r"\boff\b|\bsave\b|\bsavings\b|\bdiscount\b|\brebate\b", normalized
        ):
            continue
        if dtype in {"amount_off", "percentage_off"}:
            number = re.search(r"\d+(?:\.\d+)?", _norm(value))
            if not number:
                continue
            amount = re.escape(number.group().removesuffix(".00"))
            if "." not in number.group().removesuffix(".00"):
                amount += r"(?:\.00)?"
            token = (r"\$\s*" + amount + r"(?!\d|\.\d)"
                     if dtype == "amount_off" else r"(?<![\d.])" + amount + r"\s*%")
            claim = (rf"(?:\bsave\b|\bsavings\b|\brebate\b|\bdiscount\b)(?:\s+\w+){{0,3}}\s*{token}"
                     rf"|{token}\s+(?:off|discount|rebate|savings)\b")
            if not re.search(claim, normalized):
                continue
        if code and not re.search(r"(?<!\w)" + re.escape(code) + r"(?!\w)", normalized):
            continue
        if minimum and not _contains_value(normalized, minimum):
            continue
        if any(promo.get(key) and not _supports_date(promo[key], normalized)
               for key in ("start_date", "end_date")):
            continue
        matched = anchors.intersection(re.findall(r"[a-z]{3,}", normalized))
        if anchors and len(matched) < min(2, len(anchors)) and title not in normalized:
            continue
        if not promo.get("new_user_only") and re.search(
            r"\bfirst (?:order|purchase)\b|\bnew (?:customers?|users?|members?) only\b", normalized
        ):
            continue
        if not promo.get("purchase_required") and re.search(
            r"\bwith (?:any |a |qualifying )?purchase\b", normalized
        ):
            continue
        if not promo.get("requires_app") and re.search(r"\b(?:app.only|in.app only)\b", normalized):
            continue
        if not promo.get("requires_membership") and re.search(
            r"\bmembers? only\b|\b(?:rewards|loyalty) members\b", normalized
        ):
            continue
        if not minimum and re.search(
            r"\b(?:orders?|purchases?|spend) (?:of |over |above |at least )?\$\s*\d|\$\d+(?:\.\d+)?\+", normalized
        ):
            continue
        if (re.search(r"\bselect(?:ed)?\b", normalized)
                and not re.search(r"\bselect(?:ed)?\b", title + " " + _norm(promo.get("terms_text")))):
            continue
        result.update(status="supported", excerpt=excerpt, source_url=page_url)
        return result
    reasons.append("offer_not_grounded_in_captured_text")
    return result
