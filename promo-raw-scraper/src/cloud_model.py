"""
cloud_model.py — Gemini and Groq backends for promo extraction.

Both classes reuse OllamaModel's prompt, validation, coercion, and synthesis
logic exactly. API keys are read from environment variables:
  GEMINI_API_KEY   — Google AI Studio (free tier: 15 RPM, 1500 req/day)
  GROQ_API_KEY     — Groq Developer plan: 250K TPM for openai/gpt-oss-120b
"""
from __future__ import annotations

import json
import os
import time
from typing import List, Optional

from pydantic import ValidationError

from local_model_interface import LocalModelInterface
from models import Promotion
from ollama_model import OllamaModel


def _make_helper() -> OllamaModel:
    """Dummy OllamaModel used only for prompt building and validation helpers."""
    return OllamaModel(model_name="cloud", host="", timeout=0)


def _finish_parsing(
    helper: OllamaModel,
    raw: str,
    brand: str,
    category: Optional[str],
    source_path: str,
    text: str,
) -> List[Promotion]:
    """
    Shared post-processing for cloud model responses.
    Mirrors the logic in OllamaModel.parse_text() after the HTTP call.
    """
    try:
        items = helper._extract_promotions_list(raw)
    except ValueError as exc:
        print(f"[WARN] {brand}: cloud model response unparseable — {exc!s:.200}")
        items = []

    promotions: List[Promotion] = []
    errors: List[str] = []

    for i, item in enumerate(items):
        item = helper._coerce_data(item)
        item["brand"] = brand
        item["source_path"] = source_path
        if category and not item.get("category"):
            item["category"] = category
        item = helper._postprocess_data(item, brand)
        try:
            promotions.append(Promotion(**item))
        except ValidationError as exc:
            errors.append(
                f"Item {i + 1} failed validation: {exc}\n"
                f"Raw item: {json.dumps(item)[:400]}"
            )

    if errors and not promotions:
        print(
            f"[WARN] {brand}: all {len(errors)} cloud item(s) failed Pydantic validation "
            f"(first error: {errors[0][:200]})"
        )

    # Deduplicate by promotion_title — keep first occurrence
    seen_titles: set[str] = set()
    unique: List[Promotion] = []
    for p in promotions:
        key = (p.promotion_title or "").strip().lower().rstrip(".!?,;")
        if key and key not in seen_titles:
            seen_titles.add(key)
            unique.append(p)
        elif not key:
            unique.append(p)

    # Collapse product-grid deals when LLM returned multiple individual sale items
    if len(unique) >= 2:
        grid_deals = [
            p for p in unique
            if p.promotion_type in ("sale",)
            and p.discount_type in ("percentage_off", "sale_price", "amount_off")
            and not p.requires_membership
            and not p.requires_app
            and not p.promo_code
        ]
        if len(grid_deals) >= 2 and len(grid_deals) / len(unique) >= 0.8:
            synthesized = helper._synthesize_sale_from_price_grid(text, brand, category, source_path)
            if synthesized:
                # Merge keywords from all collapsed LLM deals into the synthesized card
                card = synthesized[0]
                merged_explicit: list[str] = list(card.product_keywords_explicit or [])
                merged_contextual: list[str] = list(card.product_keywords_contextual or [])
                merged_examples: list[str] = list(card.matched_product_examples or [])
                seen_ex = {e.upper() for e in merged_examples}
                for deal in grid_deals:
                    for kw in (deal.product_keywords_explicit or []):
                        if kw and kw not in merged_explicit:
                            merged_explicit.append(kw)
                    for kw in (deal.product_keywords_contextual or []):
                        if kw and kw not in merged_contextual:
                            merged_contextual.append(kw)
                    for ex in (deal.matched_product_examples or []):
                        if ex and ex.upper() not in seen_ex:
                            merged_examples.append(ex)
                            seen_ex.add(ex.upper())
                card.product_keywords_explicit  = merged_explicit[:30]
                card.product_keywords_contextual = merged_contextual[:40]
                card.matched_product_examples    = merged_examples[:15]
                dv = card.discount_value or ""
                print(
                    f"[SYNTH] {brand}: cloud model returned {len(grid_deals)} product-grid deals — "
                    f"collapsed into one synthesized card ({dv})"
                )
                return synthesized

    # Always try the synthesizer — even when the LLM found deals it may have missed
    # additional price-grid discounts. Added alongside LLM deals; dedup handles overlap.
    synthesized = helper._synthesize_sale_from_price_grid(text, brand, category, source_path)
    if synthesized:
        dv = synthesized[0].discount_value or ""
        if unique:
            print(f"[SYNTH] {brand}: supplementing {len(unique)} LLM deal(s) with price-grid card ({dv})")
            unique.extend(synthesized)
        else:
            print(f"[SYNTH] {brand}: cloud model found 0 deals — synthesized from price grid ({dv})")
            return synthesized

    return unique


class OpenRouterModel(LocalModelInterface):
    """
    OpenRouter backend — unified API for 100+ models including openai/gpt-4o-mini,
    openai/gpt-oss-120b, meta-llama/llama-3.3-70b-instruct, etc.
    Uses the OpenAI-compatible endpoint at https://openrouter.ai/api/v1.
    API key: set OPENROUTER_API_KEY in .env
    Install: pip install openai
    """

    def __init__(
        self,
        model_name: str = "openai/gpt-4o-mini",
        api_key: Optional[str] = None,
        timeout: int = 120,
    ) -> None:
        self.model_name = model_name
        self.api_key    = api_key or os.environ.get("OPENROUTER_API_KEY", "")
        self.timeout    = timeout
        self._last_input_tokens:  int = 0
        self._last_output_tokens: int = 0
        if not self.api_key:
            raise ValueError(
                "OPENROUTER_API_KEY not set. "
                "Export it or paste it into promo-raw-scraper/.env"
            )

    def parse_text(
        self,
        text: str,
        brand: str,
        category: Optional[str],
        source_path: str,
    ) -> List[Promotion]:
        try:
            from openai import OpenAI
        except ImportError:
            raise ImportError("openai not installed. Run: pip install openai")

        helper = _make_helper()
        prompt = helper._build_prompt(text, brand, category, source_path)

        import httpx
        print(f"  [OpenRouter] {brand}: calling {self.model_name}...", flush=True)
        http_client = httpx.Client(
            verify=False,
            timeout=httpx.Timeout(connect=15.0, read=self.timeout, write=30.0, pool=5.0),
        )
        client = OpenAI(
            api_key=self.api_key,
            base_url="https://openrouter.ai/api/v1",
            http_client=http_client,
            default_headers={
                "HTTP-Referer": "https://github.com/jeeven0099/promo-scraper",
                "X-Title": "promo-raw-scraper",
            },
        )
        response = client.chat.completions.create(
            model=self.model_name,
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
            max_tokens=8192,
        )
        raw = response.choices[0].message.content or ""

        if response.usage:
            self._last_input_tokens  = response.usage.prompt_tokens     or 0
            self._last_output_tokens = response.usage.completion_tokens  or 0
        else:
            self._last_input_tokens  = 0
            self._last_output_tokens = 0

        # When OPENROUTER_TOKEN_LOG is set (e.g. by run_benchmark.py), append usage to it
        token_log = os.environ.get("OPENROUTER_TOKEN_LOG", "")
        if token_log and (self._last_input_tokens or self._last_output_tokens):
            try:
                with open(token_log, "a", encoding="utf-8") as lf:
                    import json as _json
                    lf.write(_json.dumps({
                        "brand": brand,
                        "input_tokens":  self._last_input_tokens,
                        "output_tokens": self._last_output_tokens,
                    }) + "\n")
            except Exception:
                pass

        return _finish_parsing(helper, raw, brand, category, source_path, text)


class GeminiModel(LocalModelInterface):
    """
    Gemini backend via Google AI Studio.
    Free tier: high RPM, generous daily allowance on Flash tier.
    Recommended model: gemini-2.5-flash
    Install: pip install google-genai
    """

    def __init__(
        self,
        model_name: str = "gemini-2.5-flash",
        api_key: Optional[str] = None,
        timeout: int = 120,
    ) -> None:
        self.model_name = model_name
        self.api_key    = api_key or os.environ.get("GEMINI_API_KEY", "")
        self.timeout    = timeout
        if not self.api_key:
            raise ValueError(
                "GEMINI_API_KEY not set. "
                "Export it or pass api_key= to GeminiModel()."
            )

    def parse_text(
        self,
        text: str,
        brand: str,
        category: Optional[str],
        source_path: str,
    ) -> List[Promotion]:
        try:
            import httpx
            from google import genai
            from google.genai import types as genai_types
            from google.genai._api_client import HttpOptions
        except ImportError:
            raise ImportError(
                "google-genai not installed. "
                "Run: pip install google-genai"
            )

        helper = _make_helper()
        prompt = helper._build_prompt(text, brand, category, source_path)

        http_options = HttpOptions(httpxClient=httpx.Client(verify=False))
        client = genai.Client(api_key=self.api_key, http_options=http_options)
        response = client.models.generate_content(
            model=self.model_name,
            contents=prompt,
            config=genai_types.GenerateContentConfig(
                response_mime_type="application/json",
                max_output_tokens=8192,
            ),
        )
        raw = response.text or ""
        return _finish_parsing(helper, raw, brand, category, source_path, text)


class GroqModel(LocalModelInterface):
    """
    Groq backend — fast inference on open-weight models.
    Developer plan: 250K TPM for openai/gpt-oss-120b.
    Install: pip install groq
    """

    # Developer plan TPM limit for openai/gpt-oss-120b
    _TPM_LIMIT = 250_000
    _last_call_time: float = 0.0
    _tokens_this_minute: int = 0
    _minute_start: float = 0.0

    def __init__(
        self,
        model_name: str = "openai/gpt-oss-120b",
        api_key: Optional[str] = None,
        timeout: int = 120,
    ) -> None:
        self.model_name = model_name
        self.api_key    = api_key or os.environ.get("GROQ_API_KEY", "")
        self.timeout    = timeout
        if not self.api_key:
            raise ValueError(
                "GROQ_API_KEY not set. "
                "Export it or pass api_key= to GroqModel()."
            )

    def _rate_limit(self, estimated_tokens: int) -> None:
        """Pause if needed to stay under 250K TPM."""
        now = time.monotonic()
        if now - GroqModel._minute_start >= 60:
            GroqModel._minute_start = now
            GroqModel._tokens_this_minute = 0

        if GroqModel._tokens_this_minute + estimated_tokens > self._TPM_LIMIT:
            wait = 60 - (now - GroqModel._minute_start) + 1
            print(f"  [rate-limit] TPM near limit — waiting {wait:.0f}s")
            time.sleep(max(0, wait))
            GroqModel._minute_start = time.monotonic()
            GroqModel._tokens_this_minute = 0

        GroqModel._tokens_this_minute += estimated_tokens

    def parse_text(
        self,
        text: str,
        brand: str,
        category: Optional[str],
        source_path: str,
    ) -> List[Promotion]:
        try:
            from groq import Groq
        except ImportError:
            raise ImportError(
                "groq not installed. Run: pip install groq"
            )

        import httpx

        helper = _make_helper()
        prompt = helper._build_prompt(text, brand, category, source_path)

        # Estimate tokens before calling (4 chars ≈ 1 token)
        estimated_tokens = len(prompt) // 4 + 8192
        self._rate_limit(estimated_tokens)

        http_client = httpx.Client(verify=False)
        client = Groq(api_key=self.api_key, http_client=http_client)
        response = client.chat.completions.create(
            model=self.model_name,
            messages=[{"role": "user", "content": prompt}],
            response_format={"type": "json_object"},
            max_tokens=8192,
            timeout=self.timeout,
        )
        raw = response.choices[0].message.content or ""

        # Update token count with actuals if available
        if response.usage:
            actual = (response.usage.prompt_tokens or 0) + (response.usage.completion_tokens or 0)
            GroqModel._tokens_this_minute += actual - estimated_tokens

        return _finish_parsing(helper, raw, brand, category, source_path, text)
