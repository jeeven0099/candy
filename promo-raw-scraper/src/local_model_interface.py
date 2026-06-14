from __future__ import annotations

import re
from abc import ABC, abstractmethod
from typing import List, Optional

from models import Promotion


class LocalModelInterface(ABC):
    @abstractmethod
    def parse_text(
        self,
        text: str,
        brand: str,
        category: Optional[str],
        source_path: str,
    ) -> List[Promotion]:
        raise NotImplementedError


class RuleBasedLocalModel(LocalModelInterface):
    """
    Offline parser.
    No internet.
    No API calls.
    No model calls.

    It creates a first-pass structured Promotion object from local text.
    Later, this can be replaced with Ollama/OpenAI while keeping the same interface.
    """

    def parse_text(
        self,
        text: str,
        brand: str,
        category: Optional[str],
        source_path: str,
    ) -> List[Promotion]:
        lower = text.lower()

        useful_keywords = [
            "reward",
            "rewards",
            "offer",
            "deal",
            "promo",
            "promotion",
            "coupon",
            "discount",
            "sale",
            "valid",
            "expires",
            "birthday",
            "member",
            "membership",
            "app",
        ]

        keyword_hits = sum(lower.count(k) for k in useful_keywords)

        if keyword_hits == 0 or len(text.strip()) < 200:
            return [Promotion(
                brand=brand,
                category=category,
                promotion_title=None,
                short_summary=f"No clear offer or reward text found for {brand}.",
                promotion_type="unknown",
                discount_type="unknown",
                requires_membership=False,
                requires_app=False,
                confidence_score=0.15,
                source_type="web_page",
                source_path=source_path,
                extraction_status="no_offer_found",
                notes=[
                    "Text was too short or did not contain common offer/reward keywords."
                ],
            )]

        requires_membership = any(
            phrase in lower
            for phrase in [
                "member",
                "membership",
                "rewards",
                "reward member",
                "loyalty",
                "insider",
                "circle",
                "extra care",
                "extracare",
                "stubs",
            ]
        )

        requires_app = " app" in lower or "mobile app" in lower or "in the app" in lower

        birthday_related = "birthday" in lower

        new_user_only = any(
            phrase in lower
            for phrase in [
                "new user",
                "new customer",
                "first order",
                "first purchase",
                "sign up",
                "join now",
                "when you join",
            ]
        )

        has_clear_offer = self._has_clear_offer_evidence(lower)

        promotion_type = self._infer_promotion_type(lower)
        discount_type, discount_value = self._infer_discount(lower)

        # Safety rule:
        # If there is no clear offer evidence, do not create a specific discount.
        if not has_clear_offer:
            discount_type = "unknown"
            discount_value = None

            # If this is a rewards page, classify it as a general rewards program,
            # not a specific discount/promo.
            if "reward" in lower or "rewards" in lower or "loyalty" in lower:
                promotion_type = "reward"
            else:
                promotion_type = "unknown"

        membership_name = self._infer_membership_name(brand, lower, requires_membership)

        time_start, time_end = self._infer_time_window(text)

        redemption_method = self._infer_redemption_method(lower)
        redemption_steps = self._infer_redemption_steps(
            brand=brand,
            requires_app=requires_app,
            redemption_method=redemption_method,
            requires_membership=requires_membership,
        )

        friction_level, friction_reasons = self._infer_friction(
            requires_membership=requires_membership,
            requires_app=requires_app,
            new_user_only=new_user_only,
            redemption_method=redemption_method,
        )

        title = self._infer_title(
            brand=brand,
            promotion_type=promotion_type,
            discount_value=discount_value,
            birthday_related=birthday_related,
        )

        summary = self._infer_summary(
            brand=brand,
            promotion_type=promotion_type,
            discount_value=discount_value,
            requires_membership=requires_membership,
            requires_app=requires_app,
            birthday_related=birthday_related,
        )

        terms_text = self._extract_terms_snippet(text)

        confidence = self._score_confidence(
            text_length=len(text),
            keyword_hits=keyword_hits,
            discount_value=discount_value,
            requires_membership=requires_membership,
            terms_text=terms_text,
        )

        return [Promotion(
            brand=brand,
            category=category,
            promotion_title=title,
            short_summary=summary,
            promotion_type=promotion_type,
            discount_type=discount_type,
            discount_value=discount_value,
            requires_membership=requires_membership,
            membership_name=membership_name,
            membership_cost="free" if requires_membership else None,
            requires_app=requires_app,
            requires_account_login=requires_membership or requires_app,
            new_user_only=new_user_only,
            birthday_related=birthday_related,
            time_start=time_start,
            time_end=time_end,
            redemption_method=redemption_method,
            redemption_steps=redemption_steps,
            terms_text=terms_text,
            purchase_required=self._infer_purchase_required(lower),
            deal_scope="brand_level",
            friction_level=friction_level,
            friction_reasons=friction_reasons,
            confidence_score=confidence,
            source_type="web_page",
            source_path=source_path,
            extraction_status="success",
            notes=[
                "Generated by offline rule-based parser.",
                "Review manually before treating as final promotion data.",
            ],
        )]

    def _infer_promotion_type(self, lower: str) -> str:
        if "birthday" in lower:
            return "birthday_reward"
        if "coupon" in lower:
            return "coupon"
        if "sale" in lower or "clearance" in lower:
            return "sale"
        if "app" in lower and ("offer" in lower or "deal" in lower):
            return "app_offer"
        if "reward" in lower or "rewards" in lower:
            return "reward"
        if "member" in lower or "membership" in lower:
            return "membership_benefit"
        return "unknown"

    def _infer_discount(self, lower: str) -> tuple[str, Optional[str]]:
        """
        Only return a specific discount when there is clear evidence.

        Avoid false positives like:
        - "50 points"
        - "50 states"
        - "5 min purchase required"
        - random numbers on the page
        """

        # Clear percentage discount: "50% off", "50 percent off"
        pct = re.search(r"\b(\d{1,3})\s?(%|percent)\s?off\b", lower)
        if pct:
            return "percentage_off", f"{pct.group(1)}%"

        # Clear amount discount: "$5 off", "5 dollars off"
        amount_symbol = re.search(r"\$\s?(\d+(?:\.\d{2})?)\s?off\b", lower)
        if amount_symbol:
            return "amount_off", f"${amount_symbol.group(1)}"

        amount_words = re.search(r"\b(\d+(?:\.\d{2})?)\s?dollars?\s?off\b", lower)
        if amount_words:
            return "amount_off", f"${amount_words.group(1)}"

        # Clear free-item language
        free_patterns = [
            r"\bfree\s+(drink|beverage|coffee|item|entrée|entree|meal|dessert|appetizer|sandwich|reward|gift)\b",
            r"\bget\s+a\s+free\s+(drink|beverage|coffee|item|entrée|entree|meal|dessert|appetizer|sandwich|reward|gift)\b",
            r"\bfree\s+with\s+purchase\b",
        ]

        for pattern in free_patterns:
            if re.search(pattern, lower):
                return "free_item", "free"

        # Points-based rewards, but only if points are clearly tied to rewards
        if re.search(r"\bearn\s+\d+\s+points?\b", lower) or re.search(r"\bpoints?\s+toward\s+(a\s+)?reward\b", lower):
            return "points", None

        # Sale price, but only if sale/clearance language is clear
        if re.search(r"\b(sale|clearance|markdown|limited-time sale)\b", lower):
            return "sale_price", None

        # No clear discount found
        return "unknown", None
    def _has_clear_offer_evidence(self, lower: str) -> bool:
        """
        Returns True only when the text clearly describes a usable offer,
        discount, reward, or validity condition.
        """

        clear_patterns = [
            r"\b\d{1,3}\s?(%|percent)\s?off\b",
            r"\$\s?\d+(?:\.\d{2})?\s?off\b",
            r"\b\d+(?:\.\d{2})?\s?dollars?\s?off\b",
            r"\bfree\s+(drink|beverage|coffee|item|entrée|entree|meal|dessert|appetizer|sandwich|reward|gift)\b",
            r"\bvalid\s+(through|until|from)\b",
            r"\bexpires?\b",
            r"\blimited\s+time\b",
            r"\boffer\s+valid\b",
            r"\bpromo\s+code\b",
            r"\bcoupon\b",
            r"\bearn\s+\d+\s+points?\b",
            r"\bpoints?\s+toward\s+(a\s+)?reward\b",
        ]

        return any(re.search(pattern, lower) for pattern in clear_patterns)
    def _infer_membership_name(
        self,
        brand: str,
        lower: str,
        requires_membership: bool,
    ) -> Optional[str]:
        if not requires_membership:
            return None

        known = {
            "starbucks": "Starbucks Rewards",
            "chipotle": "Chipotle Rewards",
            "mcdonald": "MyMcDonald's Rewards",
            "chick-fil-a": "Chick-fil-A One",
            "target": "Target Circle",
            "sephora": "Beauty Insider",
            "ulta": "Ultamate Rewards",
            "cvs": "ExtraCare",
            "walgreens": "myWalgreens",
            "amc": "AMC Stubs",
            "cinemark": "Cinemark Movie Rewards",
            "best buy": "My Best Buy",
        }

        brand_lower = brand.lower()
        for key, value in known.items():
            if key in brand_lower:
                return value

        return f"{brand} Rewards"

    def _infer_time_window(self, text: str) -> tuple[Optional[str], Optional[str]]:
        pattern = re.compile(
            r"(\d{1,2})(?::(\d{2}))?\s?(am|pm)\s?(?:-|to|–)\s?"
            r"(\d{1,2})(?::(\d{2}))?\s?(am|pm)",
            re.IGNORECASE,
        )
        match = pattern.search(text)

        if not match:
            return None, None

        start_hour = int(match.group(1))
        start_minute = int(match.group(2) or 0)
        start_ampm = match.group(3).lower()

        end_hour = int(match.group(4))
        end_minute = int(match.group(5) or 0)
        end_ampm = match.group(6).lower()

        return (
            self._to_24h(start_hour, start_minute, start_ampm),
            self._to_24h(end_hour, end_minute, end_ampm),
        )

    def _to_24h(self, hour: int, minute: int, ampm: str) -> str:
        if ampm == "pm" and hour != 12:
            hour += 12
        if ampm == "am" and hour == 12:
            hour = 0
        return f"{hour:02d}:{minute:02d}"

    def _infer_redemption_method(self, lower: str) -> str:
        if "app" in lower:
            return "in_app"
        if "promo code" in lower or "code" in lower:
            return "show_code"
        if "barcode" in lower or "scan" in lower:
            return "scan_barcode"
        if "online" in lower:
            return "online"
        if "in store" in lower or "in-store" in lower:
            return "in_store"
        return "unknown"

    def _infer_redemption_steps(
        self,
        brand: str,
        requires_app: bool,
        redemption_method: str,
        requires_membership: bool,
    ) -> list[str]:
        steps: list[str] = []

        if requires_membership:
            steps.append(f"Sign in to or join the {brand} rewards/membership program.")

        if requires_app or redemption_method == "in_app":
            steps.append(f"Open the {brand} app or rewards account.")
            steps.append("Find and activate the offer if required.")
            steps.append("Use the app or account at checkout.")
        elif redemption_method == "show_code":
            steps.append("Copy or show the promo code at checkout.")
        elif redemption_method == "online":
            steps.append("Apply the offer during online checkout.")
        elif redemption_method == "in_store":
            steps.append("Ask the cashier or show the offer in store.")
        else:
            steps.append("Review the offer terms before checkout.")

        return steps

    def _infer_friction(
        self,
        requires_membership: bool,
        requires_app: bool,
        new_user_only: bool,
        redemption_method: str,
    ) -> tuple[str, list[str]]:
        reasons: list[str] = []
        score = 0

        if requires_membership:
            reasons.append("Membership or rewards account required")
            score += 1

        if requires_app:
            reasons.append("App may be required")
            score += 1

        if new_user_only:
            reasons.append("May be limited to new users")
            score += 2

        if redemption_method in {"show_code", "scan_barcode"}:
            reasons.append("Code or barcode may be required")
            score += 1

        if score <= 1:
            return "low", reasons or ["Simple redemption"]
        if score <= 3:
            return "medium", reasons
        return "high", reasons

    def _infer_title(
        self,
        brand: str,
        promotion_type: str,
        discount_value: Optional[str],
        birthday_related: bool,
    ) -> str:
        if discount_value:
            return f"{brand} {discount_value} offer"

        if birthday_related and promotion_type == "birthday_reward":
            return f"{brand} birthday reward"

        if promotion_type == "sale":
            return f"{brand} sale"

        if promotion_type == "reward":
            return f"{brand} rewards program"

        if promotion_type == "membership_benefit":
            return f"{brand} membership benefit"

        if promotion_type == "coupon":
            return f"{brand} coupon"

        return f"{brand} promotion"

    def _infer_summary(
        self,
        brand: str,
        promotion_type: str,
        discount_value: Optional[str],
        requires_membership: bool,
        requires_app: bool,
        birthday_related: bool,
    ) -> str:
        parts = [f"{brand} has"]

        if birthday_related:
            parts.append("a birthday-related reward")
        elif discount_value:
            parts.append(f"a {discount_value} offer")
        elif promotion_type == "sale":
            parts.append("a sale or discount offer")
        elif promotion_type == "reward":
            parts.append("a rewards-related offer")
        else:
            parts.append("a promotion")

        if requires_membership:
            parts.append("that may require membership")

        if requires_app:
            parts.append("and may require the app")

        return " ".join(parts) + "."

    def _extract_terms_snippet(self, text: str) -> str:
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        useful_lines = []

        keywords = [
            "valid",
            "expires",
            "terms",
            "offer",
            "reward",
            "member",
            "app",
            "purchase",
            "participating",
            "coupon",
            "discount",
            "birthday",
        ]

        for line in lines:
            lower = line.lower()
            if any(k in lower for k in keywords):
                useful_lines.append(line)

        snippet = " ".join(useful_lines[:8])
        if not snippet:
            snippet = " ".join(lines[:5])

        return snippet[:1500]

    def _infer_purchase_required(self, lower: str) -> bool:
        return any(
            phrase in lower
            for phrase in [
                "purchase required",
                "with purchase",
                "when you buy",
                "first purchase",
                "minimum purchase",
            ]
        )

    def _score_confidence(
        self,
        text_length: int,
        keyword_hits: int,
        discount_value: Optional[str],
        requires_membership: bool,
        terms_text: str,
    ) -> float:
        score = 0.25

        if text_length > 1000:
            score += 0.15
        if text_length > 3000:
            score += 0.10
        if keyword_hits > 5:
            score += 0.15
        if keyword_hits > 20:
            score += 0.10
        if discount_value:
            score += 0.10
        if requires_membership:
            score += 0.05
        if terms_text and len(terms_text) > 100:
            score += 0.10

        return min(round(score, 2), 0.65)