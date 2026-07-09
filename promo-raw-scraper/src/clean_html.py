from __future__ import annotations

import re
from bs4 import BeautifulSoup

DROP_TAGS = ['script', 'style', 'noscript', 'svg', 'canvas', 'iframe', 'nav', 'footer']

NOISE_PHRASES = [
    'accept cookies',
    'cookie policy',
    'privacy policy',
    'terms of use',
    'skip to main content',
]

# Legal boilerplate detection: long lines (>400 chars) that contain any legal signal word
# are almost certainly T&C clauses. Real deal content is rarely more than 150 chars per line.
_LEGAL_SIGNALS = re.compile(
    r'\b(redeemable|transferable|prohibited|liability|pursuant|void\b|indemnif|arbitration'
    r'|sublicense|warranties|governing\s+law|jurisdiction|severab)\b',
    re.IGNORECASE,
)
_LEGAL_LINE_MIN_LEN = 400


def extract_title(html: str) -> str | None:
    soup = BeautifulSoup(html, 'lxml')
    if soup.title and soup.title.string:
        return soup.title.string.strip()
    return None


def extract_og_image(html: str) -> str | None:
    """Return the og:image URL from meta tags, or None if not found."""
    soup = BeautifulSoup(html, 'lxml')
    for attr in ('og:image', 'twitter:image', 'twitter:image:src'):
        tag = soup.find('meta', property=attr) or soup.find('meta', attrs={'name': attr})
        if tag:
            url = tag.get('content', '').strip()
            if url.startswith('http'):
                return url
    return None


def clean_visible_text(html: str) -> str:
    soup = BeautifulSoup(html, 'lxml')
    for tag_name in DROP_TAGS:
        for tag in soup.find_all(tag_name):
            tag.decompose()

    # Inline image alt text so deal banners with descriptive alts aren't silently dropped.
    for img in soup.find_all('img', alt=True):
        alt = img.get('alt', '').strip()
        if len(alt) > 5:  # skip generic "logo", "img" etc.
            img.replace_with(alt)

    text = soup.get_text('\n')
    lines = []
    seen = set()
    for raw_line in text.splitlines():
        line = re.sub(r'\s+', ' ', raw_line).strip()
        if not line:
            continue
        lower = line.lower()
        if any(phrase in lower for phrase in NOISE_PHRASES) and len(line) < 120:
            continue
        if len(line) > _LEGAL_LINE_MIN_LEN and _LEGAL_SIGNALS.search(line):
            continue
        if line in seen:
            continue
        seen.add(line)
        lines.append(line)
    return '\n'.join(lines).strip()
