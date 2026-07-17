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
  "notes": "array of strings (observations, caveats, ambiguities)",
  "target_gender": "one of: women | men | kids | unisex — or null if not a fashion/apparel deal. Use 'unisex' when the page covers both men and women equally.",
  "product_keywords_explicit": "array of strings (max 10) — product types this deal DIRECTLY targets. Fill from the deal title, summary, or the sale grid / offer container immediately associated with this specific deal. E.g. '20% off running shoes' → ['running shoes', 'sneakers']. Use specific product-type nouns only — not colors, genders, fit descriptors, or promo words like 'sale', 'new', 'summer'. Leave [] for truly sitewide deals or rewards programs.",
  "product_keywords_contextual": "array of strings (max 25) — ONLY for sitewide or brand-wide deals: product types visible in product cards or grids on this page. Require at least 3 distinct product examples to support each term. Do NOT draw from: nav menus, footer links, SEO metadata, image alt text, breadcrumbs, recommended articles, or legal text. Leave [] when product_keywords_explicit is non-empty or for rewards programs.",
  "product_categories": "array of strings (max 5) — broad buckets this deal covers, chosen from: footwear, clothing, accessories, beauty, food, electronics, home, fitness, travel, other. Leave [] only for pure rewards programs."
    }
  ]
}
"""

_MAX_TEXT_CHARS = 30_000

_VALID_PROMOTION_TYPES = {"reward", "app_offer", "sale", "coupon", "birthday_reward", "membership_benefit", "unknown"}
_VALID_DISCOUNT_TYPES = {"percentage_off", "amount_off", "free_item", "free_shipping", "points", "sale_price", "unknown"}
_VALID_REDEMPTION_METHODS = {"in_app", "in_store", "online", "show_code", "scan_barcode", "unknown"}
_VALID_DEAL_SCOPES = {"brand_level", "location_specific", "online_only", "unknown"}
_VALID_FRICTION_LEVELS = {"low", "medium", "high", "unknown"}
_VALID_EXTRACTION_STATUSES = {"success", "no_offer_found", "failed"}
_VALID_SOURCE_TYPES = {"web_page", "email", "unknown"}
_VALID_MEMBERSHIP_COSTS = {"free", "unknown"}
_VALID_TARGET_GENDERS = {"women", "men", "kids", "unisex"}

_GENDER_WOMEN_TOKENS = frozenset([
    "women", "woman", "womens", "womenswear", "her", "ladies", "lady", "girls", "girl",
])
_GENDER_MEN_TOKENS = frozenset([
    "mens", "menswear", "him", "guys", "guy", "boys", "boy",
])
_GENDER_MEN_EXACT = frozenset(["men", "man"])  # exact-only to avoid matching inside "women"
_GENDER_KIDS_TOKENS = frozenset([
    "kids", "kid", "children", "child", "baby", "babies", "toddler", "infant", "infants",
])
_ARRAY_FIELDS = {"valid_days", "redemption_steps", "friction_reasons", "notes", "product_keywords_explicit", "product_keywords_contextual", "product_categories"}
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

        # Non-fatal: a bad LLM response (wrong key, malformed schema) should
        # never crash the pipeline — treat it as 0 deals and let the synthesizer
        # attempt a fallback below.
        try:
            items = self._extract_promotions_list(raw_response)
        except ValueError as exc:
            print(f"[WARN] {brand}: LLM response unparseable — {exc!s:.200}")
            items = []

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
            # All items failed validation — warn but don't crash; synthesizer
            # will attempt a fallback on the raw text below.
            print(
                f"[WARN] {brand}: all {len(errors)} LLM item(s) failed Pydantic validation "
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

        # Collapse product-grid deals: if the LLM returned multiple individual sale items
        # (each with a product name as title and no promo code/membership), it has
        # mistaken a collection page for individual deals. Replace with one synthesized card.
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
                synthesized = self._synthesize_sale_from_price_grid(text, brand, category, source_path)
                if synthesized:
                    dv = synthesized[0].discount_value or ""
                    print(
                        f"[SYNTH] {brand}: LLM returned {len(grid_deals)} product-grid deals — "
                        f"collapsed into one synthesized card ({dv})"
                    )
                    return synthesized

        # Always try the synthesizer — even when the LLM found deals it may have missed
        # additional price-grid discounts. The synthesized card is added alongside LLM deals,
        # not instead of them. Normalizer dedup removes any title-level overlap.
        synthesized = self._synthesize_sale_from_price_grid(text, brand, category, source_path)
        if synthesized:
            dv = synthesized[0].discount_value or ""
            if unique:
                print(f"[SYNTH] {brand}: supplementing {len(unique)} LLM deal(s) with price-grid card ({dv})")
                unique.extend(synthesized)
            else:
                print(f"[SYNTH] {brand}: LLM found 0 deals — synthesized sale deal from price grid ({dv})")
                return synthesized

        return unique

    # ------------------------------------------------------------------ #
    # Internals                                                            #
    # ------------------------------------------------------------------ #

    # Taxonomy: keywords → (category_label, extracted_keywords_for_search)
    # Each tuple: (trigger_words, category_label, search_keywords)
    # trigger_words: if any appear in product text → assign this category
    # search_keywords: individual terms stored in product_keywords for exact search matching
    _TAXONOMY: list[tuple[list[str], str, list[str]]] = [
        (
            ["jacket", "coat", "blazer", "bomber", "parka", "anorak", "windbreaker", "vest", "gilet", "outerwear"],
            "outerwear",
            ["jacket", "coat", "blazer", "bomber", "parka"],
        ),
        (
            ["pants", "trousers", "chinos", "leggings", "joggers", "shorts", "bottoms"],
            "bottoms",
            ["pants", "trousers", "leggings", "joggers", "shorts"],
        ),
        (
            ["jeans", "denim"],
            "denim",
            ["jeans", "denim"],
        ),
        (
            ["dress", "gown", "midi", "maxi", "minidress"],
            "dresses",
            ["dress", "gown"],
        ),
        (
            ["skirt"],
            "skirts",
            ["skirt"],
        ),
        (
            ["shirt", "tee", "t-shirt", "blouse", "top", "polo"],
            "tops",
            ["shirt", "tee", "blouse", "top", "polo"],
        ),
        (
            ["hoodie", "sweatshirt", "sweater", "cardigan", "knit", "pullover"],
            "sweaters",
            ["hoodie", "sweatshirt", "sweater", "cardigan"],
        ),
        (
            ["shoes", "sneakers", "boots", "sandals", "heels", "loafers", "flats", "mules", "espadrilles", "footwear"],
            "shoes",
            ["shoes", "sneakers", "boots", "sandals", "heels"],
        ),
        (
            ["bag", "handbag", "purse", "tote", "wallet", "crossbody", "clutch", "satchel", "backpack"],
            "bags",
            ["bag", "handbag", "purse", "tote", "wallet", "crossbody"],
        ),
        (
            ["belt", "hat", "cap", "scarf", "sunglasses", "jewelry", "necklace", "bracelet", "earrings", "ring", "watch", "accessories"],
            "accessories",
            ["belt", "hat", "scarf", "sunglasses", "jewelry", "watch"],
        ),
        (
            ["bra", "underwear", "lingerie", "socks", "intimates"],
            "intimates",
            ["bra", "underwear", "lingerie", "socks"],
        ),
        (
            ["swimwear", "swim", "bikini", "one-piece", "boardshort", "trunks"],
            "swimwear",
            ["swimwear", "bikini", "swim trunks"],
        ),
        (
            ["perfume", "fragrance", "cologne", "scent", "eau de"],
            "fragrance",
            ["perfume", "fragrance", "cologne"],
        ),
        (
            ["makeup", "lipstick", "mascara", "foundation", "concealer", "blush", "eyeshadow"],
            "makeup",
            ["makeup", "lipstick", "mascara", "foundation"],
        ),
        (
            ["skincare", "moisturizer", "cleanser", "serum", "sunscreen", "toner", "retinol"],
            "skincare",
            ["skincare", "moisturizer", "cleanser", "serum"],
        ),
        (
            ["suit", "tuxedo", "blazer set"],
            "suits",
            ["suit", "tuxedo"],
        ),
        (
            ["luggage", "suitcase", "duffle", "travel bag"],
            "luggage",
            ["luggage", "suitcase"],
        ),
    ]

    # Words to strip when extracting dynamic product-type tokens from product lines.
    # These are descriptors (colors, materials, fit, pattern) that don't identify the product.
    _KEYWORD_NOISE: frozenset[str] = frozenset({
        # colors
        "red","blue","black","white","green","yellow","purple","pink","orange",
        "gray","grey","brown","beige","navy","cream","ivory","tan","taupe",
        "olive","coral","teal","mint","khaki","gold","silver","nude","rose",
        "lilac","lavender","burgundy","maroon","mustard","charcoal","ecru",
        # materials
        "cotton","linen","polyester","nylon","leather","faux","silk","wool",
        "cashmere","canvas","suede","velvet","mesh","jersey","satin","chiffon",
        "tweed","fleece","flannel","modal","synthetic","organic","recycled",
        "blend","mixed","knit","woven","ribbed","terry","denim","chambray",
        # fit / style descriptors
        "slim","regular","relaxed","straight","loose","fitted","oversized",
        "cropped","long","short","high","low","mid","wide","flared","tapered",
        "skinny","bootcut","classic","essential","basic","lightweight","heavy",
        "stretch","comfort","plus","petite","tall","asymmetric","wrap",
        # patterns
        "striped","plaid","floral","solid","print","printed","pattern",
        "graphic","logo","embroidered","tie","dye","checkered","abstract",
        "leopard","animal","geometric","tropical","vintage","washed",
        # generic qualifiers
        "new","sale","clearance","original","limited","edition","collection",
        "and","the","with","for","from","into","fit","cut","leg","neck",
        "sleeve","collar","zip","button","pocket","lined","unlined","padded",
        "size","small","medium","large","extra","one","piece","set",
    })

    # Patterns that indicate a line is NOT a product name
    _SKIP_LINE_RE  = re.compile(
        r'(cookie|privacy|cart|checkout|log\s*in|sign\s*in|menu|filter|sort|'
        r'view|search|copyright|terms|policy|newsletter|subscribe|javascript|'
        r'wishlist|account|share|follow|©|all rights)',
        re.IGNORECASE,
    )
    _PRICE_LINE_RE = re.compile(r'^\s*[\$\-\+]?\s*\d[\d\.,]*\s*%?\s*$')
    _SIZE_ONLY_RE  = re.compile(r'^(XS|S|M|L|XL|XXL|XXXL|\d+|one\s+size)$', re.IGNORECASE)
    _STRIP_SIZE_RE = re.compile(r'\b(xs|s|m|l|xl|xxl|xxxl|one\s+size)\b', re.IGNORECASE)

    def _extract_product_lines(self, text: str) -> list[str]:
        """Return cleaned product name lines from the raw text (near price lines)."""
        lines = text.splitlines()

        price_line_idx: set[int] = set()
        for i, line in enumerate(lines):
            if re.search(r'\$\s*\d+', line) or re.search(r'-\d+%', line):
                price_line_idx.add(i)

        names: list[str] = []
        seen: set[str] = set()
        for i, line in enumerate(lines):
            if not any(abs(i - pi) <= 5 for pi in price_line_idx):
                continue
            raw = line.strip()
            if len(raw) < 4:
                continue
            if self._PRICE_LINE_RE.match(raw):
                continue
            if self._SKIP_LINE_RE.search(raw):
                continue
            if self._SIZE_ONLY_RE.match(raw):
                continue
            if raw.startswith('$') or ('%' in raw and len(raw) < 8):
                continue
            norm = self._STRIP_SIZE_RE.sub('', raw.lower())
            norm = re.sub(r'\s+', ' ', norm).strip(' ,.-')
            if len(norm) < 3 or norm in seen:
                continue
            seen.add(norm)
            names.append(norm)
        return names[:30]

    def _classify_products(self, product_lines: list[str], *, taxonomy_only: bool = False) -> tuple[list[str], list[str]]:
        """
        Returns (product_categories, product_keywords).

        product_categories: deduplicated category labels (e.g. ["outerwear", "bottoms"])
        product_keywords:   individual search terms drawn from matched taxonomy entries
                            plus meaningful words from product names not covered by taxonomy

        taxonomy_only=True: skip dynamic n-gram extraction (use when input is deal text,
                            not raw product name lines — avoids generating garbage tokens).
        """
        combined = ' '.join(product_lines).lower()

        categories: list[str] = []
        keywords: list[str] = []
        seen_cats: set[str] = set()
        seen_kw: set[str] = set()

        for triggers, label, search_kws in self._TAXONOMY:
            if label in seen_cats:
                continue
            # Use word-boundary matching so "top" doesn't fire inside "laptop"
            # or "dress" inside "address", etc.
            if any(re.search(r'\b' + re.escape(t) + r'\b', combined) for t in triggers):
                categories.append(label)
                seen_cats.add(label)
                for kw in search_kws:
                    if kw not in seen_kw:
                        keywords.append(kw)
                        seen_kw.add(kw)

        # Dynamic extraction: pull individual words + bigrams from every product line,
        # stripping noise words so only meaningful product-type tokens remain.
        # This means any product name (tank top, cargo shorts, slip dress…) that
        # appears in the raw text becomes a searchable keyword automatically.
        # Skipped when taxonomy_only=True (deal title/summary text as input).
        if taxonomy_only:
            return categories, keywords[:80]

        for line in product_lines:
            tokens = [
                w for w in re.split(r'[\s\-/]+', line.lower())
                if len(w) >= 3 and w not in self._KEYWORD_NOISE
            ]

            # Individual tokens
            for tok in tokens:
                if tok not in seen_kw:
                    keywords.append(tok)
                    seen_kw.add(tok)

            # Bigrams (adjacent token pairs — "tank top", "cargo shorts", etc.)
            for i in range(len(tokens) - 1):
                bigram = f"{tokens[i]} {tokens[i + 1]}"
                if bigram not in seen_kw:
                    keywords.append(bigram)
                    seen_kw.add(bigram)

            # Full product name phrase (for longer exact/contains matching)
            if 4 <= len(line) <= 60 and line not in seen_kw:
                keywords.append(line)
                seen_kw.add(line)

        return categories, keywords[:80]  # cap to avoid bloat

    def _detect_gender(self, product_lines: list[str], text: str) -> str | None:
        """Infer target_gender from product lines and page text. Returns None for non-fashion."""
        sample = " ".join(product_lines[:60]).lower() + " " + text[:2000].lower()
        tokens = set(re.split(r'[\s\-/\']+', sample))

        has_women = bool(tokens & _GENDER_WOMEN_TOKENS)
        has_men = bool(
            (tokens & _GENDER_MEN_TOKENS)
            or any(t in _GENDER_MEN_EXACT for t in tokens)
        )
        has_kids = bool(tokens & _GENDER_KIDS_TOKENS)

        if has_kids and not has_women and not has_men:
            return "kids"
        if has_women and has_men:
            return "unisex"
        if has_women:
            return "women"
        if has_men:
            return "men"
        return None

    def _synthesize_sale_from_price_grid(
        self,
        text: str,
        brand: str,
        category: Optional[str],
        source_path: str,
    ) -> List[Promotion]:
        """
        Fallback synthesizer for pages where the LLM found no explicit deal text.

        Two tiers:
          1. Price-pair detected  — computes discount range, emits "[Brand] Sale — up to X% off"
          2. Products only        — emits a generic "[Brand] Sale" with items as keywords,
                                   no discount value. Fires even with a single product found.

        Always returns [] if the page has neither price signals nor any product names.
        """
        # Extract products first — used for keywords in both tiers
        product_lines = self._extract_product_lines(text)
        product_cats, product_kws = self._classify_products(product_lines)
        target_gender = self._detect_gender(product_lines, text)

        matched_examples: list[str] = []
        seen_ex: set[str] = set()
        for line in product_lines:
            if len(matched_examples) >= 10:
                break
            orig = line.strip()
            upper = orig.upper()
            if upper not in seen_ex and len(orig) >= 4:
                matched_examples.append(upper)
                seen_ex.add(upper)

        # Tier 1: detect price-pair markdowns.
        # Match dollar-prefixed and bare 2-decimal prices in document order, then only
        # pair adjacent prices where the text between them contains ≤20 alphabetic
        # characters. This allows short labels ("Was", "Regular", "Save") but rejects
        # product names that separate different grid items — preventing cross-product
        # inflation like pairing a $42 bag against a $249 dress three rows away.
        # Dollar amounts handle comma-separated thousands (e.g. $2,999.00 → 2999.0).
        # Bare prices require exactly two decimal places to avoid matching ratings/counts.
        _price_re = re.compile(
            r'\$\s*(\d[\d,]*(?:\.\d{2})?)|(?<![.\d])(\d+\.\d{2})(?![.\d])'
        )
        price_matches = list(_price_re.finditer(text))

        discounts: list[int] = []
        for i in range(len(price_matches) - 1):
            m_i, m_j = price_matches[i], price_matches[i + 1]
            between = text[m_i.end():m_j.start()]
            # Skip price-range UI ("$100 - $300"), savings-amount labels, and
            # navigation/filter text that separates unrelated prices.
            between_stripped = between.strip()
            if between_stripped in ("-", "–", "to"):
                continue
            between_lower = between.lower()
            if any(kw in between_lower for kw in ("save", "refine", "filter", "rebate")):
                continue
            if sum(c.isalpha() for c in between) > 20:
                continue  # product name between prices → different items, not a pair
            v_i = float((m_i.group(1) or m_i.group(2)).replace(",", ""))
            v_j = float((m_j.group(1) or m_j.group(2)).replace(",", ""))
            if not (1.0 < v_i < 5000 and 1.0 < v_j < 5000):
                continue
            lo, hi = min(v_i, v_j), max(v_i, v_j)
            if hi == 0:
                continue
            ratio = (hi - lo) / hi
            pct = round(ratio * 100)
            if 10 <= pct <= 85:
                discounts.append(pct)

        # Need at least one price pair with a real markdown (≥20%) to synthesize a deal.
        # Product types don't need to match — a mix of shoes, chairs, and food items all
        # qualifying is fine. What matters is that prices are actually dropping.
        valid_discounts = [d for d in discounts if d >= 20]
        if not valid_discounts:
            return []

        max_disc = max(valid_discounts)
        min_disc = min(valid_discounts)
        discount_value = f"up to {max_disc}% off"
        title = f"{brand} Sale"
        summary = f"{brand} has items on sale with discounts from {min_disc}% to {max_disc}% off."
        if product_cats:
            summary += f" On sale: {', '.join(product_cats)}."
        return [Promotion(
            brand=brand,
            category=category,
            promotion_title=title,
            short_summary=summary,
            promotion_type="sale",
            discount_type="percentage_off",
            discount_value=discount_value,
            requires_membership=False,
            requires_app=False,
            purchase_required=False,
            redemption_method="online",
            deal_scope="online_only",
            friction_level="low",
            friction_reasons=[],
            confidence_score=0.65,
            source_type="web_page",
            source_path=source_path,
            extraction_status="success",
            notes=[
                f"Synthesized from product-grid price pairs ({len(valid_discounts)} qualifying pairs found).",
                f"Discount range: {min_disc}%–{max_disc}%.",
                "No explicit deal text — inferred from sale vs. original price pairs.",
            ],
            synthesized=True,
            synthesis_reason="price_grid_markdown",
            product_categories=product_cats[:5],
            product_keywords_explicit=[],
            product_keywords_contextual=product_kws[:25],
            matched_product_examples=matched_examples,
            target_gender=target_gender,
        )]

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
                coerced = []
                for item in val:
                    if item is None:
                        continue
                    if isinstance(item, dict):
                        # LLM returned {"step": "..."} or {"day": "..."} instead of a plain string
                        inner = next(iter(item.values()), None)
                        if inner is not None:
                            coerced.append(str(inner))
                    else:
                        coerced.append(item)
                data[field] = coerced

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

        tg = data.get("target_gender")
        if tg is not None:
            data["target_gender"] = str(tg).lower() if str(tg).lower() in _VALID_TARGET_GENDERS else None

        # timezone: non-optional field — default if LLM returned null or empty
        if not data.get("timezone"):
            data["timezone"] = "America/Chicago"

        # discount_value / promo_code: treat the string "null" as actual null
        for _field in ("discount_value", "promo_code"):
            val = data.get(_field)
            if isinstance(val, str) and val.strip().lower() in {"null", "none", "n/a", ""}:
                data[_field] = None

        # Fix year hallucination in date fields: LLM sometimes writes a past year
        # (e.g. 2023-07-05 instead of 2026-07-05), which causes the expiry filter
        # to silently drop valid deals. Bump any past-year date to the current year.
        import datetime as _dt
        _today = _dt.date.today()
        _date_re = re.compile(r'^(\d{4})(-\d{2}-\d{2})$')
        for _field in ("start_date", "end_date"):
            val = data.get(_field)
            if not isinstance(val, str):
                continue
            m = _date_re.match(val.strip())
            if not m:
                continue
            year = int(m.group(1))
            rest = m.group(2)
            if year < _today.year:
                # Bump to current year; if that date is still in the past, bump to next year
                candidate = _dt.date(year=_today.year, month=int(rest[1:3]), day=int(rest[4:6]))
                if candidate < _today:
                    candidate = candidate.replace(year=_today.year + 1)
                data[_field] = candidate.isoformat()

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

        # Rule 6: taxonomy fallback for explicit keywords when LLM left them empty.
        # Only runs on deal title+summary (structured text) so taxonomy_only avoids garbage n-grams.
        if not data.get("product_keywords_explicit"):
            title_text = data.get("promotion_title") or ""
            summary_text = data.get("short_summary") or ""
            cats, kws = self._classify_products([title_text, summary_text], taxonomy_only=True)
            if kws:
                data["product_keywords_explicit"] = kws[:10]
            if cats and not data.get("product_categories"):
                data["product_categories"] = cats[:5]

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
            "Only extract promotions offered directly by the brand.\n"
            "- Do NOT extract promotions whose title or description is not in English. Skip any deal written in Spanish, French, or any other non-English language.\n"
            "- If the page is a product collection or sale grid (many individual products listed with prices), "
            "return ONE deal card summarizing the overall sale (e.g. 'Zara Sale — up to 50% off') rather than "
            "individual cards per product. List specific product names only in matched_product_examples, "
            "not as separate deals.\n"
            "- Do NOT extract sweepstakes, contests, or raffles. A chance to win a prize is not a deal "
            "(e.g. 'MINIONS & MONSTERS Sweepstakes' should be skipped entirely).\n"
            "- Do NOT extract plain movie or event ticket sales offered at full price. A listing like "
            "'MOONLIGHT Tickets' or 'A STAR IS BORN Tickets' that simply advertises buying tickets "
            "is NOT a deal — skip it unless there is an explicit discount (e.g. '50% off tickets', "
            "'free ticket with purchase').\n"
            "- Do NOT extract service offerings at regular price (e.g. 'Private Theatre Rental', "
            "'Room Booking') — skip them unless a genuine discount is explicitly stated.\n"
            "- Do NOT extract membership feature descriptions as separate deals. If the text describes "
            "what a paid membership plan already includes (e.g. 'A-List: Extra Weekly Opportunity' "
            "describes a feature of the A-List subscription), that is NOT a promotional deal — skip it. "
            "Only extract when there is a distinct limited-time or new promotional offer on top of the "
            "membership's normal benefits.\n"
            "- product_keywords_explicit (max 10): specific product-type nouns the deal DIRECTLY covers — from the deal title, "
            "summary, or the offer container/sale grid for this deal. '20% off running shoes' → ['running shoes', 'sneakers']. "
            "Exclude colors, genders, fit words, and promo words ('sale', 'new', 'limited'). Leave [] for sitewide deals.\n"
            "- product_keywords_contextual (max 25): ONLY fill for sitewide/brand-wide deals (when explicit is []). "
            "Extract product types from product cards and grids on the page. Need 3+ distinct examples to support each term. "
            "Do NOT use: nav, footer, SEO tags, breadcrumbs, alt text, recommended articles, or legal text.\n"
            "- product_categories (max 5): broad buckets from: footwear, clothing, accessories, beauty, food, "
            "electronics, home, fitness, travel, other. Leave [] only for pure rewards programs.\n\n"
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
            "options": {"num_predict": 8192, "num_ctx": 32768},
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

        # {"products"/"items"/"deals"/... : [...]} — LLM used wrong key name
        # (e.g. J.Crew → "products", Nordstrom → "items").
        # Return whatever list we find; Pydantic validation will filter bad items.
        _ALT_KEYS = ("products", "items", "deals", "offers", "data", "results", "coupons", "sales")
        if isinstance(parsed, dict):
            for key in _ALT_KEYS:
                val = parsed.get(key)
                if isinstance(val, list):
                    return [i for i in val if isinstance(i, dict)]
            # Dict with no recognised list key — treat as no deals found
            return []

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
