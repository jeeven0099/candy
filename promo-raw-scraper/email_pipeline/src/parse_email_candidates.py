"""
parse_email_candidates.py — LLM extraction for email candidates.

Reads logs/email_candidates.csv, calls Ollama for each email, outputs:
  structured_outputs/email/{brand_slug}_{hash8}.json   — promotions
  logs/user_memberships.json                            — detected memberships
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

_SRC = Path(__file__).resolve().parents[2] / "src"
sys.path.insert(0, str(_SRC))

from ollama_model import OllamaModel  # noqa: E402
from local_model_interface import RuleBasedLocalModel  # noqa: E402
from models import Promotion  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CANDIDATES_CSV = ROOT / "logs" / "email_candidates.csv"
STRUCTURED_DIR = ROOT / "structured_outputs" / "email"
MEMBERSHIPS_FILE = ROOT / "logs" / "user_memberships.json"
BRAND_AFFINITY_FILE = ROOT / "logs" / "brand_affinity.json"

# Visibilities that warrant full Ollama extraction
_OLLAMA_VISIBILITIES = {"private_user_offer", "member_offer"}

# Suffixes that make a program name generic when the remainder equals the brand
_GENERIC_SUFFIXES = re.compile(
    r'\s+(?:rewards?|program|membership|points?|club|perks?|card|pass|plus|insider)\s*$',
    re.IGNORECASE,
)


def _is_generic_program(brand: str, program: str) -> bool:
    """Return True when program is just '{brand} Rewards' or similar filler name."""
    brand_words = re.sub(r'[^a-z0-9]', ' ', brand.lower()).split()
    stripped = _GENERIC_SUFFIXES.sub('', program.strip())
    prog_words = re.sub(r'[^a-z0-9]', ' ', stripped.lower()).split()
    return prog_words == brand_words


# Known loyalty program suffixes — strict enough to avoid marketing copy
_MEMBERSHIP_PROGRAMS = re.compile(
    r"\b([A-Z][A-Za-z&']{1,20}(?:\s[A-Za-z&']{1,20}){0,3}"
    r"\s(?:Rewards?|Insider|Circle|One|Club|Plus\s*(?:Card)?|Perks|Stubs|ExtraCare|myWalgreens|SkyMiles|AAdvantage|MileagePlus|TrueBlue|Rapid\sRewards|Ultamate\sRewards))\b",
)


def slugify(value: str) -> str:
    value = value.lower().strip()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    return value.strip("_") or "unknown"


def load_candidates(csv_path: Path, brand_filter: Optional[str]) -> list[dict]:
    with csv_path.open("r", encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    if brand_filter:
        rows = [r for r in rows if brand_filter.lower() in r.get("brand", "").lower()]
    return rows


def detect_memberships(brand: str, subject: str, text: str, sent_at: str) -> list[dict]:
    """Rule-based membership detection from email content."""
    combined = f"{subject}\n{text}"
    found = []
    seen: set[str] = set()
    for m in _MEMBERSHIP_PROGRAMS.finditer(combined):
        prog = m.group("prog").strip()
        if prog not in seen:
            seen.add(prog)
            found.append({
                "brand": brand,
                "program": prog,
                "last_seen": sent_at or datetime.now(timezone.utc).date().isoformat(),
            })
    return found


def load_memberships() -> dict:
    if MEMBERSHIPS_FILE.exists():
        try:
            return json.loads(MEMBERSHIPS_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {"generated_at": "", "memberships": []}


def update_brand_affinity(rows: list[dict]) -> None:
    """Record every brand that appears in the inbox regardless of deal quality."""
    data: dict = {}
    if BRAND_AFFINITY_FILE.exists():
        try:
            data = json.loads(BRAND_AFFINITY_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass

    brands: dict = data.get("brands", {})
    for row in rows:
        brand = row.get("brand", "").strip()
        sent_at = row.get("sent_at", "")
        if not brand:
            continue
        entry = brands.get(brand, {"email_count": 0, "last_seen": ""})
        entry["email_count"] = entry.get("email_count", 0) + 1
        if sent_at > entry.get("last_seen", ""):
            entry["last_seen"] = sent_at
        brands[brand] = entry

    data["brands"] = dict(sorted(brands.items()))
    data["generated_at"] = datetime.now(timezone.utc).isoformat()
    BRAND_AFFINITY_FILE.write_text(
        json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8"
    )


def extract_memberships_from_structured() -> list[dict]:
    """Pull clean membership_name values from Ollama-extracted email promotions."""
    found = []
    seen: set[str] = set()
    for path in STRUCTURED_DIR.glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            brand = data.get("brand", "")
            for promo in data.get("promotions", []):
                if not promo.get("requires_membership"):
                    continue
                name = (promo.get("membership_name") or "").strip()
                sent_at = promo.get("email_date") or ""
                if name and name not in seen and len(name) > 3:
                    # Skip generic placeholder names and "{brand} Rewards"-style fillers
                    if any(bad in name.lower() for bad in ("unknown", "n/a", "yes", "membership", "rewards program")):
                        continue
                    if _is_generic_program(brand, name):
                        continue
                    seen.add(name)
                    found.append({
                        "brand": brand,
                        "program": name,
                        "last_seen": sent_at,
                        "source": "llm_extracted",
                    })
        except Exception:
            pass
    return found


def save_memberships(new_entries: list[dict]) -> None:
    data = load_memberships()
    existing = {m["program"]: m for m in data["memberships"]}
    for entry in new_entries:
        prog = entry["program"]
        if prog not in existing or entry["last_seen"] > existing[prog].get("last_seen", ""):
            existing[prog] = entry
    data["memberships"] = sorted(existing.values(), key=lambda x: x["brand"])
    data["generated_at"] = datetime.now(timezone.utc).isoformat()
    MEMBERSHIPS_FILE.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def build_email_prompt(row: dict, text: str) -> str:
    """Augment the Ollama prompt with email-specific context."""
    subject = row.get("subject", "")
    sender = row.get("sender_email", "")
    visibility = row.get("visibility", "unknown")
    brand = row.get("brand", "")
    return (
        f"Email subject: {subject}\n"
        f"From: {sender}\n"
        f"Visibility: {visibility}\n"
        f"Brand: {brand}\n\n"
        f"This is a promotional email. Extract all deals.\n"
        f"Set source_type to 'email'.\n"
        f"Set visibility to '{visibility}' on every extracted promotion.\n"
        f"If visibility is 'private_user_offer', set confidence_score >= 0.85 "
        f"only when a concrete offer (code, discount, free item) is present.\n\n"
        f"--- EMAIL TEXT ---\n{text[:5000]}\n--- END ---"
    )


class EmailOllamaModel(OllamaModel):
    """Ollama model with an email-specific prompt prefix."""

    def _build_prompt(self, text: str, brand: str, category, source_path: str) -> str:
        # text already contains the email prefix injected by parse_row
        return super()._build_prompt(text, brand, category, source_path)


def parse_row(
    row: dict,
    model: OllamaModel,
    rule_model: RuleBasedLocalModel,
    force: bool,
) -> tuple[list[Promotion], list[dict]]:
    brand = row.get("brand", "Unknown")
    text_path = ROOT / row.get("text_path", "")
    if not text_path.exists():
        return [], []

    raw_text = text_path.read_text(encoding="utf-8", errors="replace")
    visibility = row.get("visibility", "public_general_offer")

    if visibility in _OLLAMA_VISIBILITIES:
        # Full LLM extraction for personal/member deals
        email_prefix = build_email_prompt(row, raw_text)
        promotions = model.parse_text(
            text=email_prefix, brand=brand, category=None, source_path=str(text_path),
        )
    else:
        # Fast rule-based extraction for public emails
        promotions = rule_model.parse_text(
            text=raw_text, brand=brand, category=None, source_path=str(text_path),
        )

    # Stamp email metadata onto each promotion
    visibility = row.get("visibility", "unknown")
    subject = row.get("subject", "")
    sender_email = row.get("sender_email", "")
    sent_at = row.get("sent_at", "")
    for p in promotions:
        p.visibility = visibility  # type: ignore[attr-defined]
        p.sender_email = sender_email  # type: ignore[attr-defined]
        p.email_subject = subject  # type: ignore[attr-defined]
        p.email_date = sent_at  # type: ignore[attr-defined]

    memberships = detect_memberships(brand, subject, raw_text, sent_at)
    return promotions, memberships


def save_structured(brand: str, content_hash: str, text_path: str, promotions: list[Promotion]) -> Path:
    STRUCTURED_DIR.mkdir(parents=True, exist_ok=True)
    fname = f"{slugify(brand)}_{content_hash[:8]}.json"
    out_path = STRUCTURED_DIR / fname
    payload = {
        "brand": brand,
        "source_path": text_path,
        "last_updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "promotion_count": len(promotions),
        "promotions": [p.model_dump(mode="json") for p in promotions],
    }
    out_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    return out_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Parse email candidates with Ollama.")
    parser.add_argument("--csv", default=str(CANDIDATES_CSV))
    parser.add_argument("--limit", type=int, default=999)
    parser.add_argument("--ollama-model", default="qwen2.5:14b")
    parser.add_argument("--ollama-host", default="http://localhost:11434")
    parser.add_argument("--ollama-timeout", type=int, default=3600)
    parser.add_argument("--brand", type=str, default=None)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    csv_path = Path(args.csv)
    if not csv_path.exists():
        raise FileNotFoundError(f"Candidates CSV not found: {csv_path}")

    rows = load_candidates(csv_path, args.brand)[:args.limit]
    ollama_model = OllamaModel(
        model_name=args.ollama_model,
        host=args.ollama_host,
        timeout=args.ollama_timeout,
    )
    rule_model = RuleBasedLocalModel()

    # Always update brand affinity from all candidates regardless of visibility
    update_brand_affinity(rows)

    ollama_rows = [r for r in rows if r.get("visibility") in _OLLAMA_VISIBILITIES]
    public_rows = [r for r in rows if r.get("visibility") not in _OLLAMA_VISIBILITIES]
    print(f"Routing: {len(ollama_rows)} via Ollama, {len(public_rows)} via rule-based")

    parsed_count = skipped = failed = 0
    all_memberships: list[dict] = []

    for row in rows:
        brand = row.get("brand", "Unknown")
        content_hash = row.get("content_hash", "unknown")
        out_path = STRUCTURED_DIR / f"{slugify(brand)}_{content_hash[:8]}.json"

        if not args.force and out_path.exists():
            print(f"[SKIP] {brand}: already parsed")
            skipped += 1
            continue

        try:
            promotions, memberships = parse_row(row, ollama_model, rule_model, args.force)
            all_memberships.extend(memberships)
            saved = save_structured(brand, content_hash, row.get("text_path", ""), promotions)
            method = "LLM" if row.get("visibility") in _OLLAMA_VISIBILITIES else "rules"
            print(f"[OK] {brand} ({len(promotions)} deals) [{method}]: {saved.name}")
            parsed_count += 1
        except Exception as e:
            print(f"[RETRY] {brand}: {type(e).__name__}, retrying...")
            time.sleep(5)
            try:
                promotions, memberships = parse_row(row, ollama_model, rule_model, args.force)
                all_memberships.extend(memberships)
                saved = save_structured(brand, content_hash, row.get("text_path", ""), promotions)
                print(f"[OK] {brand} [retry]: {saved.name}")
                parsed_count += 1
            except Exception as e2:
                print(f"[FAILED] {brand}: {e2}")
                failed += 1

    # Combine regex-detected memberships with clean LLM-extracted ones
    llm_memberships = extract_memberships_from_structured()
    all_memberships.extend(llm_memberships)

    if all_memberships:
        save_memberships(all_memberships)
        print(f"\nDetected {len(all_memberships)} membership signals -> {MEMBERSHIPS_FILE}")

    print(f"\nParsed: {parsed_count}  Skipped: {skipped}  Failed: {failed}")


if __name__ == "__main__":
    main()
