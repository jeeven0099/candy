from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from typing import Any

import requests


DEFAULT_PERSONAL_RANK_MODEL = "heuristic"


@dataclass(frozen=True)
class PersonalRankResult:
    score: float
    reasons: list[str]
    summary: str
    model_name: str


def _norm(value: str | None) -> str:
    return (value or "").strip().lower()


def _as_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(v) for v in value if str(v).strip()]
    if isinstance(value, str) and value.strip():
        try:
            decoded = json.loads(value)
            if isinstance(decoded, list):
                return [str(v) for v in decoded if str(v).strip()]
        except json.JSONDecodeError:
            return [value]
    return []


def _clamp_score(value: float) -> float:
    return round(max(0.0, min(100.0, value)), 1)


class PersonalEmailRanker:
    """Scores extracted email deals for one user.

    The default path is deterministic and model-free. A model can be opted into
    later by passing an OpenRouter model name such as google/gemini-2.5-flash.
    """

    def __init__(
        self,
        model_name: str | None = None,
        api_key: str | None = None,
        timeout: int = 45,
    ) -> None:
        self.model_name = model_name or os.getenv(
            "EMAIL_RANKER_MODEL",
            DEFAULT_PERSONAL_RANK_MODEL,
        )
        self.api_key = api_key or os.getenv("OPENROUTER_API_KEY", "")
        self.timeout = timeout

    def rank(self, promo: dict[str, Any], user_profile: dict[str, Any]) -> PersonalRankResult:
        if self.model_name != "heuristic" and self.api_key:
            try:
                return self._rank_with_openrouter(promo, user_profile)
            except Exception as exc:
                fallback = self._rank_heuristic(promo, user_profile)
                return PersonalRankResult(
                    score=fallback.score,
                    reasons=[*fallback.reasons, "model_fallback"],
                    summary=f"Model fallback used: {type(exc).__name__}",
                    model_name=f"heuristic_after_{self.model_name}",
                )
        return self._rank_heuristic(promo, user_profile)

    def _rank_with_openrouter(
        self,
        promo: dict[str, Any],
        user_profile: dict[str, Any],
    ) -> PersonalRankResult:
        prompt = {
            "task": (
                "Score whether this extracted promotional email deal should be "
                "shown to this specific Candy user. Return JSON only."
            ),
            "score_scale": "0 means hide; 100 means excellent fit and high value",
            "user": {
                "favorite_brands": user_profile.get("favorite_brands", []),
                "favorite_categories": user_profile.get("favorite_categories", []),
                "deal_priorities": user_profile.get("deal_priorities", []),
                "hidden_brands": user_profile.get("hidden_brands", []),
                "brand_affinity": user_profile.get("brand_affinity", [])[:20],
                "category_affinity": user_profile.get("category_affinity", [])[:20],
            },
            "deal": {
                "brand": promo.get("brand"),
                "category": promo.get("category"),
                "title": promo.get("promotion_title"),
                "summary": promo.get("short_summary"),
                "discount_type": promo.get("discount_type"),
                "discount_value": promo.get("discount_value"),
                "global_quality_score": promo.get("global_quality_score"),
                "economic_value_score": promo.get("economic_value_score"),
                "requires_membership": promo.get("requires_membership"),
                "visibility": promo.get("visibility"),
                "email_subject": promo.get("email_subject"),
                "sender_email": promo.get("sender_email"),
            },
            "return_schema": {
                "score": "number 0-100",
                "reasons": ["short_snake_case_reason"],
                "summary": "one short sentence",
            },
        }

        response = requests.post(
            "https://openrouter.ai/api/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
                "HTTP-Referer": "https://github.com/jeeven0099/candy",
                "X-Title": "Candy email ranker",
            },
            json={
                "model": self.model_name,
                "messages": [{"role": "user", "content": json.dumps(prompt)}],
                "response_format": {"type": "json_object"},
                "max_tokens": 500,
                "temperature": 0.1,
            },
            timeout=self.timeout,
        )
        response.raise_for_status()
        raw = response.json()["choices"][0]["message"]["content"] or "{}"
        data = json.loads(raw)
        return PersonalRankResult(
            score=_clamp_score(float(data.get("score") or 0)),
            reasons=_as_list(data.get("reasons"))[:8],
            summary=str(data.get("summary") or "")[:240],
            model_name=self.model_name,
        )

    def _rank_heuristic(
        self,
        promo: dict[str, Any],
        user_profile: dict[str, Any],
    ) -> PersonalRankResult:
        brand = _norm(promo.get("brand"))
        category = _norm(promo.get("category"))
        title = _norm(promo.get("promotion_title"))
        dtype = _norm(promo.get("discount_type"))
        visibility = _norm(promo.get("visibility"))

        favorites = {_norm(v) for v in user_profile.get("favorite_brands", [])}
        categories = {_norm(v) for v in user_profile.get("favorite_categories", [])}
        priorities = {_norm(v) for v in user_profile.get("deal_priorities", [])}
        hidden = {_norm(v) for v in user_profile.get("hidden_brands", [])}

        score = float(promo.get("global_quality_score") or 0)
        if not score:
            score = 45 + float(promo.get("confidence_score") or 0) * 25

        reasons: list[str] = []
        if brand in hidden:
            return PersonalRankResult(0.0, ["hidden_brand"], "Hidden by user settings.", "heuristic")

        if brand in favorites:
            score += 20
            reasons.append("favorite_brand")
        if category in categories:
            score += 12
            reasons.append("favorite_category")

        brand_affinity = user_profile.get("brand_affinity", [])
        for row in brand_affinity:
            if _norm(row.get("brand")) == brand:
                score += min(float(row.get("affinity_score") or 0) / 8.0, 14.0)
                reasons.append("brand_affinity")
                break

        category_affinity = user_profile.get("category_affinity", [])
        for row in category_affinity:
            if _norm(row.get("category")) == category:
                score += min(float(row.get("affinity_score") or 0) / 10.0, 10.0)
                reasons.append("category_affinity")
                break

        if visibility == "private_user_offer":
            score += 9
            reasons.append("private_email_offer")
        elif visibility == "member_offer":
            score += 6
            reasons.append("member_email_offer")

        if dtype == "free_item":
            score += 8
            reasons.append("free_item")
        if "free" in priorities and dtype == "free_item":
            score += 8
            reasons.append("matches_free_priority")
        if "discount" in priorities and dtype in {"percentage_off", "amount_off", "sale_price"}:
            score += 6
            reasons.append("matches_discount_priority")
        if "bogo" in priorities and re.search(r"\bbogo\b|buy one get one", title):
            score += 7
            reasons.append("matches_bogo_priority")

        if dtype == "points" and brand not in favorites:
            score -= 10
            reasons.append("points_without_affinity")
        if promo.get("requires_membership") and visibility != "member_offer":
            score -= 5
            reasons.append("membership_required")
        if "newsletter" in title or "sign up" in title:
            score -= 12
            reasons.append("newsletter_like")

        score = _clamp_score(score)
        if not reasons:
            reasons.append("deal_quality")

        summary = "Personal fit scored from preferences, affinity, and email-specific value."
        return PersonalRankResult(score, reasons[:8], summary, "heuristic")
