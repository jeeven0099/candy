#!/usr/bin/env python3
"""
analytics_dashboard.py — Candy Analytics Dashboard

Fetches user_interactions from Supabase and renders a local HTML report.

Find your service_role key:
  Supabase Dashboard → Settings → API → service_role (secret) key

Usage:
  python analytics_dashboard.py --key <service_role_key>
  python analytics_dashboard.py          # reads SUPABASE_SERVICE_KEY from .env
  python analytics_dashboard.py --days 7
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import webbrowser
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx

SUPABASE_URL = "https://liwncnxxsxbgijfgchdy.supabase.co"
ROOT = Path(__file__).resolve().parents[1]
OUT  = ROOT / "logs" / "analytics_dashboard.html"

# ── Env ───────────────────────────────────────────────────────────────────────

def _load_env() -> None:
    for path in [ROOT / ".env", ROOT.parent / ".env"]:
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            os.environ.setdefault(k.strip(), v.strip())

# ── Fetch ─────────────────────────────────────────────────────────────────────

def fetch_all(key: str) -> list[dict]:
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Accept": "application/json",
    }
    rows: list[dict] = []
    offset, limit = 0, 1000
    with httpx.Client(verify=False, timeout=30) as client:
        while True:
            r = client.get(
                f"{SUPABASE_URL}/rest/v1/user_interactions",
                headers=headers,
                params={
                    "select": "event_type,brand,category,promotion_id,user_id,session_id,created_at,metadata",
                    "order": "created_at.desc",
                    "limit": limit,
                    "offset": offset,
                },
            )
            r.raise_for_status()
            batch = r.json()
            if not batch:
                break
            rows.extend(batch)
            if len(batch) < limit:
                break
            offset += limit
    return rows

# ── Aggregate ─────────────────────────────────────────────────────────────────

def _dt(s: str) -> datetime:
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return datetime.min.replace(tzinfo=timezone.utc)

def _meta(row: dict) -> dict:
    m = row.get("metadata") or {}
    if isinstance(m, str):
        try:
            return json.loads(m)
        except Exception:
            return {}
    return m if isinstance(m, dict) else {}

def aggregate(rows: list[dict], days: int) -> dict:
    now    = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=days)
    last7  = now - timedelta(days=7)

    recent = [r for r in rows if _dt(r.get("created_at", "")) >= cutoff]

    # ── Acquisition ───────────────────────────────────────────────────────────
    active_users = len({r["user_id"] for r in rows if _dt(r.get("created_at","")) >= last7 and r.get("user_id")})
    total_users  = len({r["user_id"] for r in rows if r.get("user_id")})

    sessions_by_day: dict[str, set] = defaultdict(set)
    for r in rows:
        dt = _dt(r.get("created_at", ""))
        if dt >= now - timedelta(days=14) and r.get("session_id"):
            sessions_by_day[dt.strftime("%b %d")].add(r["session_id"])

    sessions_per_day = []
    for i in range(13, -1, -1):
        label = (now - timedelta(days=i)).strftime("%b %d")
        sessions_per_day.append({"day": label, "count": len(sessions_by_day.get(label, set()))})

    avg_sessions = round(sum(s["count"] for s in sessions_per_day[-7:]) / 7, 1)

    # ── Engagement ────────────────────────────────────────────────────────────
    events = Counter(r["event_type"] for r in recent)
    opens   = events["deal_card_opened"]
    saves   = events["deal_saved"]
    redeems = events["redeem_clicked"] + events["fast_redeem_clicked"]
    searches = events["search_submitted"]

    # ── Ranking ───────────────────────────────────────────────────────────────
    tier_order  = ["excellent", "great", "good", "fair", "low", "unscored"]
    effort_order = ["instant", "easy", "code_required", "app_required", "membership_required", "unknown"]

    tier_opens   = Counter()
    tier_redeems = Counter()
    effort_opens = Counter()

    for r in recent:
        m = _meta(r)
        tier   = m.get("value_tier") or "unscored"
        effort = m.get("effort_type") or "unknown"
        if r["event_type"] == "deal_card_opened":
            tier_opens[tier]   += 1
            effort_opens[effort] += 1
        elif r["event_type"] in ("redeem_clicked", "fast_redeem_clicked"):
            tier_redeems[tier] += 1

    # ── Top content ───────────────────────────────────────────────────────────
    brand_opens = Counter(
        r["brand"] for r in recent
        if r["event_type"] == "deal_card_opened" and r.get("brand")
    )
    cat_opens = Counter(
        r["category"] for r in recent
        if r["event_type"] == "deal_card_opened" and r.get("category")
    )
    promo_opens = Counter(
        (r.get("promotion_id",""), r.get("brand",""))
        for r in recent
        if r["event_type"] == "deal_card_opened" and r.get("promotion_id")
    )

    return {
        "days": days,
        "generated_at": now.strftime("%b %d %Y, %H:%M UTC"),
        "total_rows": len(rows),
        # acquisition
        "active_users": active_users,
        "total_users": total_users,
        "avg_sessions": avg_sessions,
        "sessions_per_day": sessions_per_day,
        # engagement
        "opens": opens,
        "saves": saves,
        "redeems": redeems,
        "searches": searches,
        # ranking
        "tier_opens":   {t: tier_opens.get(t, 0) for t in tier_order if tier_opens.get(t, 0) > 0},
        "tier_redeems": {t: tier_redeems.get(t, 0) for t in tier_order if tier_redeems.get(t, 0) > 0},
        "effort_opens": {e: effort_opens.get(e, 0) for e in effort_order if effort_opens.get(e, 0) > 0},
        # top content
        "top_brands":     dict(brand_opens.most_common(10)),
        "top_categories": dict(cat_opens.most_common(8)),
        "top_promos": [
            {"id": k[0], "brand": k[1], "opens": v}
            for k, v in promo_opens.most_common(10)
        ],
    }

# ── HTML ──────────────────────────────────────────────────────────────────────

TIER_COLORS = {
    "excellent":  "#28A745",
    "great":      "#2ECC71",
    "good":       "#FF9F0A",
    "fair":       "#FF6B2B",
    "low":        "#FF453A",
    "unscored":   "#8E8E93",
}
EFFORT_COLORS = {
    "instant":            "#2ECC71",
    "easy":               "#28A745",
    "code_required":      "#FF9F0A",
    "app_required":       "#FF6B2B",
    "membership_required":"#AF52DE",
    "unknown":            "#8E8E93",
}
PALETTE = ["#C0003C","#2ECC71","#FF9F0A","#2C77E5","#AF52DE","#FF6B2B","#34C759","#FF453A","#636366","#5AC8FA"]

def _js(v) -> str:
    return json.dumps(v)

def render_html(d: dict) -> str:
    sp      = d["sessions_per_day"]
    sp_labels = _js([s["day"]   for s in sp])
    sp_vals   = _js([s["count"] for s in sp])

    def bar_chart(chart_id: str, data: dict, colors: dict | None = None, horizontal: bool = False) -> str:
        labels = _js(list(data.keys()))
        vals   = _js(list(data.values()))
        clrs   = _js([colors.get(k, "#C0003C") if colors else PALETTE[i % len(PALETTE)] for i, k in enumerate(data)])
        axis   = '"indexAxis": "y",' if horizontal else ""
        return f"""
        new Chart(document.getElementById('{chart_id}'), {{
          type: 'bar',
          data: {{ labels: {labels}, datasets: [{{ data: {vals}, backgroundColor: {clrs}, borderRadius: 4, borderSkipped: false }}] }},
          options: {{ {axis} plugins: {{ legend: {{ display: false }} }}, scales: {{ x: {{ grid: {{ color: 'rgba(0,0,0,0.05)' }} }}, y: {{ grid: {{ color: 'rgba(0,0,0,0.05)' }} }} }} }}
        }});"""

    tier_opens_chart   = bar_chart("tierOpens",   d["tier_opens"],   TIER_COLORS)
    tier_redeems_chart = bar_chart("tierRedeems", d["tier_redeems"], TIER_COLORS)
    effort_opens_chart = bar_chart("effortOpens", d["effort_opens"], EFFORT_COLORS, horizontal=True)
    top_brands_chart   = bar_chart("topBrands",   d["top_brands"])
    top_cats_chart     = bar_chart("topCats",     d["top_categories"])

    promo_rows = "".join(
        f'<tr><td>{i+1}</td><td>{p["brand"]}</td><td class="mono">{p["id"][:16]}…</td><td class="num">{p["opens"]}</td></tr>'
        for i, p in enumerate(d["top_promos"])
    )

    save_rate   = f'{round(d["saves"]   / d["opens"] * 100, 1)}%' if d["opens"] else "—"
    redeem_rate = f'{round(d["redeems"] / d["opens"] * 100, 1)}%' if d["opens"] else "—"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Candy Analytics</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0 }}
  body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #F5F5F7; color: #1C1C1E; font-size: 14px }}
  header {{ background: #fff; border-bottom: 1px solid #E5E5EA; padding: 20px 32px; display: flex; justify-content: space-between; align-items: center }}
  header h1 {{ font-size: 20px; font-weight: 700; color: #C0003C }}
  header span {{ font-size: 12px; color: #8E8E93 }}
  .container {{ max-width: 1200px; margin: 0 auto; padding: 28px 24px }}
  .section-label {{ font-size: 11px; font-weight: 700; letter-spacing: 1.2px; text-transform: uppercase; color: #8E8E93; margin: 28px 0 12px }}
  .stats {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 12px }}
  .stat {{ background: #fff; border-radius: 14px; padding: 18px 16px; box-shadow: 0 1px 4px rgba(0,0,0,.06) }}
  .stat .value {{ font-size: 28px; font-weight: 800; color: #1C1C1E; letter-spacing: -1px }}
  .stat .label {{ font-size: 12px; color: #8E8E93; margin-top: 4px }}
  .stat .sub {{ font-size: 11px; color: #C0003C; margin-top: 2px; font-weight: 600 }}
  .charts {{ display: grid; grid-template-columns: 1fr 1fr; gap: 16px }}
  .charts.wide {{ grid-template-columns: 1fr }}
  .charts.three {{ grid-template-columns: 1fr 1fr 1fr }}
  .card {{ background: #fff; border-radius: 14px; padding: 20px; box-shadow: 0 1px 4px rgba(0,0,0,.06) }}
  .card h3 {{ font-size: 13px; font-weight: 700; color: #1C1C1E; margin-bottom: 16px }}
  .card canvas {{ max-height: 220px }}
  table {{ width: 100%; border-collapse: collapse }}
  th {{ text-align: left; font-size: 11px; font-weight: 700; color: #8E8E93; letter-spacing: 0.5px; padding: 0 0 10px; text-transform: uppercase }}
  td {{ padding: 9px 0; border-top: 1px solid #F2F2F7; font-size: 13px }}
  td.num {{ text-align: right; font-weight: 700; color: #C0003C }}
  td.mono {{ font-family: monospace; font-size: 11px; color: #8E8E93 }}
  tr:first-child td {{ border-top: none }}
  @media (max-width: 700px) {{ .charts, .charts.three {{ grid-template-columns: 1fr }} }}
</style>
</head>
<body>
<header>
  <h1>🍬 Candy Analytics</h1>
  <span>Last {d["days"]} days &nbsp;·&nbsp; {d["total_rows"]} events &nbsp;·&nbsp; {d["generated_at"]}</span>
</header>
<div class="container">

  <div class="section-label">Acquisition</div>
  <div class="stats">
    <div class="stat"><div class="value">{d["active_users"]}</div><div class="label">Active testers</div><div class="sub">last 7 days</div></div>
    <div class="stat"><div class="value">{d["total_users"]}</div><div class="label">Total testers</div><div class="sub">all time</div></div>
    <div class="stat"><div class="value">{d["avg_sessions"]}</div><div class="label">Sessions / day</div><div class="sub">7-day avg</div></div>
  </div>

  <div class="charts wide" style="margin-top:16px">
    <div class="card"><h3>Sessions per day (14 days)</h3><canvas id="sessions"></canvas></div>
  </div>

  <div class="section-label">Engagement</div>
  <div class="stats">
    <div class="stat"><div class="value">{d["opens"]}</div><div class="label">Deal opens</div></div>
    <div class="stat"><div class="value">{d["saves"]}</div><div class="label">Saves</div><div class="sub">save rate {save_rate}</div></div>
    <div class="stat"><div class="value">{d["redeems"]}</div><div class="label">Redeems</div><div class="sub">redeem rate {redeem_rate}</div></div>
    <div class="stat"><div class="value">{d["searches"]}</div><div class="label">Searches</div></div>
  </div>

  <div class="section-label">Ranking</div>
  <div class="charts three">
    <div class="card"><h3>Opens by value tier</h3><canvas id="tierOpens"></canvas></div>
    <div class="card"><h3>Redeems by value tier</h3><canvas id="tierRedeems"></canvas></div>
    <div class="card"><h3>Opens by effort type</h3><canvas id="effortOpens"></canvas></div>
  </div>

  <div class="section-label">Top content</div>
  <div class="charts">
    <div class="card"><h3>Top brands by opens</h3><canvas id="topBrands"></canvas></div>
    <div class="card"><h3>Top categories by opens</h3><canvas id="topCats"></canvas></div>
  </div>

  <div style="margin-top:16px">
    <div class="card">
      <h3>Most opened promotions</h3>
      <table>
        <tr><th>#</th><th>Brand</th><th>Promotion ID</th><th style="text-align:right">Opens</th></tr>
        {promo_rows if promo_rows else '<tr><td colspan="4" style="color:#8E8E93;padding:16px 0">No data yet</td></tr>'}
      </table>
    </div>
  </div>

</div>
<script>
  new Chart(document.getElementById('sessions'), {{
    type: 'line',
    data: {{
      labels: {sp_labels},
      datasets: [{{
        data: {sp_vals},
        borderColor: '#C0003C',
        backgroundColor: 'rgba(192,0,60,0.08)',
        fill: true,
        tension: 0.35,
        pointRadius: 3,
        pointBackgroundColor: '#C0003C',
      }}]
    }},
    options: {{
      plugins: {{ legend: {{ display: false }} }},
      scales: {{
        x: {{ grid: {{ display: false }} }},
        y: {{ beginAtZero: true, grid: {{ color: 'rgba(0,0,0,0.05)' }}, ticks: {{ stepSize: 1 }} }}
      }}
    }}
  }});
  {tier_opens_chart}
  {tier_redeems_chart}
  {effort_opens_chart}
  {top_brands_chart}
  {top_cats_chart}
</script>
</body>
</html>"""

# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Candy analytics dashboard")
    parser.add_argument("--key",  default=None, help="Supabase service_role key")
    parser.add_argument("--days", type=int, default=30, help="Lookback window in days (default 30)")
    parser.add_argument("--no-open", action="store_true", help="Don't open browser automatically")
    args = parser.parse_args()

    _load_env()
    key = args.key or os.environ.get("SUPABASE_SERVICE_KEY", "")
    if not key:
        print("ERROR: No service_role key found.")
        print("  Option 1: python analytics_dashboard.py --key <key>")
        print("  Option 2: Add SUPABASE_SERVICE_KEY=<key> to .env")
        print("  Find key: Supabase Dashboard → Settings → API → service_role")
        sys.exit(1)

    print("Fetching events from Supabase…")
    try:
        rows = fetch_all(key)
    except httpx.HTTPStatusError as e:
        print(f"ERROR: {e.response.status_code} — {e.response.text[:200]}")
        sys.exit(1)

    print(f"  {len(rows)} events fetched")
    print("Aggregating…")
    data = aggregate(rows, days=args.days)
    html = render_html(data)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(html, encoding="utf-8")
    print(f"Dashboard written to: {OUT}")

    if not args.no_open:
        webbrowser.open(OUT.as_uri())

if __name__ == "__main__":
    main()
