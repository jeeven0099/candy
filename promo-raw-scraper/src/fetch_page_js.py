from __future__ import annotations

from fetch_page import FetchResult


_CHROMIUM_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)

try:
    from playwright_stealth import stealth_sync as _stealth
except ImportError:
    _stealth = None


def _apply_stealth(page) -> None:
    if _stealth is not None:
        _stealth(page)


class PlaywrightSession:
    """
    Reusable Playwright browser session.  Open once, fetch many URLs, close once.
    Use as a context manager:

        with PlaywrightSession() as session:
            result = session.fetch(url)
    """

    def __init__(self, timeout_ms: int = 30_000) -> None:
        self.timeout_ms = timeout_ms
        self._pw_ctx = None
        self._browser = None

    def __enter__(self) -> "PlaywrightSession":
        from playwright.sync_api import sync_playwright
        self._pw_ctx = sync_playwright()
        pw = self._pw_ctx.__enter__()
        self._browser = pw.chromium.launch(channel="chrome", headless=True)
        return self

    def __exit__(self, *args) -> None:
        if self._browser:
            self._browser.close()
            self._browser = None
        if self._pw_ctx:
            self._pw_ctx.__exit__(*args)
            self._pw_ctx = None

    def fetch(self, url: str) -> FetchResult:
        from playwright.sync_api import TimeoutError as PWTimeout
        try:
            context = self._browser.new_context(
                user_agent=_CHROMIUM_UA,
                viewport={"width": 1280, "height": 800},
            )
            page = context.new_page()
            _apply_stealth(page)
            response = page.goto(url, wait_until="domcontentloaded", timeout=self.timeout_ms)
            try:
                page.wait_for_load_state("networkidle", timeout=10_000)
            except PWTimeout:
                pass
            status = response.status if response else 200
            final_url = page.url
            html = page.content()
            context.close()
            if status not in (200, 0):
                return FetchResult(url=url, ok=False, status_code=status, html=None,
                                   error=f"non_200_response:{status}", final_url=final_url)
            return FetchResult(url=url, ok=True, status_code=status, html=html,
                               error=None, final_url=final_url)
        except PWTimeout:
            return FetchResult(url=url, ok=False, status_code=None, html=None,
                               error="timeout", final_url=None)
        except Exception as exc:
            return FetchResult(url=url, ok=False, status_code=None, html=None,
                               error=f"playwright_error:{type(exc).__name__}:{exc}",
                               final_url=None)


def fetch_page_js(url: str, timeout_ms: int = 30_000) -> FetchResult:
    """
    Fetch a URL using a headless Chromium browser via Playwright.
    Waits for JavaScript to finish rendering before returning the HTML.
    Falls back gracefully if Playwright is not installed.
    """
    try:
        from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout
    except ImportError:
        return FetchResult(
            url=url, ok=False, status_code=None, html=None,
            error="playwright_not_installed", final_url=None,
        )

    try:
        with sync_playwright() as pw:
            # Use system Chrome to avoid downloading a separate Chromium binary
            browser = pw.chromium.launch(channel="chrome", headless=True)
            context = browser.new_context(
                user_agent=_CHROMIUM_UA,
                viewport={"width": 1280, "height": 800},
                java_script_enabled=True,
            )
            page = context.new_page()
            _apply_stealth(page)

            response = page.goto(url, wait_until="domcontentloaded", timeout=timeout_ms)

            # Wait for dynamic content — networkidle can stall on polling pages,
            # so cap it and proceed regardless.
            try:
                page.wait_for_load_state("networkidle", timeout=10_000)
            except PWTimeout:
                pass

            status = response.status if response else 200
            final_url = page.url
            html = page.content()
            browser.close()

        if status not in (200, 0):
            return FetchResult(
                url=url, ok=False, status_code=status, html=None,
                error=f"non_200_response:{status}", final_url=final_url,
            )

        return FetchResult(
            url=url, ok=True, status_code=status, html=html,
            error=None, final_url=final_url,
        )

    except PWTimeout:
        return FetchResult(url=url, ok=False, status_code=None, html=None,
                           error="timeout", final_url=None)
    except Exception as exc:
        return FetchResult(url=url, ok=False, status_code=None, html=None,
                           error=f"playwright_error:{type(exc).__name__}:{exc}",
                           final_url=None)
