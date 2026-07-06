from __future__ import annotations

from typing import Any, List, Literal, Optional
from pydantic import BaseModel, Field, field_validator


PromotionType = Literal[
    "reward",
    "app_offer",
    "sale",
    "coupon",
    "birthday_reward",
    "membership_benefit",
    "unknown",
]

EmailVisibility = Literal[
    "public_general_offer",
    "member_offer",
    "private_user_offer",
    "unknown",
]

DiscountType = Literal[
    "percentage_off",
    "amount_off",
    "free_item",
    "free_shipping",
    "points",
    "sale_price",
    "unknown",
]

RedemptionMethod = Literal[
    "in_app",
    "in_store",
    "online",
    "show_code",
    "scan_barcode",
    "unknown",
]

DealScope = Literal[
    "brand_level",
    "location_specific",
    "online_only",
    "unknown",
]

FrictionLevel = Literal[
    "low",
    "medium",
    "high",
    "unknown",
]

ExtractionStatus = Literal[
    "success",
    "no_offer_found",
    "failed",
]


class StoreLocation(BaseModel):
    osm_id: Optional[str] = None
    name: str
    address: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    zip: Optional[str] = None
    lat: float
    lng: float
    phone: Optional[str] = None


class Promotion(BaseModel):
    brand: str
    category: Optional[str] = None

    promotion_title: Optional[str] = None
    short_summary: Optional[str] = None
    promotion_type: PromotionType = "unknown"

    discount_type: DiscountType = "unknown"
    discount_value: Optional[str] = None

    requires_membership: bool = False
    membership_name: Optional[str] = None
    membership_cost: Optional[Literal["free", "unknown"]] = None

    requires_app: bool = False
    requires_account_login: bool = False

    new_user_only: bool = False
    birthday_related: bool = False

    start_date: Optional[str] = None
    end_date: Optional[str] = None
    valid_days: List[str] = Field(default_factory=list)
    time_start: Optional[str] = None
    time_end: Optional[str] = None
    timezone: str = "America/New_York"

    redemption_method: RedemptionMethod = "unknown"
    redemption_steps: List[str] = Field(default_factory=list)

    @field_validator("redemption_steps", "valid_days", mode="before")
    @classmethod
    def coerce_str_list(cls, v: Any) -> Any:
        if not isinstance(v, list):
            return v
        result = []
        for item in v:
            if isinstance(item, str):
                result.append(item)
            elif isinstance(item, dict):
                val = next(iter(item.values()), None)
                if val and isinstance(val, str):
                    result.append(val)
        return result

    promo_code: Optional[str] = None
    terms_text: Optional[str] = None
    minimum_spend: Optional[str] = None
    purchase_required: bool = False

    deal_scope: DealScope = "unknown"

    friction_level: FrictionLevel = "unknown"
    friction_reasons: List[str] = Field(default_factory=list)

    confidence_score: float = Field(default=0.0, ge=0.0, le=1.0)

    source_type: Literal["web_page", "email", "unknown"] = "web_page"
    source_path: str

    extraction_status: ExtractionStatus = "success"
    notes: List[str] = Field(default_factory=list)

    target_gender: Optional[Literal["women", "men", "kids", "unisex"]] = None

    # Synthesis metadata — only populated by the price-grid synthesizer
    synthesized: bool = False
    synthesis_reason: Optional[str] = None
    product_categories: List[str] = Field(default_factory=list)
    product_keywords: List[str] = Field(default_factory=list)
    matched_product_examples: List[str] = Field(default_factory=list)

    # Email-only fields
    visibility: Optional[EmailVisibility] = None
    sender_email: Optional[str] = None
    email_subject: Optional[str] = None
    email_date: Optional[str] = None