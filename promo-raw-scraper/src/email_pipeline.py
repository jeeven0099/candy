from __future__ import annotations

import argparse
import email.utils
import imaplib
import json
import os
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from email.header import decode_header, make_header
from email.message import EmailMessage
from email.parser import BytesParser
from email.policy import default
from html import unescape
from pathlib import Path
from typing import Iterable

from bs4 import BeautifulSoup

from hash_content import sha256_text
from logger import append_jsonl


ROOT = Path(__file__).resolve().parents[1]
RAW_EMAIL_DIR = ROOT / 'raw_email'
RAW_EMAIL_TEXT_DIR = ROOT / 'raw_email_text'
LOG_FILE = ROOT / 'logs' / 'email_results.jsonl'
DEAL_CANDIDATES_FILE = ROOT / 'logs' / 'email_deal_candidates.jsonl'

PROMO_KEYWORDS = [
    'sale',
    'deal',
    'offer',
    'discount',
    'promo',
    'coupon',
    'reward',
    'rewards',
    'free',
    'save',
    'clearance',
    'expires',
    'valid',
]

CODE_RE = re.compile(
    r'\b(?:promo\s+code|coupon\s+code|offer\s+code|code|use\s+code|enter\s+code)\s*[:\-]?\s*([A-Z0-9][A-Z0-9-]{3,24})\b',
    re.IGNORECASE,
)
PERCENT_DISCOUNT_RE = re.compile(r'\b(?:up\s+to\s+)?\d{1,3}%\s+off\b|\bsave\s+\d{1,3}%\b', re.IGNORECASE)
DOLLAR_DISCOUNT_RE = re.compile(r'\$\d+(?:\.\d{2})?\s+off\b|\bsave\s+\$\d+(?:\.\d{2})?\b', re.IGNORECASE)
EXPIRY_RE = re.compile(
    r'\b(?:expires?|ends?|valid\s+(?:through|until))\s+(?:on\s+)?'
    r'([A-Za-z]{3,9}\.?\s+\d{1,2}(?:,\s*\d{4})?|\d{1,2}/\d{1,2}(?:/\d{2,4})?)',
    re.IGNORECASE,
)
URL_RE = re.compile(r'https?://[^\s<>"\']+', re.IGNORECASE)


@dataclass(frozen=True)
class ParsedEmail:
    brand: str
    sender: str
    sender_email: str
    subject: str
    sent_at: str | None
    message_id: str
    text: str
    html: str
    links: list[str]


def utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def safe_slug(value: str, fallback: str = 'email') -> str:
    safe = ''.join(ch.lower() if ch.isalnum() else '_' for ch in value)
    while '__' in safe:
        safe = safe.replace('__', '_')
    return safe.strip('_') or fallback


def decode_mime(value: str | None) -> str:
    if not value:
        return ''
    try:
        return str(make_header(decode_header(value)))
    except Exception:
        return value


def parse_email_date(value: str | None) -> str | None:
    if not value:
        return None
    try:
        parsed = email.utils.parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat()


def infer_brand(from_header: str) -> tuple[str, str, str]:
    name, address = email.utils.parseaddr(from_header)
    decoded_name = decode_mime(name).strip()
    sender_email = address.strip()
    if decoded_name:
        brand = decoded_name
    elif sender_email and '@' in sender_email:
        domain = sender_email.split('@', 1)[1].split('.', 1)[0]
        brand = domain.replace('-', ' ').replace('_', ' ').title()
    else:
        brand = 'Unknown'
    return brand, decoded_name or sender_email, sender_email


def normalize_text(text: str) -> str:
    text = unescape(text or '').replace('\xa0', ' ')
    lines = [line.strip() for line in text.splitlines()]
    lines = [line for line in lines if line]
    return '\n'.join(lines).strip()


def html_to_text(html: str) -> str:
    soup = BeautifulSoup(html or '', 'lxml')
    for tag in soup(['script', 'style', 'noscript']):
        tag.decompose()
    return normalize_text(soup.get_text('\n'))


def extract_body_parts(message: EmailMessage) -> tuple[str, str]:
    plain_parts: list[str] = []
    html_parts: list[str] = []

    for part in message.walk():
        if part.is_multipart():
            continue
        if part.get_content_disposition() == 'attachment':
            continue
        content_type = part.get_content_type()
        try:
            content = part.get_content()
        except Exception:
            payload = part.get_payload(decode=True) or b''
            charset = part.get_content_charset() or 'utf-8'
            content = payload.decode(charset, errors='replace')
        if not isinstance(content, str):
            continue
        if content_type == 'text/plain':
            plain_parts.append(content)
        elif content_type == 'text/html':
            html_parts.append(content)

    plain = normalize_text('\n'.join(plain_parts))
    html = '\n'.join(html_parts)
    if not plain and html:
        plain = html_to_text(html)
    return plain, html


def extract_links(text: str, html: str) -> list[str]:
    links: list[str] = []
    for match in URL_RE.findall(text or ''):
        links.append(match.rstrip(').,;]'))

    if html:
        soup = BeautifulSoup(html, 'lxml')
        for tag in soup.find_all('a', href=True):
            href = tag['href'].strip()
            if href.startswith('http://') or href.startswith('https://'):
                links.append(href)

    seen = set()
    unique_links = []
    for link in links:
        if link not in seen:
            seen.add(link)
            unique_links.append(link)
    return unique_links[:50]


def parse_email_message(raw_bytes: bytes) -> ParsedEmail:
    message = BytesParser(policy=default).parsebytes(raw_bytes)
    subject = decode_mime(message.get('subject'))
    brand, sender, sender_email = infer_brand(message.get('from', ''))
    text, html = extract_body_parts(message)
    links = extract_links(text, html)
    return ParsedEmail(
        brand=brand,
        sender=sender,
        sender_email=sender_email,
        subject=subject,
        sent_at=parse_email_date(message.get('date')),
        message_id=message.get('message-id', ''),
        text=text,
        html=html,
        links=links,
    )


def extract_deal_signals(parsed: ParsedEmail) -> dict:
    combined = f'{parsed.subject}\n{parsed.text}'
    lower = combined.lower()
    keyword_hits = {kw: lower.count(kw) for kw in PROMO_KEYWORDS}

    codes = list(dict.fromkeys(code.upper() for code in CODE_RE.findall(combined)))
    discounts = list(dict.fromkeys(PERCENT_DISCOUNT_RE.findall(combined) + DOLLAR_DISCOUNT_RE.findall(combined)))
    expiry_phrases = list(dict.fromkeys(EXPIRY_RE.findall(combined)))
    has_signal = any(keyword_hits.values()) or bool(codes or discounts or expiry_phrases)

    return {
        'has_signal': has_signal,
        'keyword_hits': keyword_hits,
        'promo_codes': codes[:10],
        'discount_phrases': discounts[:10],
        'expiry_phrases': expiry_phrases[:10],
    }


def email_hash_exists(content_hash: str) -> bool:
    for meta_path in RAW_EMAIL_TEXT_DIR.glob('*.meta.json'):
        try:
            meta = json.loads(meta_path.read_text(encoding='utf-8'))
        except (OSError, json.JSONDecodeError):
            continue
        if meta.get('content_hash') == content_hash:
            return True
    return False


def process_email(raw_bytes: bytes, source_id: str, dry_run: bool = False) -> dict:
    scraped_at = utc_iso()
    parsed = parse_email_message(raw_bytes)
    text_length = len(parsed.text)

    if text_length < 40:
        return {
            'brand': parsed.brand,
            'subject': parsed.subject,
            'source_id': source_id,
            'status': 'failed',
            'error': 'email_text_too_short',
            'text_length': text_length,
            'scraped_at': scraped_at,
        }

    content_hash = sha256_text(f'{parsed.sender_email}\n{parsed.subject}\n{parsed.text}')
    if dry_run:
        return {
            'brand': parsed.brand,
            'subject': parsed.subject,
            'source_id': source_id,
            'status': 'dry_run',
            'content_hash': content_hash,
            'text_length': text_length,
            'scraped_at': scraped_at,
        }

    if email_hash_exists(content_hash):
        return {
            'brand': parsed.brand,
            'subject': parsed.subject,
            'source_id': source_id,
            'status': 'skipped_duplicate_hash',
            'content_hash': content_hash,
            'text_length': text_length,
            'scraped_at': scraped_at,
        }

    RAW_EMAIL_DIR.mkdir(parents=True, exist_ok=True)
    RAW_EMAIL_TEXT_DIR.mkdir(parents=True, exist_ok=True)

    sent_stamp = (parsed.sent_at or scraped_at).replace(':', '').replace('-', '')
    sent_stamp = sent_stamp.split('.', 1)[0].replace('+0000', 'Z')
    base_name = f'{safe_slug(parsed.brand)}_{sent_stamp}_{content_hash[:10]}'

    raw_path = RAW_EMAIL_DIR / f'{base_name}.eml'
    text_path = RAW_EMAIL_TEXT_DIR / f'{base_name}.txt'
    meta_path = RAW_EMAIL_TEXT_DIR / f'{base_name}.meta.json'

    raw_path.write_bytes(raw_bytes)
    text_path.write_text(parsed.text, encoding='utf-8')

    signals = extract_deal_signals(parsed)
    meta = {
        'brand': parsed.brand,
        'sender': parsed.sender,
        'sender_email': parsed.sender_email,
        'subject': parsed.subject,
        'sent_at': parsed.sent_at,
        'message_id': parsed.message_id,
        'source_id': source_id,
        'source_type': 'email',
        'scraped_at': scraped_at,
        'content_hash': content_hash,
        'text_length': text_length,
        'link_count': len(parsed.links),
        'links': parsed.links,
        'raw_email_path': str(raw_path.relative_to(ROOT)),
        'text_path': str(text_path.relative_to(ROOT)),
        'deal_signal': signals['has_signal'],
    }
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding='utf-8')

    if signals['has_signal']:
        candidate = {
            'source': 'email',
            'brand': parsed.brand,
            'subject': parsed.subject,
            'sender_email': parsed.sender_email,
            'sent_at': parsed.sent_at,
            'source_id': source_id,
            'content_hash': content_hash,
            'keyword_hits': signals['keyword_hits'],
            'promo_codes': signals['promo_codes'],
            'discount_phrases': signals['discount_phrases'],
            'expiry_phrases': signals['expiry_phrases'],
            'links': parsed.links[:10],
            'text_path': str(text_path.relative_to(ROOT)),
        }
        append_jsonl(DEAL_CANDIDATES_FILE, candidate)

    return {
        **meta,
        'status': 'success',
        'error': None,
    }


def provider_default_host(user: str) -> str | None:
    domain = user.split('@')[-1].lower()
    if domain == 'gmail.com':
        return 'imap.gmail.com'
    if domain in {'outlook.com', 'hotmail.com', 'live.com', 'msn.com'}:
        return 'outlook.office365.com'
    if domain in {'yahoo.com', 'ymail.com'}:
        return 'imap.mail.yahoo.com'
    if domain in {'icloud.com', 'me.com', 'mac.com'}:
        return 'imap.mail.me.com'
    return None


def imap_since_date(days: int) -> str:
    since = datetime.now(timezone.utc) - timedelta(days=days)
    return since.strftime('%d-%b-%Y')


def quote_imap_value(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def iter_local_eml_files(path: Path, limit: int | None) -> Iterable[tuple[str, bytes]]:
    files = sorted(path.glob('*.eml'), key=lambda item: item.stat().st_mtime, reverse=True)
    if limit is not None:
        files = files[:limit]
    for eml_path in files:
        yield str(eml_path), eml_path.read_bytes()


def load_env_file(path: Path) -> None:
    for raw_line in path.read_text(encoding='utf-8').splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def iter_imap_messages(args) -> Iterable[tuple[str, bytes]]:
    user = args.email or os.getenv('EMAIL_ADDRESS') or os.getenv('EMAIL_IMAP_USER')
    password = os.getenv('EMAIL_APP_PASSWORD') or os.getenv('EMAIL_IMAP_PASSWORD')
    host = args.imap_host or os.getenv('EMAIL_IMAP_HOST') or (provider_default_host(user) if user else None)
    port = int(args.imap_port or os.getenv('EMAIL_IMAP_PORT') or 993)

    if not user or not password or not host:
        raise SystemExit(
            'Missing email settings. Set EMAIL_ADDRESS, EMAIL_APP_PASSWORD, and optionally EMAIL_IMAP_HOST.'
        )

    mailbox = args.mailbox or os.getenv('EMAIL_IMAP_MAILBOX') or 'INBOX'
    mail = imaplib.IMAP4_SSL(host, port)
    try:
        mail.login(user, password)
        status, _ = mail.select(mailbox, readonly=True)
        if status != 'OK':
            raise SystemExit(f'Could not open mailbox: {mailbox}')

        gmail_query = args.gmail_query or os.getenv('EMAIL_GMAIL_QUERY')
        raw_query = args.query or os.getenv('EMAIL_IMAP_QUERY')
        if gmail_query:
            status, data = mail.uid('search', None, 'X-GM-RAW', quote_imap_value(gmail_query))
        elif raw_query:
            status, data = mail.uid('search', None, raw_query)
        else:
            status, data = mail.uid('search', None, f'(SINCE {imap_since_date(args.since_days)})')

        if status != 'OK' or not data:
            return

        uids = data[0].split()
        if args.limit is not None:
            uids = uids[-args.limit:]

        for uid in reversed(uids):
            status, fetched = mail.uid('fetch', uid, '(RFC822)')
            if status != 'OK':
                continue
            for part in fetched:
                if isinstance(part, tuple) and part[1]:
                    yield f'imap:{mailbox}:{uid.decode("ascii", errors="replace")}', part[1]
                    break
    finally:
        try:
            mail.close()
        except imaplib.IMAP4.error:
            pass
        mail.logout()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Collect raw promotional emails from IMAP or local .eml files.')
    parser.add_argument('--limit', type=int, default=50, help='Maximum messages to process')
    parser.add_argument('--since-days', type=int, default=30, help='Default IMAP date window when no query is provided')
    parser.add_argument('--mailbox', type=str, default=None, help='IMAP mailbox name, default INBOX')
    parser.add_argument('--email', type=str, default=None, help='Email username, or set EMAIL_ADDRESS')
    parser.add_argument('--imap-host', type=str, default=None, help='IMAP host, inferred for common providers when possible')
    parser.add_argument('--imap-port', type=int, default=None, help='IMAP SSL port, default 993')
    parser.add_argument('--query', type=str, default=None, help='Raw IMAP search query, for example (SINCE 01-May-2026)')
    parser.add_argument('--gmail-query', type=str, default=None, help='Gmail X-GM-RAW search query')
    parser.add_argument('--eml-dir', type=Path, default=None, help='Process local .eml files instead of connecting to IMAP')
    parser.add_argument('--env-file', type=Path, default=None, help='Load email settings from a simple KEY=VALUE env file')
    parser.add_argument('--dry-run', action='store_true', help='Parse messages without saving raw email/text outputs')
    return parser


def main() -> None:
    args = build_parser().parse_args()

    if args.env_file:
        load_env_file(args.env_file)

    if args.eml_dir:
        messages = iter_local_eml_files(args.eml_dir, args.limit)
    else:
        messages = iter_imap_messages(args)

    processed = 0
    for source_id, raw_bytes in messages:
        record = process_email(raw_bytes, source_id=source_id, dry_run=args.dry_run)
        append_jsonl(LOG_FILE, record)
        processed += 1
        print(f"Processing {record.get('brand')}: {record.get('subject')}")
        print(f"  -> {record.get('status')} {record.get('error') or ''}")

    print(f'Processed {processed} email messages.')


if __name__ == '__main__':
    main()
