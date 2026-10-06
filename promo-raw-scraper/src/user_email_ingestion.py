from __future__ import annotations

import argparse
import base64
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlparse

# Match the existing Windows email runner's SSL key-log workaround.
os.environ.pop("SSLKEYLOGFILE", None)

import requests
from dateutil import parser as date_parser

from email_pipeline import extract_deal_signals, load_env_file, parse_email_message
from generate_scores import compute_global_quality_score
from hash_content import sha256_text
from local_model_interface import RuleBasedLocalModel
from normalize_promotions import (
    compute_status,
    deduplicate,
    fix_confidence,
    fix_deal_scope,
    fix_free_shipping,
    fix_promotion_title,
    fix_redemption_method,
    fix_rewards_program_title,
    fix_subscription_pricing,
    fix_unknown_type_from_title,
    fix_zero_pct_discount,
    is_placeholder,
    load_brand_lookup,
)
from personal_email_ranker import DEFAULT_PERSONAL_RANK_MODEL, PersonalEmailRanker
from structured_parser import get_model


GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me"
DEFAULT_GMAIL_QUERY = "category:promotions newer_than:14d"
ACTIVE_STATUSES = {"active", "probably_active", "online_only"}
VISIBLE_RANK_FLOOR = 70.0

_PRIVATE_BODY = re.compile(
    r"\bjust\s+for\s+you\b"
    r"|\byour\s+(?:reward|offer|gift|code|coupon|account|exclusive)\b"
    r"|\bunique\s+(?:code|offer)\b"
    r"|\bone[-\s]time\s+(?:code|offer|use)\b"
    r"|\bpersonali[sz]ed\b"
    r"|\bexclusive(?:ly)?\s+for\s+you\b",
    re.IGNORECASE,
)
_PRIVATE_SUBJECT = re.compile(
    r"\bjust\s+for\s+you\b|\bpersonali[sz]ed\b|\byour\s+(?:reward|offer|gift|exclusive)\b",
    re.IGNORECASE,
)
_BARCODE_SIGNALS = re.compile(r"\bbarcode\b|\bqr\s+code\b|\bscan\s+", re.IGNORECASE)
_MEMBER_SIGNALS = re.compile(
    r"\b(?:rewards?|loyalty|insider|circle|plus|elite|member)\s+"
    r"(?:member|exclusive|only|offer|get|price|benefit)\b"
    r"|\bfor\s+(?:our\s+)?(?:rewards?|loyalty|insider|circle|elite)\s+members?\b",
    re.IGNORECASE,
)


@dataclass
class GmailMessage:
    id: str
    thread_id: str
    history_id: str | None
    received_at: str | None
    raw_bytes: bytes
    label_ids: tuple[str, ...] = ()


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _iso_from_gmail_ms(value: str | None) -> str | None:
    if not value:
        return None
    try:
        dt = datetime.fromtimestamp(int(value) / 1000, tz=timezone.utc)
        return dt.isoformat()
    except ValueError:
        return None


def _parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed
    except ValueError:
        return None


def classify_visibility(subject: str, body_text: str, body_html: str) -> str:
    combined = f"{subject}\n{body_text}"
    if _PRIVATE_SUBJECT.search(subject) or _PRIVATE_BODY.search(combined):
        return "private_user_offer"
    if _BARCODE_SIGNALS.search(body_html or ""):
        return "private_user_offer"
    if _MEMBER_SIGNALS.search(combined):
        return "member_offer"
    return "public_general_offer"


class SupabaseAdmin:
    def __init__(self, url: str | None = None, service_key: str | None = None) -> None:
        self.url = (url or os.environ.get("SUPABASE_URL", "")).rstrip("/")
        self.service_key = service_key or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        if not self.url or not self.service_key:
            raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
        self.headers = {
            "apikey": self.service_key,
            "Authorization": f"Bearer {self.service_key}",
            "Content-Type": "application/json",
        }

    def _rest(self, table: str) -> str:
        return f"{self.url}/rest/v1/{table}"

    def get(self, table: str, params: dict[str, str]) -> list[dict[str, Any]]:
        resp = requests.get(self._rest(table), headers=self.headers, params=params, timeout=30)
        resp.raise_for_status()
        return resp.json()

    def patch(self, table: str, params: dict[str, str], payload: dict[str, Any]) -> None:
        resp = requests.patch(self._rest(table), headers=self.headers, params=params, json=payload, timeout=30)
        resp.raise_for_status()

    def insert(self, table: str, payload: dict[str, Any]) -> dict[str, Any] | None:
        headers = {**self.headers, "Prefer": "return=representation"}
        resp = requests.post(self._rest(table), headers=headers, json=payload, timeout=30)
        resp.raise_for_status()
        rows = resp.json()
        return rows[0] if rows else None

    def upsert(self, table: str, payload: dict[str, Any], on_conflict: str) -> None:
        headers = {**self.headers, "Prefer": "resolution=merge-duplicates,return=minimal"}
        resp = requests.post(
            self._rest(table),
            headers=headers,
            params={"on_conflict": on_conflict},
            json=payload,
            timeout=30,
        )
        resp.raise_for_status()


def refresh_access_token(token_row: dict[str, Any], sb: SupabaseAdmin, user_id: str) -> str:
    access_token = token_row.get("access_token") or ""
    expires_at = _parse_iso(token_row.get("access_token_expires_at"))
    if access_token and expires_at and (expires_at - datetime.now(timezone.utc)).total_seconds() > 120:
        return access_token

    refresh_token = token_row.get("refresh_token") or ""
    client_id = os.environ.get("GMAIL_GOOGLE_CLIENT_ID") or os.environ.get("GOOGLE_CLIENT_ID")
    client_secret = os.environ.get("GMAIL_GOOGLE_CLIENT_SECRET") or os.environ.get("GOOGLE_CLIENT_SECRET")
    if not refresh_token or not client_id or not client_secret:
        if access_token:
            return access_token
        raise RuntimeError("Missing Gmail refresh token or Google OAuth client credentials")

    resp = requests.post(
        "https://oauth2.googleapis.com/token",
        data={
            "client_id": client_id,
            "client_secret": client_secret,
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        },
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    expires = datetime.now(timezone.utc).timestamp() + int(data.get("expires_in") or 3300)
    access_token = data["access_token"]
    sb.upsert(
        "gmail_connection_tokens",
        {
            "user_id": user_id,
            "access_token": access_token,
            "refresh_token": refresh_token,
            "access_token_expires_at": datetime.fromtimestamp(expires, tz=timezone.utc).isoformat(),
            "token_type": data.get("token_type", "Bearer"),
            "updated_at": _utc_now(),
        },
        "user_id",
    )
    return access_token


def list_gmail_messages(access_token: str, query: str, limit: int) -> list[dict[str, str]]:
    messages: list[dict[str, str]] = []
    page_token = None
    while limit == 0 or len(messages) < limit:
        params = {
            "q": f"{DEFAULT_GMAIL_QUERY} ({query})" if query != DEFAULT_GMAIL_QUERY else query,
            "labelIds": "CATEGORY_PROMOTIONS",
            "maxResults": min(limit - len(messages), 500) if limit else 500,
        }
        if page_token:
            params["pageToken"] = page_token
        resp = requests.get(
            f"{GMAIL_API}/messages",
            headers={"Authorization": f"Bearer {access_token}"},
            params=params,
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()
        messages.extend(data.get("messages") or [])
        page_token = data.get("nextPageToken")
        if not page_token:
            break
    return messages[:limit] if limit else messages


def fetch_gmail_message(access_token: str, message_id: str) -> GmailMessage:
    resp = requests.get(
        f"{GMAIL_API}/messages/{message_id}",
        headers={"Authorization": f"Bearer {access_token}"},
        params={"format": "raw", "fields": "id,threadId,historyId,internalDate,labelIds,raw"},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    raw = data.get("raw") or ""
    padded = raw + "=" * (-len(raw) % 4)
    raw_bytes = base64.urlsafe_b64decode(padded.encode("ascii"))
    return GmailMessage(
        id=data["id"],
        thread_id=data.get("threadId", ""),
        history_id=data.get("historyId"),
        received_at=_iso_from_gmail_ms(data.get("internalDate")),
        raw_bytes=raw_bytes,
        label_ids=tuple(data.get("labelIds") or []),
    )


def is_in_scope(message: GmailMessage, now: datetime | None = None) -> bool:
    now = now or datetime.now(timezone.utc)
    received = _parse_iso(message.received_at)
    return (
        "CATEGORY_PROMOTIONS" in message.label_ids
        and received is not None
        and now - timedelta(days=14) <= received <= now
    )


def _email_expiry(parsed) -> str | None:
    phrases = extract_deal_signals(parsed)["expiry_phrases"]
    reference = _parse_iso(parsed.sent_at) or datetime.now(timezone.utc)
    for phrase in phrases:
        try:
            expiry = date_parser.parse(phrase, default=reference.replace(hour=0, minute=0, second=0, microsecond=0))
            if expiry.date() < reference.date() and not re.search(r"\b\d{4}\b|\d{1,2}/\d{1,2}/\d{2,4}", phrase):
                if reference.month == 12 and expiry.month == 1:
                    expiry = expiry.replace(year=reference.year + 1)
            return expiry.date().isoformat()
        except (ValueError, OverflowError):
            continue
    return None


def _redemption_link(parsed) -> str | None:
    for link in parsed.links:
        if urlparse(link).scheme not in {"http", "https"}:
            continue
        if re.search(r"unsubscribe|preferences|privacy|view.?in.?browser", link, re.IGNORECASE):
            continue
        return link
    return None


def _build_email_prompt(parsed, visibility: str) -> str:
    return (
        f"Email subject: {parsed.subject}\n"
        f"From: {parsed.sender_email}\n"
        f"Visibility: {visibility}\n"
        f"Brand: {parsed.brand}\n\n"
        "This is a promotional email. Extract redeemable deals only. "
        "Set source_type to email and preserve the visibility value.\n\n"
        f"--- EMAIL TEXT ---\n{parsed.text[:5000]}\n--- END ---"
    )


def extract_promotions(parsed, visibility: str, extraction_model: Any) -> list[dict[str, Any]]:
    text = f"{parsed.subject}\n{parsed.text}"
    promotions = extraction_model.parse_text(
        text=text if isinstance(extraction_model, RuleBasedLocalModel) else _build_email_prompt(parsed, visibility),
        brand=parsed.brand,
        category=None,
        source_path=f"gmail:{parsed.message_id}",
    )
    signals = extract_deal_signals(parsed)
    expiry = _email_expiry(parsed)
    link = _redemption_link(parsed)

    result: list[dict[str, Any]] = []
    for promo in promotions:
        if promo.extraction_status != "success":
            continue
        data = promo.model_dump(mode="json")
        data["brand"] = parsed.brand
        data["source"] = "email"
        data["source_type"] = "email"
        data["visibility"] = visibility
        data["sender_email"] = parsed.sender_email
        data["email_subject"] = parsed.subject
        data["email_date"] = parsed.sent_at
        data["last_confirmed"] = parsed.sent_at
        if not data.get("promo_code") and len(signals["promo_codes"]) == 1:
            data["promo_code"] = signals["promo_codes"][0]
        if not data.get("end_date"):
            data["end_date"] = expiry
        if not data.get("deal_url"):
            data["deal_url"] = link
        data["source_url"] = data.get("deal_url")
        if isinstance(extraction_model, RuleBasedLocalModel):
            data["promotion_title"] = parsed.subject.strip() or data.get("promotion_title")
            # Email confidence comes from redeemable evidence, not newsletter length.
            if data.get("discount_value") and data.get("discount_type") in {"percentage_off", "amount_off", "free_item"}:
                evidence = sum(bool(value) for value in (data.get("promo_code"), data.get("deal_url"), data.get("end_date")))
                data["confidence_score"] = round(0.6 + evidence * 0.05, 2)
        result.append(data)
    return result


def normalize_email_promotions(promos: list[dict[str, Any]]) -> list[dict[str, Any]]:
    now = datetime.now(timezone.utc)
    normalized: list[dict[str, Any]] = []
    for promo in promos:
        if not isinstance(promo, dict) or is_placeholder(promo):
            continue
        promo = fix_zero_pct_discount(promo)
        promo = fix_free_shipping(promo)
        promo = fix_subscription_pricing(promo)
        promo = fix_unknown_type_from_title(promo)
        promo = fix_rewards_program_title(promo)
        promo = fix_promotion_title(promo, promo.get("brand", ""))
        promo = fix_redemption_method(promo)
        promo = fix_deal_scope(promo)
        if promo.get("visibility") != "private_user_offer":
            promo = fix_confidence(promo)
        promo["status"] = compute_status(promo, now)
        promo = compute_global_quality_score(promo)
        normalized.append(promo)
    return deduplicate(normalized)


def _deal_fingerprint(user_id: str, message: GmailMessage, promo: dict[str, Any]) -> str:
    raw = "\n".join(
        [
            user_id,
            message.id,
            promo.get("brand") or "",
            promo.get("promotion_title") or "",
            promo.get("discount_type") or "",
            promo.get("discount_value") or "",
            promo.get("promo_code") or "",
        ]
    )
    return sha256_text(raw)


def _parse_expires_at(promo: dict[str, Any]) -> str | None:
    end_date = promo.get("end_date")
    if not end_date:
        return None
    try:
        return (datetime.fromisoformat(str(end_date)[:10]).replace(tzinfo=timezone.utc) + timedelta(days=1)).isoformat()
    except ValueError:
        return None


def load_user_profile(sb: SupabaseAdmin, user_id: str) -> dict[str, Any]:
    prefs = sb.get("user_preferences", {"select": "*", "user_id": f"eq.{user_id}"})
    brands = sb.get(
        "user_brand_affinity",
        {"select": "brand,affinity_score", "user_id": f"eq.{user_id}", "order": "affinity_score.desc", "limit": "25"},
    )
    cats = sb.get(
        "user_category_affinity",
        {"select": "category,affinity_score", "user_id": f"eq.{user_id}", "order": "affinity_score.desc", "limit": "25"},
    )
    p = prefs[0] if prefs else {}
    return {
        "favorite_brands": p.get("favorite_brands") or [],
        "favorite_categories": p.get("favorite_categories") or [],
        "deal_priorities": list((p.get("deal_type_preferences") or {}).keys()),
        "hidden_brands": [item.get("brand", item) if isinstance(item, dict) else item for item in (p.get("hidden_brands") or [])],
        "brand_affinity": brands,
        "category_affinity": cats,
    }


def iter_connections(
    sb: SupabaseAdmin,
    user_id: str | None,
    google_email: str | None,
    all_users: bool,
) -> Iterable[dict[str, Any]]:
    if not user_id and not google_email and not all_users:
        raise SystemExit("Pass --user-id or --google-email for this personal sync. Use --all-users only when intentionally syncing everyone.")

    params = {"select": "*", "status": "eq.connected"}
    if user_id:
        params["user_id"] = f"eq.{user_id}"
    if google_email:
        params["google_email"] = f"eq.{google_email}"
    return sb.get("gmail_connections", params)


def ingest_for_user(
    sb: SupabaseAdmin,
    connection: dict[str, Any],
    args: argparse.Namespace,
    extraction_model: Any,
    ranker: PersonalEmailRanker,
) -> tuple[int, int]:
    user_id = connection["user_id"]
    job = sb.insert(
        "email_sync_jobs",
        {"user_id": user_id, "status": "running", "requested_reason": args.reason, "started_at": _utc_now()},
    )
    job_id = job["id"] if job else None
    messages_seen = deals_extracted = 0

    try:
        token_rows = sb.get("gmail_connection_tokens", {"select": "*", "user_id": f"eq.{user_id}"})
        if not token_rows:
            raise RuntimeError("No Gmail token row for user")
        access_token = refresh_access_token(token_rows[0], sb, user_id)
        mailbox_resp = requests.get(
            f"{GMAIL_API}/profile",
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=30,
        )
        mailbox_resp.raise_for_status()
        actual_email = mailbox_resp.json().get("emailAddress", "").lower()
        if not actual_email or actual_email != (connection.get("google_email") or "").lower():
            raise RuntimeError("Gmail token does not match the selected Gmail account. Reconnect Gmail.")
        profile = load_user_profile(sb, user_id)

        for item in list_gmail_messages(access_token, args.gmail_query, args.limit):
            message = fetch_gmail_message(access_token, item["id"])
            if not is_in_scope(message):
                continue
            messages_seen += 1
            parsed = parse_email_message(message.raw_bytes)
            signals = extract_deal_signals(parsed)
            if not signals.get("has_signal"):
                continue
            visibility = classify_visibility(parsed.subject, parsed.text, parsed.html)
            content_hash = sha256_text(f"{parsed.sender_email}\n{parsed.subject}\n{parsed.text}")
            extracted = extract_promotions(parsed, visibility, extraction_model)
            brand_lookup = getattr(args, "brand_lookup", {})
            brand_info = brand_lookup.get(parsed.brand.lower(), {})
            for promo in extracted:
                promo["brand"] = brand_info.get("brand") or promo["brand"]
                promo["category"] = promo.get("category") or brand_info.get("category")
                promo["last_confirmed"] = message.received_at or parsed.sent_at
            normalized = normalize_email_promotions(extracted)

            for promo in normalized:
                rank = ranker.rank(promo, profile)
                promo["personal_rank_score"] = rank.score
                promo["personal_rank_model"] = rank.model_name
                promo["personal_rank_reasons"] = rank.reasons
                promo["personal_rank_summary"] = rank.summary
                status = "active" if promo.get("status") in ACTIVE_STATUSES and rank.score >= args.min_rank_score else "suppressed"
                sb.upsert(
                    "user_email_deals",
                    {
                        "user_id": user_id,
                        "gmail_message_id": message.id,
                        "gmail_thread_id": message.thread_id,
                        "content_hash": content_hash,
                        "deal_fingerprint": _deal_fingerprint(user_id, message, promo),
                        "brand": promo.get("brand"),
                        "category": promo.get("category"),
                        "promotion_title": promo.get("promotion_title"),
                        "sender_email": parsed.sender_email,
                        "email_subject": parsed.subject,
                        "email_date": parsed.sent_at,
                        "visibility": visibility,
                        "promotion_json": promo,
                        "extraction_model": args.extraction_model,
                        "personal_rank_model": rank.model_name,
                        "personal_rank_score": rank.score,
                        "personal_rank_reasons": rank.reasons,
                        "personal_rank_summary": rank.summary,
                        "status": status,
                        "expires_at": _parse_expires_at(promo),
                        "received_at": message.received_at or parsed.sent_at,
                        "extracted_at": _utc_now(),
                        "updated_at": _utc_now(),
                    },
                    "user_id,deal_fingerprint",
                )
                deals_extracted += 1

        sb.patch(
            "user_email_deals",
            {"user_id": f"eq.{user_id}", "status": "eq.active", "received_at": f"lt.{(datetime.now(timezone.utc) - timedelta(days=14)).isoformat()}"},
            {"status": "suppressed", "updated_at": _utc_now()},
        )
        sb.upsert(
            "gmail_connections",
            {
                **connection,
                "last_sync_at": _utc_now(),
                "sync_error": None,
                "updated_at": _utc_now(),
            },
            "user_id",
        )
        if job_id:
            sb.patch(
                "email_sync_jobs",
                {"id": f"eq.{job_id}"},
                {
                    "status": "completed",
                    "finished_at": _utc_now(),
                    "messages_seen": messages_seen,
                    "deals_extracted": deals_extracted,
                },
            )
        return messages_seen, deals_extracted
    except Exception as exc:
        sb.patch("gmail_connections", {"user_id": f"eq.{user_id}"}, {"sync_error": str(exc), "updated_at": _utc_now()})
        if job_id:
            sb.patch(
                "email_sync_jobs",
                {"id": f"eq.{job_id}"},
                {"status": "failed", "finished_at": _utc_now(), "messages_seen": messages_seen, "deals_extracted": deals_extracted, "error": str(exc)},
            )
        raise


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Ingest Gmail promotion emails into per-user private deal rows.")
    parser.add_argument("--user-id", default=None, help="users.id to sync one Candy user")
    parser.add_argument("--google-email", default=None, help="Gmail address to sync")
    parser.add_argument("--all-users", action="store_true", help="Sync every connected Gmail account")
    parser.add_argument("--gmail-query", default=os.getenv("EMAIL_GMAIL_QUERY", DEFAULT_GMAIL_QUERY))
    parser.add_argument("--limit", type=int, default=0, help="Maximum messages; 0 reads all matching messages")
    parser.add_argument("--env-file", type=Path, default=Path(__file__).resolve().parents[1] / ".env")
    parser.add_argument("--reason", default="manual")
    parser.add_argument("--min-rank-score", type=float, default=VISIBLE_RANK_FLOOR)
    parser.add_argument("--extraction-model", choices=["rule_based", "ollama", "groq", "openrouter"], default="rule_based")
    parser.add_argument("--ollama-model", default="qwen2.5:14b")
    parser.add_argument("--ollama-host", default="http://localhost:11434")
    parser.add_argument("--ollama-timeout", type=int, default=3600)
    parser.add_argument("--openrouter-model", default="openai/gpt-4o-mini")
    parser.add_argument("--rank-model", default=DEFAULT_PERSONAL_RANK_MODEL)
    parser.add_argument("--cloud-timeout", type=int, default=60)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    if args.limit < 0:
        raise SystemExit("--limit must be zero or positive")
    if not args.user_id and not args.google_email and not args.all_users:
        raise SystemExit("Pass --user-id or --google-email to select your Gmail account.")
    if args.env_file and args.env_file.exists():
        load_env_file(args.env_file)
    args.brand_lookup = load_brand_lookup(Path(__file__).resolve().parents[1] / "sources" / "urls.json")
    sb = SupabaseAdmin()
    extraction_model = RuleBasedLocalModel(min_text_length=1, require_keywords=False) if args.extraction_model == "rule_based" else get_model(
        model_type=args.extraction_model,
        ollama_model=args.ollama_model,
        ollama_host=args.ollama_host,
        ollama_timeout=args.ollama_timeout,
        openrouter_model=args.openrouter_model,
        cloud_timeout=args.cloud_timeout,
    )
    ranker = PersonalEmailRanker(model_name=args.rank_model, timeout=args.cloud_timeout)

    total_messages = total_deals = users = 0
    for connection in iter_connections(sb, args.user_id, args.google_email, args.all_users):
        users += 1
        print(f"[EmailSync] user={connection['user_id']} gmail={connection.get('google_email') or ''}")
        messages, deals = ingest_for_user(sb, connection, args, extraction_model, ranker)
        total_messages += messages
        total_deals += deals
        print(f"  messages={messages} deals={deals}")

    if users == 0:
        raise SystemExit("No connected Gmail account matched. Connect Gmail in Candy Settings first.")

    print(f"[EmailSync] complete users={users} messages={total_messages} deals={total_deals}")


if __name__ == "__main__":
    sys.exit(main())
