"""
email_ingest.py — Read Gmail promotions tab (last 40 days) and save clean
text + metadata with visibility classification.

Visibility values:
  private_user_offer   — personalised to the recipient (barcode, unique code, "just for you")
  member_offer         — requires loyalty membership ("Rewards members get…")
  public_general_offer — sitewide sale, newsletter, no personalisation
  unknown              — cannot determine

Output per email:
  email_text/{brand}_{stamp}_{hash8}.txt
  email_text/{brand}_{stamp}_{hash8}.meta.json
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# Allow emoji and non-ASCII in subjects on Windows consoles
if hasattr(sys.stdout, "buffer"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# Allow imports from the parent src/ directory
_SRC = Path(__file__).resolve().parents[2] / "src"
sys.path.insert(0, str(_SRC))

from email_pipeline import (  # noqa: E402
    extract_deal_signals,
    iter_imap_messages,
    iter_local_eml_files,
    load_env_file,
    parse_email_message,
    safe_slug,
)
from hash_content import sha256_text  # noqa: E402
from logger import append_jsonl  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
EMAIL_TEXT_DIR = ROOT / "email_text"
LOG_FILE = ROOT / "logs" / "ingest_results.jsonl"

DEFAULT_GMAIL_QUERY = "category:promotions newer_than:14d"

# ---------------------------------------------------------------------------
# Visibility classification
# ---------------------------------------------------------------------------

_PRIVATE_BODY = re.compile(
    r"\bjust\s+for\s+you\b"
    r"|\byour\s+(?:reward|offer|gift|code|coupon|account|exclusive)\b"
    r"|\bunique\s+(?:code|offer)\b"
    r"|\bone[-\s]time\s+(?:code|offer|use)\b"
    r"|\bpersonali[sz]ed\b"
    r"|\bexclusive(?:ly)?\s+for\s+you\b"
    r"|\byour\s+special\s+offer\b",
    re.IGNORECASE,
)
_PRIVATE_SUBJECT = re.compile(
    r"\bjust\s+for\s+you\b"
    r"|\bpersonali[sz]ed\b"
    r"|\byour\s+(?:reward|offer|gift|exclusive)\b"
    r"|\bwe\s+(?:miss|saved|picked)\s+(?:you|this\s+for\s+you)\b",
    re.IGNORECASE,
)
_BARCODE_SIGNALS = re.compile(
    r"\bbarcode\b|\bqr\s+code\b|\bscan\s+(?:to\s+redeem|in[-\s]?store)\b",
    re.IGNORECASE,
)
_MEMBER_SIGNALS = re.compile(
    r"\b(?:rewards?|loyalty|insider|circle|plus|elite|member)\s+(?:member|exclusive|only|offer|get|price|benefit)\b"
    r"|\b(?:member|insider|circle|rewards?)\s+(?:sale|savings?|access|perk)\b"
    r"|\bfor\s+(?:our\s+)?(?:rewards?|loyalty|insider|circle|elite)\s+members?\b",
    re.IGNORECASE,
)


def classify_visibility(subject: str, body_text: str, body_html: str) -> str:
    combined = f"{subject}\n{body_text}"
    if _PRIVATE_SUBJECT.search(subject) or _PRIVATE_BODY.search(combined):
        return "private_user_offer"
    if _BARCODE_SIGNALS.search(body_html or ""):
        return "private_user_offer"
    if _MEMBER_SIGNALS.search(combined):
        return "member_offer"
    return "public_general_offer"


# ---------------------------------------------------------------------------
# Dedup
# ---------------------------------------------------------------------------

def _hash_exists(content_hash: str) -> bool:
    for p in EMAIL_TEXT_DIR.glob("*.meta.json"):
        try:
            if json.loads(p.read_text(encoding="utf-8")).get("content_hash") == content_hash:
                return True
        except Exception:
            pass
    return False


# ---------------------------------------------------------------------------
# Process one email
# ---------------------------------------------------------------------------

def process_email(raw_bytes: bytes, source_id: str, dry_run: bool = False) -> dict:
    ingested_at = datetime.now(timezone.utc).isoformat()
    parsed = parse_email_message(raw_bytes)

    if len(parsed.text) < 40:
        return {
            "brand": parsed.brand, "subject": parsed.subject,
            "status": "failed", "error": "text_too_short",
            "ingested_at": ingested_at,
        }

    content_hash = sha256_text(f"{parsed.sender_email}\n{parsed.subject}\n{parsed.text}")

    if dry_run:
        visibility = classify_visibility(parsed.subject, parsed.text, parsed.html)
        return {
            "brand": parsed.brand, "subject": parsed.subject,
            "visibility": visibility, "status": "dry_run",
            "content_hash": content_hash, "ingested_at": ingested_at,
        }

    if _hash_exists(content_hash):
        return {
            "brand": parsed.brand, "subject": parsed.subject,
            "status": "skipped_duplicate_hash",
            "content_hash": content_hash, "ingested_at": ingested_at,
        }

    visibility = classify_visibility(parsed.subject, parsed.text, parsed.html)
    signals = extract_deal_signals(parsed)

    EMAIL_TEXT_DIR.mkdir(parents=True, exist_ok=True)
    sent_stamp = (parsed.sent_at or ingested_at).replace(":", "").replace("-", "")
    sent_stamp = sent_stamp.split(".", 1)[0].replace("+0000", "Z")
    base = f"{safe_slug(parsed.brand)}_{sent_stamp}_{content_hash[:8]}"

    text_path = EMAIL_TEXT_DIR / f"{base}.txt"
    meta_path = EMAIL_TEXT_DIR / f"{base}.meta.json"
    text_path.write_text(parsed.text, encoding="utf-8")

    meta = {
        "brand": parsed.brand,
        "sender": parsed.sender,
        "sender_email": parsed.sender_email,
        "subject": parsed.subject,
        "sent_at": parsed.sent_at,
        "message_id": parsed.message_id,
        "source_id": source_id,
        "source_type": "email",
        "ingested_at": ingested_at,
        "content_hash": content_hash,
        "visibility": visibility,
        "text_length": len(parsed.text),
        "link_count": len(parsed.links),
        "links": parsed.links[:20],
        "deal_signal": signals["has_signal"],
        "total_keyword_count": sum(signals["keyword_hits"].values()),
        "promo_codes": signals["promo_codes"],
        "discount_phrases": signals["discount_phrases"],
        "text_path": str(text_path.relative_to(ROOT)),
    }
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    return {**meta, "status": "success"}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest Gmail promotions tab emails.")
    parser.add_argument("--limit", type=int, default=200)
    parser.add_argument("--since-days", type=int, default=40)
    parser.add_argument("--gmail-query", type=str, default=DEFAULT_GMAIL_QUERY)
    parser.add_argument("--email", type=str, default=None)
    parser.add_argument("--imap-host", type=str, default=None)
    parser.add_argument("--imap-port", type=int, default=None)
    parser.add_argument("--mailbox", type=str, default="INBOX")
    parser.add_argument("--query", type=str, default=None)
    parser.add_argument("--eml-dir", type=Path, default=None)
    parser.add_argument("--env-file", type=Path, default=None)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if args.env_file:
        load_env_file(args.env_file)

    messages = (
        iter_local_eml_files(args.eml_dir, args.limit)
        if args.eml_dir
        else iter_imap_messages(args)
    )

    counts = {"success": 0, "skipped": 0, "failed": 0}
    visibility_counts: dict[str, int] = {}

    for source_id, raw_bytes in messages:
        record = process_email(raw_bytes, source_id=source_id, dry_run=args.dry_run)
        append_jsonl(LOG_FILE, record)
        status = record.get("status", "")
        vis = record.get("visibility", "")
        if status == "success":
            counts["success"] += 1
            visibility_counts[vis] = visibility_counts.get(vis, 0) + 1
        elif "skip" in status:
            counts["skipped"] += 1
        else:
            counts["failed"] += 1
        print(f"  {record['brand']}: {record.get('subject', '')[:60]}")
        print(f"    -> {status}  visibility={vis}")

    print(f"\nDone: {counts['success']} saved, {counts['skipped']} skipped, {counts['failed']} failed")
    for vis, n in sorted(visibility_counts.items()):
        print(f"  {vis}: {n}")


if __name__ == "__main__":
    main()
