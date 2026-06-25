"""
generate_quality_report.py — post-pipeline quality and health check.

Reads all_promotions.json and the Flutter asset folder, then appends an
8-section quality report to the most recent pipeline log.

Run AFTER: generate_scores.py, download_logos.py, and asset copy in
run_nightly.ps1 — so all final data is in place.

Sections:
  1. App Asset Health Check
  2. Visible Deal Counts
  3. Quality Warnings
  4. Fast Redemption Summary
  5. Confidence Summary
  6. Freshness Summary
  7. Top 10 Near Me + Top 10 Online
  8. Parse Failure Detail
  9. Change Since Previous Run
"""
from __future__ import annotations

import json
import re
from collections import Counter
from datetime import date, datetime, timezone
from pathlib import Path

ROOT           = Path(__file__).resolve().parents[1]
ALL_PROMOS     = ROOT / "all_promotions.json"
FAILED_DIR     = ROOT / "structured_outputs" / "failed"
LOGS_DIR       = ROOT / "logs"
FLUTTER_ASSETS = ROOT.parent / "promo_viewer" / "assets"
LOGOS_SRC      = ROOT / "logos"
METRICS_PATH   = LOGS_DIR / "last_run_metrics.json"

VISIBLE_STATUSES = {"active", "probably_active", "online_only"}
CONFIDENCE_MIN   = 0.65


# ---------------------------------------------------------------------------
# Filters matching Flutter tab logic
# ---------------------------------------------------------------------------

def is_visible(p: dict) -> bool:
    return (
        p.get("status") in VISIBLE_STATUSES
        and (p.get("confidence_score") or 0.0) >= CONFIDENCE_MIN
    )


def is_online(p: dict) -> bool:
    method = p.get("redemption_method") or ""
    scope  = p.get("deal_scope") or ""
    ptype  = p.get("promotion_type") or ""
    if ptype in ("reward", "membership_benefit"):
        return False
    if method == "online":
        return True
    if scope == "online_only" and method in ("show_code", "in_app"):
        return True
    return False


_NEAR_ME_EXCLUDED_CATEGORIES = {"travel", "finance"}

def is_near_me(p: dict) -> bool:
    if is_online(p):
        return False
    if p.get("category") in _NEAR_ME_EXCLUDED_CATEGORIES:
        return False
    return True


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_date(s: str | None) -> date | None:
    if not s:
        return None
    try:
        return date.fromisoformat(str(s)[:10])
    except ValueError:
        return None


def _delta_line(label: str, prev_val, curr_val: int | float, fmt: str = "d") -> str:
    if prev_val is None:
        return f"  {label}: {curr_val}"
    diff = curr_val - prev_val
    sign = "+" if diff >= 0 else ""
    if fmt == "f3":
        return f"  {label}: {curr_val:.3f} ({sign}{diff:.3f})"
    return f"  {label}: {curr_val} ({sign}{int(diff)})"


def _top_n_lines(pool: list[dict], n: int = 10) -> list[str]:
    ranked = sorted(pool, key=lambda x: x.get("global_quality_score") or 0, reverse=True)[:n]
    lines: list[str] = []
    for i, p in enumerate(ranked, 1):
        brand  = p.get("brand") or "?"
        title  = (p.get("promotion_title") or "")[:48]
        score  = p.get("global_quality_score") or 0
        conf   = p.get("confidence_score") or 0
        fr     = p.get("fast_redemption") or {}
        action = fr.get("button_label") or fr.get("action_type") or "—"
        lines.append(f"  {i:2}. {brand} | {title} | score {score:.0f} | conf {conf:.2f} | {action}")
    return lines


def _write_to_log(log_path: Path | None, lines: list[str]) -> None:
    if log_path is None:
        return
    with open(log_path, "a", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    logs = sorted(LOGS_DIR.glob("pipeline_*.log"))
    log_path = logs[-1] if logs else None

    out_lines: list[str] = []

    def out(s: str = "") -> None:
        out_lines.append(s)
        print(s)

    # ── Load data ────────────────────────────────────────────────────────────

    if not ALL_PROMOS.exists():
        out("[ERROR] all_promotions.json not found — quality report skipped")
        _write_to_log(log_path, out_lines)
        return

    data       = json.loads(ALL_PROMOS.read_text(encoding="utf-8"))
    all_promos = data.get("promotions", []) if isinstance(data, dict) else data
    visible    = [p for p in all_promos if is_visible(p)]
    today      = date.today()

    # ── 1. App Asset Health Check ────────────────────────────────────────────

    out()
    out("=" * 60)
    out("  APP ASSET HEALTH CHECK")
    out("=" * 60)

    asset_checks = {
        "all_promotions.json":  FLUTTER_ASSETS / "all_promotions.json",
        "brand_locations.json": FLUTTER_ASSETS / "brand_locations.json",
        "user_memberships.json":FLUTTER_ASSETS / "user_memberships.json",
        "brand_affinity.json":  FLUTTER_ASSETS / "brand_affinity.json",
    }
    for name, path in asset_checks.items():
        status = "OK" if path.exists() and path.stat().st_size > 64 else "MISSING"
        out(f"  {name}: {status}")

    logos_src_n = len(list(LOGOS_SRC.glob("*.png"))) if LOGOS_SRC.exists() else 0
    logos_dst   = FLUTTER_ASSETS / "logos"
    logos_dst_n = len(list(logos_dst.glob("*.png"))) if logos_dst.exists() else 0
    logos_ok    = logos_dst_n >= logos_src_n * 0.8
    out(f"  logos copied: {logos_dst_n} / {logos_src_n}  [{'OK' if logos_ok else 'LOW'}]")

    all_assets_ok = all(p.exists() and p.stat().st_size > 64 for p in asset_checks.values())
    out(f"  Flutter asset copy: {'SUCCESS' if all_assets_ok else 'FAILED'}")

    # ── 2. Visible Deal Counts ────────────────────────────────────────────────

    out()
    out("=" * 60)
    out("  VISIBLE DEAL COUNTS  (status active/probably_active/online_only, conf >= 0.65)")
    out("=" * 60)

    fr_eligible = sum(1 for p in visible if (p.get("fast_redemption") or {}).get("eligible"))
    has_score   = sum(1 for p in visible if p.get("global_quality_score") is not None)
    miss_title  = sum(1 for p in visible if not (p.get("promotion_title") or "").strip())
    miss_url    = sum(1 for p in visible if not (p.get("source_url") or "").strip())
    miss_brand  = sum(1 for p in visible if not (p.get("brand") or "").strip())

    out(f"  Visible deals after confidence filter : {len(visible)}")
    out(f"  Deals with fast_redemption eligible   : {fr_eligible}")
    out(f"  Deals with global_quality_score            : {has_score}")
    out(f"  Deals missing title                   : {miss_title}")
    out(f"  Deals missing source_url              : {miss_url}")
    out(f"  Deals missing brand                   : {miss_brand}")

    # ── 3. Quality Warnings ──────────────────────────────────────────────────

    warnings: list[str] = []

    expired_visible = [
        p for p in visible
        if _parse_date(p.get("end_date")) and _parse_date(p["end_date"]) < today  # type: ignore[arg-type]
    ]
    if expired_visible:
        warnings.append(f"  - {len(expired_visible)} visible deal(s) have already expired")

    if miss_url:
        warnings.append(f"  - {miss_url} deal(s) missing source_url")

    no_fast = sum(1 for p in visible if not (p.get("fast_redemption") or {}).get("eligible"))
    if no_fast:
        warnings.append(f"  - {no_fast} deal(s) have no fast redeem action")

    top20 = sorted(visible, key=lambda x: x.get("global_quality_score") or 0, reverse=True)[:20]
    low_conf_top = [p for p in top20 if (p.get("confidence_score") or 0) < 0.75]
    if low_conf_top:
        warnings.append(f"  - {len(low_conf_top)} of the top-20 ranked deals have confidence < 0.75")

    out()
    out("=" * 60)
    out("  QUALITY WARNINGS")
    out("=" * 60)
    out(f"  High-priority warnings: {len(warnings)}")
    for w in warnings:
        out(w)

    # ── 4. Fast Redemption Distribution ─────────────────────────────────────

    out()
    out("=" * 60)
    out("  FAST REDEMPTION SUMMARY")
    out("=" * 60)

    fr_dist: Counter = Counter()
    for p in visible:
        fr = p.get("fast_redemption") or {}
        if fr.get("eligible"):
            fr_dist[fr.get("action_type", "unknown")] += 1
        else:
            fr_dist["not_supported"] += 1

    for action, count in fr_dist.most_common():
        out(f"  {action}: {count}")

    # ── 5. Confidence Summary ────────────────────────────────────────────────

    out()
    out("=" * 60)
    out("  CONFIDENCE SUMMARY")
    out("=" * 60)

    conf_90  = sum(1 for p in visible if (p.get("confidence_score") or 0) >= 0.90)
    conf_80  = sum(1 for p in visible if 0.80 <= (p.get("confidence_score") or 0) < 0.90)
    conf_65  = sum(1 for p in visible if 0.65 <= (p.get("confidence_score") or 0) < 0.80)
    conf_drop= sum(1 for p in all_promos if (p.get("confidence_score") or 0) < CONFIDENCE_MIN)

    out(f"  >= 0.90        : {conf_90}")
    out(f"  0.80-0.89      : {conf_80}")
    out(f"  0.65-0.79      : {conf_65}")
    out(f"  < 0.65 dropped : {conf_drop}")

    # ── 6. Freshness / Expiry Summary ────────────────────────────────────────

    out()
    out("=" * 60)
    out("  FRESHNESS SUMMARY")
    out("=" * 60)

    s_active  = sum(1 for p in visible if p.get("status") == "active")
    s_prob    = sum(1 for p in visible if p.get("status") == "probably_active")
    s_online  = sum(1 for p in visible if p.get("status") == "online_only")
    exp_today = 0
    exp_3d    = 0
    no_exp    = 0

    for p in visible:
        d = _parse_date(p.get("end_date"))
        if d is None:
            no_exp += 1
        elif d == today:
            exp_today += 1
        elif 0 < (d - today).days <= 3:
            exp_3d += 1

    s_expired      = sum(1 for p in all_promos if p.get("status") == "expired")
    s_needs_review = sum(1 for p in all_promos if p.get("status") == "needs_review")

    out(f"  Active                : {s_active}")
    out(f"  Probably active       : {s_prob}")
    out(f"  Online only           : {s_online}")
    out(f"  Expires today         : {exp_today}")
    out(f"  Expires within 3 days : {exp_3d}")
    out(f"  No expiry found       : {no_exp}")
    out(f"  Expired (hidden)      : {s_expired}")
    out(f"  Needs review (hidden) : {s_needs_review}")

    # ── 7. Top 10 Near Me + Top 10 Online ────────────────────────────────────

    near_me_pool = [p for p in visible if is_near_me(p)]
    online_pool  = [p for p in visible if is_online(p)]

    out()
    out("=" * 60)
    out(f"  TOP 10 NEAR ME  ({len(near_me_pool)} eligible deals)")
    out("=" * 60)
    for line in _top_n_lines(near_me_pool):
        out(line)

    out()
    out("=" * 60)
    out(f"  TOP 10 ONLINE  ({len(online_pool)} eligible deals)")
    out("=" * 60)
    for line in _top_n_lines(online_pool):
        out(line)

    # ── 8. Parse Failure Detail ──────────────────────────────────────────────
    # Only show failures that appear in the CURRENT pipeline log, not all
    # historical failures sitting in structured_outputs/failed/.

    failed_details: list[tuple[str, str]] = []

    if log_path and log_path.exists():
        log_text = log_path.read_text(encoding="utf-8", errors="replace")
        # Lines like: [FAILED] Hilton: C:\...\failed\hilton.json
        current_failed_brands = re.findall(r"^\[FAILED\] (.+?):", log_text, re.MULTILINE)

        # For each brand that failed this run, look up the error in the JSON
        slugified = {
            re.sub(r"[^a-z0-9]", "_", b.lower()).strip("_"): b
            for b in current_failed_brands
        }

        for slug, brand in slugified.items():
            # Try exact file match, then fuzzy
            candidates = list(FAILED_DIR.glob(f"{slug}.json")) if FAILED_DIR.exists() else []
            if not candidates and FAILED_DIR.exists():
                candidates = [
                    f for f in FAILED_DIR.glob("*.json")
                    if slug in f.stem or f.stem in slug
                ]
            if candidates:
                try:
                    fd = json.loads(candidates[0].read_text(encoding="utf-8"))
                    error = str(fd.get("error") or "unknown error")
                except Exception:
                    error = "could not read error file"
            else:
                error = "error file not found"

            if "timed out" in error.lower():
                reason = "LLM timeout"
            elif "invalid json" in error.lower() or "json decode" in error.lower():
                reason = "invalid JSON from LLM"
            elif "no concrete" in error.lower() or "no promotion" in error.lower():
                reason = "no concrete promotion extracted"
            elif "pydantic" in error.lower() or "validation" in error.lower():
                reason = "LLM output failed validation"
            elif "404" in error:
                reason = "Ollama model not found (404)"
            elif "connection" in error.lower():
                reason = "connection error"
            elif "valid json" in error.lower():
                reason = "invalid JSON from LLM"
            elif "could not extract" in error.lower() or "promotions list" in error.lower():
                reason = "LLM returned no promotions list"
            else:
                reason = error.replace('\n', ' ')[:120]

            failed_details.append((brand, reason))

    if failed_details:
        out()
        out("=" * 60)
        out(f"  PARSE FAILURES  ({len(failed_details)} brands this run)")
        out("=" * 60)
        for brand, reason in failed_details:
            out(f"  {brand}: {reason}")

    # ── 9. Change Since Previous Run ─────────────────────────────────────────

    avg_conf = (
        round(sum((p.get("confidence_score") or 0) for p in visible) / len(visible), 3)
        if visible else 0.0
    )

    current_metrics = {
        "date": today.isoformat(),
        "visible": len(visible),
        "near_me": len(near_me_pool),
        "online": len(online_pool),
        "fast_redeem_eligible": fr_eligible,
        "avg_confidence": avg_conf,
    }

    out()
    out("=" * 60)
    out("  CHANGE SINCE PREVIOUS RUN")
    out("=" * 60)

    if METRICS_PATH.exists():
        prev = json.loads(METRICS_PATH.read_text(encoding="utf-8"))
        prev_date = prev.get("date", "?")
        out(f"  Previous run: {prev_date}")
        out(_delta_line("Total visible deals", prev.get("visible"),    len(visible)))
        out(_delta_line("Near Me deals",       prev.get("near_me"),    len(near_me_pool)))
        out(_delta_line("Online deals",        prev.get("online"),     len(online_pool)))
        out(_delta_line("Fast redeem eligible",prev.get("fast_redeem_eligible"), fr_eligible))
        out(_delta_line("Average confidence",  prev.get("avg_confidence"), avg_conf, fmt="f3"))

        prev_visible = prev.get("visible") or 0
        if prev_visible > 0 and len(visible) < prev_visible * 0.70:
            out()
            out("  !! WARNING: visible deals dropped >30% vs last run !!")
            out("  !! Review before deploying to Flutter assets.        !!")
    else:
        out("  (no previous run - first quality report)")

    METRICS_PATH.write_text(json.dumps(current_metrics, indent=2), encoding="utf-8")

    out()
    out("=" * 60)
    out()

    _write_to_log(log_path, out_lines)


if __name__ == "__main__":
    main()
