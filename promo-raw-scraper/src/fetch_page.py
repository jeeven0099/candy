from __future__ import annotations

import time
import warnings
from dataclasses import dataclass
from typing import Optional

import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


USER_AGENT = (
    'PromoRawScraper/0.1 (+private research; contact: owner) '
    'Mozilla/5.0 compatible'
)


@dataclass
class FetchResult:
    url: str
    ok: bool
    status_code: int | None
    html: str | None
    error: str | None
    final_url: str | None = None


def fetch_page(url: str, timeout: int = 20, max_retries: int = 2, backoff_seconds: float = 1.5) -> FetchResult:
    headers = {
        'User-Agent': USER_AGENT,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
    }
    last_error: Optional[str] = None
    for attempt in range(max_retries + 1):
        try:
            response = requests.get(url, headers=headers, timeout=timeout, allow_redirects=True, verify=False)
            # Many modern sites declare ISO-8859-1 but serve UTF-8 — override to avoid mojibake
            if response.encoding and response.encoding.upper() in ('ISO-8859-1', 'LATIN-1', 'LATIN1'):
                response.encoding = response.apparent_encoding or 'utf-8'
            if response.status_code != 200:
                return FetchResult(
                    url=url,
                    ok=False,
                    status_code=response.status_code,
                    html=None,
                    error=f'non_200_response:{response.status_code}',
                    final_url=response.url,
                )
            if not response.text.strip():
                return FetchResult(
                    url=url,
                    ok=False,
                    status_code=response.status_code,
                    html=None,
                    error='empty_response',
                    final_url=response.url,
                )
            return FetchResult(
                url=url,
                ok=True,
                status_code=response.status_code,
                html=response.text,
                error=None,
                final_url=response.url,
            )
        except requests.Timeout:
            last_error = 'timeout'
        except requests.RequestException as exc:
            last_error = f'request_error:{type(exc).__name__}:{exc}'
        if attempt < max_retries:
            time.sleep(backoff_seconds * (2 ** attempt))
    return FetchResult(url=url, ok=False, status_code=None, html=None, error=last_error, final_url=None)
