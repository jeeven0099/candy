from __future__ import annotations

import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW_TEXT_DIR = ROOT / 'raw_text'
OUT_FILE = ROOT / 'logs' / 'raw_data_summary.csv'
KEYWORDS = ['reward', 'offer', 'deal', 'discount', 'promo', 'app', 'member', 'birthday', 'expires', 'valid', 'coupon', 'free']


def load_meta(text_path: Path) -> dict:
    meta_path = text_path.with_suffix('.meta.json')
    if meta_path.exists():
        return json.loads(meta_path.read_text(encoding='utf-8'))
    return {}


def summarize_file(path: Path) -> dict:
    text = path.read_text(encoding='utf-8', errors='replace')
    meta = load_meta(path)
    lower = text.lower()
    keyword_hits = {kw: lower.count(kw) for kw in KEYWORDS}
    return {
        'brand': meta.get('brand', ''),
        'file_name': path.name,
        'source_url': meta.get('url', ''),
        'text_length': len(text),
        'line_count': len(text.splitlines()),
        'first_500_chars': text[:500].replace('\n', ' '),
        **{f'kw_{kw}': count for kw, count in keyword_hits.items()},
    }


def main() -> None:
    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    rows = [summarize_file(path) for path in RAW_TEXT_DIR.glob('*.txt')]
    rows.sort(key=lambda row: (row['brand'], row['file_name']))
    fieldnames = ['brand', 'file_name', 'source_url', 'text_length', 'line_count', 'first_500_chars'] + [f'kw_{kw}' for kw in KEYWORDS]
    with OUT_FILE.open('w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f'Wrote {len(rows)} summaries to {OUT_FILE.relative_to(ROOT)}')
    for row in rows[:20]:
        print(f"{row['brand'] or row['file_name']}: {row['text_length']} chars | reward={row['kw_reward']} offer={row['kw_offer']} deal={row['kw_deal']}")


if __name__ == '__main__':
    main()
