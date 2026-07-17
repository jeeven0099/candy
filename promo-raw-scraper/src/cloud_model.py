"""
cloud_model.py — Gemini and Groq backends for promo extraction.

Both classes reuse OllamaModel's prompt, validation, coercion, and synthesis
logic exactly. API keys are read from environment variables:
  GEMINI_API_KEY   — Google AI Studio (free tier: 15 RPM, 1500 req/day)
  GROQ_API_KEY     — Groq (free tier: ~30 RPM, 100K tokens/day)
"""
from __future__ import annotations

import json
import os
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
                dv = synthesized[0].discount_value or ""
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
    Free tier: ~30 RPM, 100K tokens/day.
    Recommended model: llama-3.3-70b-versatile
    Install: pip install groq
    """

    def __init__(
        self,
        model_name: str = "llama-3.3-70b-versatile",
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
        # Groq free tier: ~12K TPM. Prompt template overhead is ~2-3K tokens,
        # so cap text at 6000 chars to stay well under the limit.
        safe_text = text[:6000] if len(text) > 6000 else text
        prompt = helper._build_prompt(safe_text, brand, category, source_path)

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
        return _finish_parsing(helper, raw, brand, category, source_path, text)
