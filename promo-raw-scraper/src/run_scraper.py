from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

from clean_html import clean_visible_text, extract_og_image, extract_title
from fetch_page import fetch_page, FetchResult
from fetch_page_js import fetch_page_js, PlaywrightSession
from hash_content import hash_exists_for_brand, is_similar_to_last, sha256_text
from logger import append_jsonl
from source_loader import filter_sources, load_sources

ROOT = Path(__file__).resolve().parents[1]
RAW_HTML_DIR = ROOT / 'raw_html'
RAW_TEXT_DIR = ROOT / 'raw_text'
LOG_FILE = ROOT / 'logs' / 'scrape_results.jsonl'
SOURCES_FILE = ROOT / 'sources' / 'urls.json'


def utc_timestamp_for_filename() -> str:
    return datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')


def utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# Errors where requests fails but a real browser with stealth may succeed
_PLAYWRIGHT_RETRY_ERRORS = {
    "timeout",
    "non_200_response:403",  # actively blocked — stealth Playwright often gets through
    "non_200_response:406",
    "non_200_response:307",
}


def _try_playwright(url: str, session: PlaywrightSession | None = None) -> tuple | None:
    """Return (fetch, text, title) if Playwright succeeds, else None."""
    js_fetch = session.fetch(url) if session is not None else fetch_page_js(url)
    if not (js_fetch.ok and js_fetch.html):
        return None
    js_text = clean_visible_text(js_fetch.html)
    js_title = extract_title(js_fetch.html)
    if detect_bad_page(js_title, js_text, js_fetch.final_url) or len(js_text) < 100:
        return None
    return js_fetch, js_text, js_title


def prune_raw_files(keep: int = 3) -> int:
    """Delete old raw text/html/meta files, keeping the `keep` most recent per brand."""
    _TS_RE = re.compile(r'_\d{8}T\d{6}Z$')
    by_slug: dict[str, list[Path]] = defaultdict(list)
    for f in RAW_TEXT_DIR.glob('*.txt'):
        slug = _TS_RE.sub('', f.stem)
        by_slug[slug].append(f)

    deleted = 0
    for slug, files in by_slug.items():
        files.sort(key=lambda f: f.name)
        for txt in files[:-keep]:
            txt.unlink(missing_ok=True)
            txt.with_suffix('.meta.json').unlink(missing_ok=True)
            html = RAW_HTML_DIR / txt.with_suffix('.html').name
            html.unlink(missing_ok=True)
            deleted += 1
    return deleted


def detect_bad_page(title: str | None, text: str, final_url: str | None) -> str | None:
    title_lower = (title or '').lower()
    text_sample = text[:1200].lower()
    final_lower = (final_url or '').lower()

    title_markers = {
        'access_denied': ('access denied', 'access to this page has been denied'),
        'page_not_found': ('404 not found', 'page not found', 'page not available', 'oops page not found'),
        'site_offline': ('site offline',),
        'generic_error': ('something went wrong',),
        'bot_or_queue_page': ('routing to checkout',),
    }
    text_markers = {
        'access_denied': ('access to this page has been denied', 'access denied'),
        'bot_or_queue_page': ('enable javascript and cookies', 'verify you are human', 'request unsuccessful'),
        'generic_error': ('something went wrong',),
    }
    url_markers = {
        'page_not_found': ('/pagenotfound', '/page-not-found'),
        'bot_or_queue_page': ('/verify?', '/dduser-challenge', 'queue.'),
    }

    for reason, markers in title_markers.items():
        if any(marker in title_lower for marker in markers):
            return reason
    for reason, markers in text_markers.items():
        if any(marker in text_sample for marker in markers):
            return reason
    for reason, markers in url_markers.items():
        if any(marker in final_lower for marker in markers):
            return reason
    return None


def _fetch_one_url(
    url: str,
    *,
    requests_only: bool = False,
    pw_session: PlaywrightSession | None = None,
) -> tuple[str, str, str | None, str | None] | None:
    """
    Fetch a single URL and return (text, html, title, og_image) on success, else None.
    Handles Playwright fallback transparently.
    """
    fetch = fetch_page(url)
    fetch_method = 'requests'
    html: str = fetch.html or ''
    text = title = og_image = ''

    if fetch.ok and html:
        text  = clean_visible_text(html)
        title = extract_title(html)
        og_image = extract_og_image(html)

    # Try Playwright when requests blocks or returns too little content.
    # The JS-SPA check catches pages where the server returns a React/Next.js shell
    # (large HTML from JS bundles, almost no visible text) — e.g. Uniqlo, Zara.
    _is_js_spa = fetch.ok and len(html) > 500_000 and len(text) < 3_000
    needs_pw = (
        (not fetch.ok and fetch.error in _PLAYWRIGHT_RETRY_ERRORS)
        or (fetch.ok and len(text) < 100)
        or _is_js_spa
        or (fetch.ok and html and detect_bad_page(title, text, fetch.final_url))
    )
    if needs_pw:
        if requests_only:
            return None   # caller will queue for pass 2
        result = _try_playwright(url, session=pw_session)
        if result:
            fetch, text, title = result
            html = fetch.html
            og_image = extract_og_image(html)
            fetch_method = 'playwright'
            print(f'    -> Playwright got {len(text)} chars')
        else:
            return None

    if not text or len(text) < 100:
        return None
    if detect_bad_page(title, text, fetch.final_url):
        return None

    return text, html, title, og_image


def process_source(source, dry_run: bool = False, *,
                   requests_only: bool = False,
                   pw_session: PlaywrightSession | None = None) -> dict:
    scraped_at = utc_iso()
    stamp = utc_timestamp_for_filename()
    base_name = f'{source.slug}_{stamp}'

    if dry_run:
        return {'brand': source.brand, 'url': source.url,
                'status': 'dry_run', 'scraped_at': scraped_at}

    # ── Multi-URL brands: fetch each page, combine text separated by section headers ──
    if len(source.urls) > 1:
        sections: list[str] = []
        combined_html = ''
        og_image: str | None = None
        title: str | None = None
        failed_urls: list[str] = []

        for url in source.urls:
            result = _fetch_one_url(url, requests_only=requests_only, pw_session=pw_session)
            if result is None:
                if requests_only:
                    # At least one URL needs Playwright — queue the whole brand
                    return {'brand': source.brand, 'category': source.category,
                            'url': source.url, 'status': 'needs_playwright',
                            'scraped_at': scraped_at}
                failed_urls.append(url)
                continue
            url_text, url_html, url_title, url_og = result
            sections.append(f'=== {url} ===\n{url_text}')
            combined_html += url_html
            if not og_image:
                og_image = url_og
            if not title:
                title = url_title

        if not sections:
            return {'brand': source.brand, 'category': source.category,
                    'url': source.url, 'status': 'failed',
                    'scraped_at': scraped_at,
                    'error': f'all {len(source.urls)} URLs failed'}

        if failed_urls:
            print(f'    -> {len(failed_urls)}/{len(source.urls)} URLs failed: {failed_urls}')

        text = '\n\n'.join(sections)
        html = combined_html
        fetch_method = 'multi_url'

    else:
        # ── Single-URL brand: original logic ──────────────────────────────────
        fetch = fetch_page(source.url)
        fetch_method = 'requests'
        og_image: str | None = None

        if not fetch.ok and fetch.error in _PLAYWRIGHT_RETRY_ERRORS:
            if requests_only:
                return {'brand': source.brand, 'category': source.category,
                        'url': source.url, 'status': 'needs_playwright', 'scraped_at': scraped_at}
            print(f'    -> requests failed ({fetch.error}), trying Playwright fallback...')
            result = _try_playwright(source.url, session=pw_session)
            if result:
                fetch, text, title = result
                html = fetch.html
                og_image = extract_og_image(html)
                fetch_method = 'playwright'
                print(f'    -> Playwright got {len(text)} chars')
            else:
                print(f'    -> Playwright also failed')
                return {'brand': source.brand, 'category': source.category,
                        'url': source.url, 'status': 'failed',
                        'http_status': fetch.status_code, 'scraped_at': scraped_at,
                        'error': fetch.error, 'final_url': fetch.final_url}

        if not fetch.ok or not fetch.html:
            return {'brand': source.brand, 'category': source.category,
                    'url': source.url, 'status': 'failed',
                    'http_status': fetch.status_code, 'scraped_at': scraped_at,
                    'error': fetch.error, 'final_url': fetch.final_url}

        if fetch_method == 'requests':
            html = fetch.html
            text = clean_visible_text(html)
            title = extract_title(html)
            og_image = extract_og_image(html)

        bad_page_reason = detect_bad_page(title, text, fetch.final_url)
        if bad_page_reason:
            if requests_only and fetch_method == 'requests':
                return {'brand': source.brand, 'category': source.category,
                        'url': source.url, 'status': 'needs_playwright', 'scraped_at': scraped_at}
            return {'brand': source.brand, 'category': source.category,
                    'url': source.url, 'status': 'failed',
                    'http_status': fetch.status_code, 'scraped_at': scraped_at,
                    'error': f'blocked_or_error_page:{bad_page_reason}',
                    'text_length': len(text), 'title': title, 'final_url': fetch.final_url}

        _is_js_spa = len(html) > 500_000 and len(text) < 3_000
        if len(text) < 100 or _is_js_spa:
            if requests_only:
                return {'brand': source.brand, 'category': source.category,
                        'url': source.url, 'status': 'needs_playwright', 'scraped_at': scraped_at}
            reason = 'JS SPA detected' if _is_js_spa else f'{len(text)} chars'
            print(f'    -> requests got thin text ({reason}), trying Playwright fallback...')
            result = _try_playwright(source.url, session=pw_session)
            if result:
                fetch, text, title = result
                html = fetch.html
                og_image = extract_og_image(html)
                fetch_method = 'playwright'
                print(f'    -> Playwright got {len(text)} chars')
            else:
                print(f'    -> Playwright also failed')
                return {'brand': source.brand, 'category': source.category,
                        'url': source.url, 'status': 'failed',
                        'http_status': fetch.status_code, 'scraped_at': scraped_at,
                        'error': 'clean_text_too_short', 'text_length': len(text),
                        'final_url': fetch.final_url}

    # ── Common write path ─────────────────────────────────────────────────────
    content_hash = sha256_text(text)
    if hash_exists_for_brand(source.slug, content_hash, RAW_TEXT_DIR):
        existing = sorted(RAW_TEXT_DIR.glob(f'{source.slug}_*.txt'))
        if existing:
            existing[-1].touch()
        return {'brand': source.brand, 'category': source.category,
                'url': source.url, 'status': 'skipped_duplicate_hash',
                'content_hash': content_hash, 'scraped_at': scraped_at,
                'text_length': len(text), 'html_length': len(html)}

    similar, ratio = is_similar_to_last(source.slug, text, RAW_TEXT_DIR)
    if similar:
        return {'brand': source.brand, 'category': source.category,
                'url': source.url, 'status': 'skipped_similar',
                'content_hash': content_hash, 'similarity': ratio,
                'scraped_at': scraped_at, 'text_length': len(text), 'html_length': len(html)}

    RAW_HTML_DIR.mkdir(parents=True, exist_ok=True)
    RAW_TEXT_DIR.mkdir(parents=True, exist_ok=True)

    html_path = RAW_HTML_DIR / f'{base_name}.html'
    text_path = RAW_TEXT_DIR / f'{base_name}.txt'
    meta_path = RAW_TEXT_DIR / f'{base_name}.meta.json'

    html_path.write_text(html, encoding='utf-8')
    text_path.write_text(text, encoding='utf-8')

    meta = {
        'brand':       source.brand,
        'category':    source.category,
        'url':         source.url,
        'urls':        list(source.urls),
        'source_type': source.source_type,
        'scraped_at':  scraped_at,
        'fetch_method': fetch_method,
        'content_hash': content_hash,
        'title':       title,
        'og_image':    og_image,
        'text_length': len(text),
        'html_length': len(html),
        'html_path':   str(html_path.relative_to(ROOT)),
        'text_path':   str(text_path.relative_to(ROOT)),
    }
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding='utf-8')

    return {**meta, 'status': 'success', 'error': None}


def main() -> None:
    parser = argparse.ArgumentParser(description='Scrape raw promotion/rewards pages.')
    parser.add_argument('--brand', type=str, default=None, help='Filter sources by brand substring')
    parser.add_argument('--category', type=str, default=None, help='Filter sources by category (e.g. travel, tech, home_goods)')
    parser.add_argument('--limit', type=int, default=None, help='Limit number of sources')
    parser.add_argument('--dry-run', action='store_true', help='Print what would be fetched without fetching')
    parser.add_argument('--keep-raw', type=int, default=1, help='Raw files to keep per brand (default: 1)')
    args = parser.parse_args()

    sources = load_sources(SOURCES_FILE)
    selected = filter_sources(sources, brand=args.brand, category=args.category, limit=args.limit, allowed_only=True)

    print(f'Loaded {len(sources)} sources; selected {len(selected)} allowed sources.')

    records: list[dict] = []

    def _record(r: dict) -> None:
        records.append(r)
        append_jsonl(LOG_FILE, r)
        print(f"  -> {r.get('status')} {r.get('error') or ''}")

    # Pass 1: try all brands with requests only; collect those that need Playwright
    needs_playwright: list = []
    for source in selected:
        print(f'Processing {source.brand}: {source.url}')
        record = process_source(source, dry_run=args.dry_run, requests_only=True)
        if record.get('status') == 'needs_playwright':
            needs_playwright.append(source)
            print(f'  -> queued for Playwright')
        else:
            _record(record)

    # Pass 2: process all Playwright-needed brands with a single shared browser
    if needs_playwright:
        print(f'\nStarting shared Playwright browser for {len(needs_playwright)} brand(s)...')
        try:
            with PlaywrightSession() as session:
                for source in needs_playwright:
                    print(f'Processing {source.brand} [Playwright]: {source.url}')
                    _record(process_source(source, dry_run=args.dry_run, pw_session=session))
        except Exception as exc:
            print(f'  [WARN] Shared browser failed ({exc}), falling back to per-brand Playwright')
            for source in needs_playwright:
                print(f'Processing {source.brand}: {source.url}')
                _record(process_source(source, dry_run=args.dry_run))

    # Prune old raw files, keeping only the most recent per brand
    deleted = prune_raw_files(keep=args.keep_raw)
    if deleted:
        print(f'\nPruned {deleted} old raw file(s) (kept {args.keep_raw} per brand)')

    # Scrape summary
    changed       = [r['brand'] for r in records if r.get('status') == 'success']
    skipped_exact = sum(1 for r in records if r.get('status') == 'skipped_duplicate_hash')
    fuzzy_records = [r for r in records if r.get('status') == 'skipped_similar']
    skipped_fuzzy = len(fuzzy_records)
    skipped       = skipped_exact + skipped_fuzzy
    failed        = [r['brand'] for r in records if r.get('status', '').startswith('failed')]

    print(f'\n{"="*60}')
    print(f'  Scrape summary')
    print(f'{"="*60}')
    print(f'  Changed  : {len(changed)} brand(s) -> will be re-parsed by qwen')
    print(f'  Unchanged: {skipped} brand(s) -> will be skipped'
          + (f' ({skipped_fuzzy} fuzzy-matched)' if skipped_fuzzy else ''))
    print(f'  Failed   : {len(failed)} brand(s) -> no data')
    if changed:
        print(f'\n  Brands with new content:')
        for b in sorted(changed):
            print(f'    + {b}')
    if fuzzy_records:
        print(f'\n  Fuzzy-skipped brands (similarity >= threshold):')
        for r in sorted(fuzzy_records, key=lambda r: r['brand']):
            print(f'    ~ {r["brand"]} (similarity {r["similarity"]:.4f})')
    if failed:
        print(f'\n  Failed brands:')
        for b in sorted(failed):
            print(f'    x {b}')
    print(f'{"="*60}\n')


if __name__ == '__main__':
    main()
