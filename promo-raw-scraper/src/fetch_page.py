from __future__ import annotations

import time
import warnings
from dataclasses import dataclass
from typing import Optional

import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

try:
    from curl_cffi import requests as _curl_requests
    _CURL_CFFI_AVAILABLE = True
except ImportError:
    import requests as _requests
    _CURL_CFFI_AVAILABLE = False

if not _CURL_CFFI_AVAILABLE:
    import requests


USER_AGENT = (
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/124.0.0.0 Safari/537.36'
)

# Realistic Chrome headers that WAFs expect alongside the TLS fingerprint
_CHROME_HEADERS = {
    'User-Agent': USER_AGENT,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept-Encoding': 'gzip, deflate, br',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'none',
    'Sec-Fetch-User': '?1',
    'Upgrade-Insecure-Requests': '1',
    'sec-ch-ua': '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"',
}


@dataclass
class FetchResult:
    url: str
    ok: bool
    status_code: int | None
    html: str | None
    error: str | None
    final_url: str | None = None


def fetch_page(url: str, timeout: int = 20, max_retries: int = 2, backoff_seconds: float = 1.5) -> FetchResult:
    last_error: Optional[str] = None
    for attempt in range(max_retries + 1):
        try:
            if _CURL_CFFI_AVAILABLE:
                response = _curl_requests.get(
                    url,
                    headers=_CHROME_HEADERS,
                    timeout=timeout,
                    allow_redirects=True,
                    verify=False,
                    impersonate="chrome124",
                )
            else:
                response = _requests.get(
                    url,
                    headers=_CHROME_HEADERS,
                    timeout=timeout,
                    allow_redirects=True,
                    verify=False,
                )

            # Many modern sites declare ISO-8859-1 but serve UTF-8 — override to avoid mojibake
            if hasattr(response, 'encoding') and response.encoding and \
                    response.encoding.upper() in ('ISO-8859-1', 'LATIN-1', 'LATIN1'):
                response.encoding = getattr(response, 'apparent_encoding', None) or 'utf-8'

            if response.status_code != 200:
                return FetchResult(
                    url=url,
                    ok=False,
                    status_code=response.status_code,
                    html=None,
                    error=f'non_200_response:{response.status_code}',
                    final_url=str(response.url),
                )
            if not response.text.strip():
                return FetchResult(
                    url=url,
                    ok=False,
                    status_code=response.status_code,
                    html=None,
                    error='empty_response',
                    final_url=str(response.url),
                )
            return FetchResult(
                url=url,
                ok=True,
                status_code=response.status_code,
                html=response.text,
                error=None,
                final_url=str(response.url),
            )
        except Exception as exc:
            name = type(exc).__name__
            msg = str(exc).lower()
            if 'timeout' in name.lower() or 'timeout' in msg:
                last_error = 'timeout'
            else:
                last_error = f'request_error:{name}:{exc}'
        if attempt < max_retries:
            time.sleep(backoff_seconds * (2 ** attempt))
    return FetchResult(url=url, ok=False, status_code=None, html=None, error=last_error, final_url=None)
