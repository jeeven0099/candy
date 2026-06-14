from __future__ import annotations

import json
import re
from typing import Any, List, Optional

import requests
from pydantic import ValidationError

from local_model_interface import LocalModelInterface
from models import Promotion


_FIELD_SCHEMA = """
Return a JSON object with a "promotions" array. Each item in the array has EXACTLY these fields:

{
  "promotions": [
    {
  "brand": "string",
  "category": "string or null  (e.g. food, coffee, retail)",
  "promotion_title": "string or null",
  "short_summary": "string or null  (1-2 sentences)",
  "promotion_type": "one of: reward | app_offer | sale | coupon | birthday_reward | membership_benefit | unknown",
  "discount_type": "one of: percentage_off | amount_off | free_item | free_shipping | points | sale_price | unknown",
  "discount_value": "string or null  (e.g. '50%', '$5', 'free')",
  "requires_membership": "boolean",
  "membership_name": "string or null",
  "membership_cost": "one of: free | unknown  — or null if requires_membership is false",
  "requires_app": "boolean",
  "requires_account_login": "boolean",
  "new_user_only": "boolean",
  "birthday_related": "boolean",
  "start_date": "string or null  (ISO date: 2025-01-01)",
  "end_date": "string or null  (ISO date)",
  "valid_days": "array of strings  (e.g. ['Monday', 'Tuesday'])",
  "time_start": "string or null  (24h: '09:00')",
  "time_end": "string or null  (24h: '21:00')",
  "timezone": "string  (IANA timezone of the brand's primary market, e.g. 'America/New_York', 'America/Chicago', 'America/Los_Angeles'. Use the brand's headquarters or most common store timezone. Default to 'America/New_York' only if unknown.)",
  "redemption_method": "one of: in_app | in_store | online | show_code | scan_barcode | unknown",
  "redemption_steps": "array of step strings",
  "promo_code": "string or null  (exact promo/coupon code if explicitly shown, e.g. 'SUMMER20', 'APP10'. Only include if the code itself appears in the text — do not guess.)",
  "terms_text": "string or null  (relevant snippet from source text)",
  "minimum_spend": "string or null  (e.g. '$10')",
  "purchase_required": "boolean",
  "deal_scope": "one of: brand_level | location_specific | online_only | unknown",
  "friction_level": "one of: low | medium | high | unknown",
  "friction_reasons": "array of strings",
  "confidence_score": "float 0.0–1.0",
  "source_type": "one of: web_page | email | unknown",
  "source_path": "string",
  "extraction_status": "one of: success | no_offer_found | failed",
  "notes": "array of strings (observations, caveats, ambiguities)"
    }
  ]
}
"""

_MAX_TEXT_CHARS = 6000

_VALID_PROMOTION_TYPES = {"reward", "app_offer", "sale", "coupon", "birthday_reward", "membership_benefit", "unknown"}
_VALID_DISCOUNT_TYPES = {"percentage_off", "amount_off", "free_item", "free_shipping", "points", "sale_price", "unknown"}
_VALID_REDEMPTION_METHODS = {"in_app", "in_store", "online", "show_code", "scan_barcode", "unknown"}
_VALID_DEAL_SCOPES = {"brand_level", "location_specific", "online_only", "unknown"}
_VALID_FRICTION_LEVELS = {"low", "medium", "high", "unknown"}
_VALID_EXTRACTION_STATUSES = {"success", "no_offer_found", "failed"}
_VALID_SOURCE_TYPES = {"web_page", "email", "unknown"}
_VALID_MEMBERSHIP_COSTS = {"free", "unknown"}
_ARRAY_FIELDS = {"valid_days", "redemption_steps", "friction_reasons", "notes"}
_BOOL_FIELDS = {
    "requires_membership", "requires_app", "requires_account_login",
    "new_user_only", "birthday_related", "purchase_required",
}


class OllamaModel(LocalModelInterface):
    """
    LLM-backed parser using a local Ollama instance.

    Sends raw promo text to an Ollama model and parses the JSON response
    into a validated Promotion object. Requires `ollama serve` to be running.
    """

    def __init__(
        self,
        model_name: str = "llama3.1:8b",
        host: str = "http://localhost:11434",
        timeout: int = 600,
    ) -> None:
        self.model_name = model_name
        self.host = host.rstrip("/")
        self.timeout = timeout

    def parse_text(
        self,
        text: str,
        brand: str,
        category: Optional[str],
        source_path: str,
    ) -> List[Promotion]:
        prompt = self._build_prompt(text, brand, category, source_path)
        raw_response = self._call_ollama(prompt)
        items = self._extract_promotions_list(raw_response)

        promotions: List[Promotion] = []
        errors: List[str] = []

        for i, item in enumerate(items):
            item = self._coerce_data(item)

            # Enforce fields the caller owns — never let the LLM override them
            item["brand"] = brand
            item["source_path"] = source_path
            if category and not item.get("category"):
                item["category"] = category

            item = self._postprocess_data(item, brand)

            try:
                promotions.append(Promotion(**item))
            except ValidationError as exc:
                errors.append(
                    f"Item {i + 1} failed validation: {exc}\n"
                    f"Raw item: {json.dumps(item)[:400]}"
                )

        if errors and not promotions:
            raise ValueError(
                f"All {len(errors)} promotion(s) from Ollama failed Pydantic validation.\n"
                + "\n".join(errors)
                + f"\nRaw LLM response (first 800 chars): {raw_response[:800]}"
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

        return unique

    # ------------------------------------------------------------------ #
    # Internals                                                            #
    # ------------------------------------------------------------------ #

    def _coerce_data(self, data: dict) -> dict:
        """
        Fix common LLM schema deviations before Pydantic validation.
        Prevents failures caused by minor formatting issues in the LLM output.
        """
        # Ensure array fields are always lists, with null items filtered out
        for field in _ARRAY_FIELDS:
            val = data.get(field)
            if val is None:
                data[field] = []
            elif isinstance(val, str):
                data[field] = [val] if val.strip() else []
            elif isinstance(val, list):
                data[field] = [item for item in val if item is not None]

        # Coerce boolean fields — handle None and string representations
        for field in _BOOL_FIELDS:
            val = data.get(field)
            if val is None:
                data[field] = False
            elif isinstance(val, str):
                data[field] = val.strip().lower() in {"true", "yes", "1"}

        # Clamp confidence_score to [0.0, 1.0]
        score = data.get("confidence_score")
        if score is not None:
            try:
                data["confidence_score"] = max(0.0, min(1.0, float(score)))
            except (TypeError, ValueError):
                data["confidence_score"] = 0.0

        # Replace invalid enum values with their fallback
        _enum_fallbacks = {
            "promotion_type": ("unknown", _VALID_PROMOTION_TYPES),
            "discount_type": ("unknown", _VALID_DISCOUNT_TYPES),
            "redemption_method": ("unknown", _VALID_REDEMPTION_METHODS),
            "deal_scope": ("unknown", _VALID_DEAL_SCOPES),
            "friction_level": ("unknown", _VALID_FRICTION_LEVELS),
            "extraction_status": ("success", _VALID_EXTRACTION_STATUSES),
            "source_type": ("web_page", _VALID_SOURCE_TYPES),
        }
        for field, (fallback, valid_set) in _enum_fallbacks.items():
            val = data.get(field)
            if val is None:
                data[field] = fallback
            elif str(val).lower() not in valid_set:
                data[field] = fallback
            else:
                data[field] = str(val).lower()

        # membership_cost: null when no membership, otherwise "free" or "unknown"
        if not data.get("requires_membership"):
            data["membership_cost"] = None
        else:
            mc = data.get("membership_cost")
            if mc is None or str(mc).lower() not in _VALID_MEMBERSHIP_COSTS:
                data["membership_cost"] = "unknown"
            else:
                data["membership_cost"] = str(mc).lower()

        # timezone: non-optional field — default if LLM returned null or empty
        if not data.get("timezone"):
            data["timezone"] = "America/Chicago"

        # discount_value / promo_code: treat the string "null" as actual null
        for _field in ("discount_value", "promo_code"):
            val = data.get(_field)
            if isinstance(val, str) and val.strip().lower() in {"null", "none", "n/a", ""}:
                data[_field] = None

        return data

    def _postprocess_data(self, data: dict, brand: str) -> dict:
        """
        Deterministic fixes applied after coercion and LLM ownership enforcement,
        before Pydantic validation.
        """
        fixed = False

        # Rule 1: missing or generic title — generate from short_summary
        title = data.get("promotion_title") or ""
        if not title or any(bad in title.lower() for bad in ("unknown", "n/a", "none")):
            summary = data.get("short_summary", "")
            if summary and "unknown" not in summary.lower():
                generated = summary.split(".")[0].strip()
                data["promotion_title"] = generated[:80] if len(generated) > 80 else generated
            elif data.get("promotion_type") == "reward":
                data["promotion_title"] = f"{brand} Rewards Program"
            else:
                data["promotion_title"] = f"{brand} Promotion"
            fixed = True
        elif len(title) > 80:
            # Truncate overly long titles the LLM returned directly
            data["promotion_title"] = title[:77].rstrip() + "..."

        # Rule 2: missing or rewards-boilerplate summary — build from context
        summary = data.get("short_summary") or ""
        summary_is_missing = not summary or "unknown" in summary.lower()
        summary_is_boilerplate = "offers a rewards program where members can earn" in summary
        if summary_is_missing or summary_is_boilerplate:
            promo_type = data.get("promotion_type", "unknown")
            title_now = data.get("promotion_title", "")
            discount = data.get("discount_value")
            if promo_type == "reward":
                data["short_summary"] = (
                    f"{brand} offers a rewards program where members can earn points and redeem rewards."
                )
            elif discount and title_now:
                data["short_summary"] = f"{brand} is offering {discount} off. See terms for details."
            elif title_now:
                data["short_summary"] = f"{brand}: {title_now}."
            else:
                data["short_summary"] = f"{brand} has an active promotion. See terms for details."
            fixed = True

        # Rule 3: in_app redemption implies requires_app
        if data.get("redemption_method") == "in_app" and not data.get("requires_app"):
            data["requires_app"] = True
            fixed = True

        # Rule 4: unknown redemption on a non-app, non-store deal → online
        if (
            data.get("redemption_method") == "unknown"
            and not data.get("requires_app")
            and data.get("deal_scope") in ("online_only", "brand_level")
            and data.get("source_type") == "web_page"
        ):
            data["redemption_method"] = "online"
            fixed = True

        # Rule 5: cap confidence when fields were missing or fixed
        if fixed:
            score = data.get("confidence_score", 0.0)
            data["confidence_score"] = min(float(score), 0.75)

        return data

    def _build_prompt(
        self,
        text: str,
        brand: str,
        category: Optional[str],
        source_path: str,
    ) -> str:
        truncated = text[:_MAX_TEXT_CHARS]
        cat_line = f"Category: {category}\n" if category else ""

        return (
            "You are a promotional data extraction assistant.\n"
            "Extract ALL distinct promotions and deals from the raw scraped text below.\n"
            "Each separate deal, offer, or discount is its own item in the promotions array.\n"
            "Extract ALL distinct promotions and deals — every separate offer counts.\n\n"
            f"Brand: {brand}\n"
            f"{cat_line}"
            f"Source path: {source_path}\n\n"
            f"{_FIELD_SCHEMA}\n"
            "Extraction rules:\n"
            "- Only extract what is explicitly stated. Do not invent or guess values.\n"
            "- Set extraction_status to 'no_offer_found' and confidence_score < 0.3 when no clear promotion exists.\n"
            "- Only set discount_value when an explicit amount appears (e.g. '50% off', '$5 off').\n"
            "- confidence_score should reflect how completely and unambiguously the promotion is described.\n"
            "- Use the notes array for any ambiguities or caveats.\n"
            "- Keep terms_text to one short sentence (under 120 chars). Extract only the key restriction — do not copy full legal text.\n"
            "- If the text describes a rewards program or redemption catalog rather than one specific "
            "limited-time promotion, classify it as promotion_type='reward', discount_type='points', "
            "discount_value=null, and explain this in notes.\n"
            "- Do not infer birthday_related=true unless the text clearly describes a birthday reward, "
            "birthday gift, birthday month offer, or birthday freebie.\n"
            "- Do not infer new_user_only=true from generic phrases like 'join', 'sign up', or "
            "'create an account' unless the text clearly states the offer is only for new "
            "users/customers/members.\n"
            "- Use discount_type='free_shipping' for free shipping offers. Use 'free_item' only for "
            "physical free products (food, merchandise, samples). Never use 'free_item' for shipping.\n"
            "- Use discount_type='sale_price' for fixed recurring subscription prices "
            "(e.g. '$6.99/month for Premium Student', '$18.99/month for Premium Duo'). "
            "Set discount_value to the price per period (e.g. '$6.99/month').\n"
            "- Set membership_cost to 'free' if the program is free to join, 'unknown' if not stated. "
            "Set membership_cost to null if requires_membership is false.\n"
            "- If the offer is redeemable on a website with no app or in-store requirement, use "
            "redemption_method='online'.\n"
            "- Do NOT extract third-party credit card or bank partnership promotions (e.g. 'Free shipping with the Chase Sapphire Card'). "
            "Only extract promotions offered directly by the brand.\n\n"
            "If no promotions are found, return {\"promotions\": []}.\n"
            "Respond with ONLY the JSON object. No explanation, no markdown, no code fences.\n\n"
            "--- RAW TEXT START ---\n"
            f"{truncated}\n"
            "--- RAW TEXT END ---"
        )

    def _call_ollama(self, prompt: str) -> str:
        url = f"{self.host}/api/chat"
        payload = {
            "model": self.model_name,
            "messages": [{"role": "user", "content": prompt}],
            "stream": False,
            "format": "json",
            "options": {"num_predict": 8192},
        }

        try:
            response = requests.post(url, json=payload, timeout=self.timeout)
            response.raise_for_status()
        except requests.ConnectionError as exc:
            raise RuntimeError(
                f"Cannot connect to Ollama at {self.host}. "
                "Is Ollama running? Try: ollama serve"
            ) from exc
        except requests.Timeout:
            raise RuntimeError(
                f"Ollama request timed out after {self.timeout}s. "
                "Try a smaller model or increase --timeout."
            ) from None

        result = response.json()
        return result["message"]["content"]

    def _extract_promotions_list(self, raw: str) -> List[dict]:
        parsed = self._parse_raw_json(raw)

        # {"promotions": [...]} — expected format
        if isinstance(parsed, dict) and "promotions" in parsed:
            items = parsed["promotions"]
            if isinstance(items, list):
                return [i for i in items if isinstance(i, dict)]

        # [...] — LLM returned array directly
        if isinstance(parsed, list):
            return [i for i in parsed if isinstance(i, dict)]

        # {...} — LLM returned a single promotion object
        if isinstance(parsed, dict) and any(
            k in parsed for k in ("promotion_type", "discount_type", "extraction_status")
        ):
            return [parsed]

        raise ValueError(
            f"Could not extract a promotions list from Ollama response.\n"
            f"Raw response (first 500 chars): {raw[:500]}"
        )

    def _parse_raw_json(self, raw: str) -> Any:
        raw = raw.strip()

        # Strip markdown code fences if the model ignored the instruction
        fence = re.search(r"```(?:json)?\s*([\s\S]+?)\s*```", raw)
        if fence:
            raw = fence.group(1).strip()

        # Try full parse first
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            pass

        # Fall back to finding the outermost { } or [ ] block
        block = re.search(r"(\{[\s\S]+\}|\[[\s\S]+\])", raw)
        if block:
            try:
                return json.loads(block.group(0))
            except json.JSONDecodeError:
                pass

        # Partial recovery: response was truncated mid-JSON (num_predict cutoff).
        # Find all complete promotion objects before the truncation point.
        if '"promotions"' in raw:
            matches = list(re.finditer(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)?\}', raw))
            items = []
            for m in matches:
                try:
                    obj = json.loads(m.group(0))
                    if isinstance(obj, dict) and "brand" in obj:
                        items.append(obj)
                except json.JSONDecodeError:
                    continue
            if items:
                return {"promotions": items}

        raise ValueError(
            f"Ollama did not return valid JSON.\n"
            f"Raw response (first 500 chars): {raw[:500]}"
        )
