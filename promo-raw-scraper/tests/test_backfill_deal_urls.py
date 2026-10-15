import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import backfill_deal_urls as backfill


def run_backfill(tmp_path, monkeypatch, marker, excerpt):
    monkeypatch.setattr(backfill, "RAW_TEXT_DIR", tmp_path)
    (tmp_path / "example_20261015T120000Z.txt").write_text(
        f"Save 20% off running shoes. [deal_url:{marker}]", encoding="utf-8",
    )
    path = tmp_path / "example.json"
    path.write_text(json.dumps({
        "brand": "Example", "website_domain": "example.com",
        "promotions": [{
            "promotion_title": "20% off running shoes",
            "source_url": "https://example.com/offers",
            "source_evidence": {"excerpt": excerpt},
        }],
    }), encoding="utf-8")
    backfill.process_brand(path)
    return json.loads(path.read_text(encoding="utf-8"))["promotions"][0]


def test_backfill_preserves_captured_source(tmp_path, monkeypatch):
    row = run_backfill(tmp_path, monkeypatch, "/running", "Save 20% off running shoes. [deal_url:/running]")
    assert row["deal_url"] == "https://www.example.com/running"
    assert row["source_url"] == "https://example.com/offers"


def test_unrelated_navigation_cannot_become_a_deal_link(tmp_path, monkeypatch):
    row = run_backfill(tmp_path, monkeypatch, "/accessibility", "Save 20% off running shoes.")
    assert "deal_url" not in row
    assert row["source_url"] == "https://example.com/offers"


def test_protocol_relative_links_cannot_leave_brand_domain(tmp_path, monkeypatch):
    row = run_backfill(tmp_path, monkeypatch, "//evil.test/running", "Save 20% off running shoes. [deal_url://evil.test/running]")
    assert "deal_url" not in row
