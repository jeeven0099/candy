from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from local_model_interface import LocalModelInterface, RuleBasedLocalModel
from models import Promotion


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = PROJECT_ROOT / "structured_outputs"
FAILED_DIR = OUTPUT_DIR / "failed"


def slugify(value: str) -> str:
    value = value.lower().strip()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    return value.strip("_") or "unknown"


def get_model(
    model_type: str = "rule_based",
    ollama_model: str = "llama3.1:8b",
    ollama_host: str = "http://localhost:11434",
    ollama_timeout: int = 600,
    groq_model: str = "llama-3.3-70b-versatile",
    groq_api_key: Optional[str] = None,
    cloud_timeout: int = 120,
) -> LocalModelInterface:
    if model_type == "ollama":
        from ollama_model import OllamaModel
        return OllamaModel(
            model_name=ollama_model,
            host=ollama_host,
            timeout=ollama_timeout,
        )
    if model_type == "groq":
        from cloud_model import GroqModel
        return GroqModel(
            model_name=groq_model,
            api_key=groq_api_key,
            timeout=cloud_timeout,
        )
    return RuleBasedLocalModel()


def parse_text_file(
    input_path: Path,
    brand: str,
    category: Optional[str] = None,
    model_type: str = "rule_based",
    ollama_model: str = "llama3.1:8b",
    ollama_host: str = "http://localhost:11434",
    ollama_timeout: int = 600,
    groq_model: str = "llama-3.3-70b-versatile",
    groq_api_key: Optional[str] = None,
    cloud_timeout: int = 120,
) -> List[Promotion]:
    text = input_path.read_text(encoding="utf-8", errors="replace")

    model = get_model(
        model_type=model_type,
        ollama_model=ollama_model,
        ollama_host=ollama_host,
        ollama_timeout=ollama_timeout,
        groq_model=groq_model,
        groq_api_key=groq_api_key,
        cloud_timeout=cloud_timeout,
    )

    return model.parse_text(
        text=text,
        brand=brand,
        category=category,
        source_path=str(input_path),
    )


def save_promotions_json(promotions: List[Promotion], brand: str, input_path: Path) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    brand_slug = slugify(brand)
    output_path = OUTPUT_DIR / f"{brand_slug}.json"

    payload = {
        "brand": brand,
        "source_path": str(input_path),
        "last_updated": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "promotion_count": len(promotions),
        "promotions": [p.model_dump(mode="json") for p in promotions],
    }

    with output_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)

    return output_path


def save_failed_output(
    raw_data: object,
    brand: str,
    input_path: Path,
    error: Exception,
) -> Path:
    FAILED_DIR.mkdir(parents=True, exist_ok=True)

    brand_slug = slugify(brand)
    failed_path = FAILED_DIR / f"{brand_slug}.json"

    payload = {
        "brand": brand,
        "input_path": str(input_path),
        "last_updated": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "error": str(error),
        "raw_data": raw_data,
    }

    with failed_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)

    return failed_path