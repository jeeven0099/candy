import copy
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
import normalize_promotions as normalization
import run_scraper
from fetch_page import FetchResult
from source_loader import Source
from source_evidence import build_source_evidence, matches_domain, public_http_url


NOW = datetime(2026, 10, 9, 12, tzinfo=timezone.utc)


def offer(**overrides):
    return {
        "brand": "Example", "promotion_title": "20% off running shoes",
        "discount_type": "percentage_off", "discount_value": "20%",
        "promotion_type": "coupon", "promo_code": "RUN20",
        "requires_membership": False, "requires_app": False,
        "purchase_required": False, "new_user_only": False,
        "redemption_method": "online", "redemption_steps": ["Enter RUN20 at checkout."],
        "confidence_score": 0.95, "extraction_status": "success",
        **overrides,
    }


def evidence(text="Save 20% off running shoes. Use code RUN20.", **overrides):
    return build_source_evidence(
        offer(**overrides), text, source_url="https://example.com/offers",
        checked_at=NOW.isoformat(), trusted_domain="example.com",
    )


def test_supported_quote_is_real_and_bound_to_offer():
    text = "Save 20% off running shoes. Use code RUN20."
    result = evidence(text)
    assert result["status"] == "supported"
    assert result["excerpt"] in text
    assert result["offer"]["promo_code"] == "RUN20"
    assert result["checked_at"] == NOW.isoformat()


@pytest.mark.parametrize("url", [
    "javascript:alert(1)", "https://example.com.evil.test/offers",
    "https://example.com@evil.test/", "https://127.0.0.1/", "https://localhost/",
    "https://example.com:444/", "https://example.com\\@evil.test/",
    "https://example.com/\n", "https://example.com./", "https://example.com.evil/",
])
def test_untrusted_urls_do_not_qualify(url):
    assert not matches_domain(url, "example.com")


def test_known_subdomains_match_but_unrelated_siblings_do_not():
    assert matches_domain("https://www.example.com/offers", "example.com")
    assert matches_domain("https://shop.example.com/offers", "example.com")
    assert not matches_domain("https://evil.com/", "example.com")
    assert not matches_domain("https://example.com/", "example.com/path")
    assert not matches_domain("https://example.com/", "example.com#bad")
    assert not public_http_url("file:///tmp/source")


@pytest.mark.parametrize("text", [
    "Save 120% off running shoes. Use code RUN20.",
    "Running shoes $20. Use code RUN20.",
    "Save 20% off jackets. Use code RUN20.",
    "Save 20% off running shoes. Use code OTHER20.",
    "Up to 20% off running shoes. Use code RUN20.",
    "Save 20% off running shoes for new customers only. Use code RUN20.",
    "Save 20% off running shoes for rewards members. Use code RUN20.",
    "Save 20% off running shoes on orders over $100. Use code RUN20.",
])
def test_unsubstantiated_claims_and_omitted_conditions_need_review(text):
    assert evidence(text)["status"] == "unverified"


def test_threshold_and_date_must_be_supported_by_same_passage():
    text = "Save 20% off running shoes on orders over $100. Use RUN20. Ends October 10, 2026."
    assert evidence(text, minimum_spend="$100", end_date="2026-10-10")["status"] == "supported"
    assert evidence(text, minimum_spend="$150")["status"] == "unverified"
    assert evidence(text, end_date="2027-10-10")["status"] == "unverified"


def test_distant_matches_and_cross_page_matches_are_not_combined():
    text = "Save 20% off running shoes.\n" + "Regular items\n" * 6 + "Code RUN20."
    assert evidence(text)["status"] == "unverified"


def test_regular_price_is_not_misread_as_discount_and_select_terms_are_not_hidden():
    assert evidence("Running shoes $100. Save $20 off. Use RUN20.", discount_type="amount_off", discount_value="$100")["status"] == "unverified"
    assert evidence("Save 20% off selected running shoes. Use RUN20.")["status"] == "unverified"
    assert evidence("Save 20% off selected running shoes. Use RUN20.", terms_text="Selected running shoes only.")["status"] == "supported"
    text = "=== https://example.com/shoes ===\nSave 20% off running shoes.\n=== https://example.com/jackets ===\nCode RUN20."
    assert evidence(text)["status"] == "unverified"


def test_multi_page_excerpt_records_the_actual_source_page():
    text = "=== https://example.com/ ===\nHome\n=== https://example.com/shoes ===\nSave 20% off running shoes. Use RUN20."
    result = evidence(text)
    assert result["status"] == "supported"
    assert result["source_url"] == "https://example.com/shoes"


@pytest.mark.parametrize("overrides", [
    {"synthesized": True}, {"redemption_steps": []}, {"promo_code": None},
    {"requires_membership": True, "membership_name": None},
])
def test_incomplete_and_synthesized_offers_need_review(overrides):
    assert evidence(**overrides)["status"] == "unverified"


def test_normalization_uses_capture_date_and_quarantines_unsupported(tmp_path, monkeypatch):
    monkeypatch.setattr(normalization, "RAW_TEXT_DIR", tmp_path)
    stamp = "example_20260901T120000Z"
    (tmp_path / f"{stamp}.txt").write_text("Save 20% off running shoes. Use RUN20.")
    (tmp_path / f"{stamp}.meta.json").write_text(json.dumps({
        "url": "https://example.com/offers", "scraped_at": "2026-09-01T12:00:00+00:00",
    }))
    input_path = tmp_path / "example.json"
    input_path.write_text(json.dumps({"brand": "Example", "source_path": f"{stamp}.txt", "promotions": [offer()]}))
    lookup = {"example": {"brand": "Example", "website_domain": "example.com", "category": "fashion"}}
    result = normalization.normalize_file(input_path, lookup, NOW)
    p = result["promotions"][0]
    assert p["last_confirmed"] == "2026-09-01T12:00:00+00:00"
    assert p["status"] == "needs_review"

    previous = copy.deepcopy(result)
    previous["promotions"][0]["source_evidence"]["checked_at"] = NOW.isoformat()
    refreshed = normalization.normalize_file(input_path, lookup, NOW, previous_output=previous)
    assert refreshed["promotions"][0]["last_confirmed"] == NOW.isoformat()
    assert refreshed["promotions"][0]["status"] == "probably_active"

    failed = copy.deepcopy(result)
    failed_evidence = failed["promotions"][0]["source_evidence"]
    failed_evidence.update(status="unverified", reasons=["source_fetch_failed"], check_failed_at=NOW.isoformat())
    quarantined = normalization.normalize_file(input_path, lookup, NOW, previous_output=failed)
    assert quarantined["promotions"][0]["source_evidence"]["status"] == "unverified"
    assert quarantined["promotions"][0]["status"] == "needs_review"

    previous["promotions"][0]["source_evidence"]["content_hash"] = "different-content"
    refreshed = normalization.normalize_file(input_path, lookup, NOW, previous_output=previous)
    assert refreshed["promotions"][0]["status"] == "needs_review"

    (tmp_path / f"{stamp}.txt").write_text("No offers here.")
    result = normalization.normalize_file(input_path, lookup, NOW)
    assert result["promotions"][0]["source_evidence"]["status"] == "unverified"
    assert result["promotions"][0]["status"] == "needs_review"


def test_normalization_preserves_timestamp_precision(tmp_path, monkeypatch):
    monkeypatch.setattr(normalization, "RAW_TEXT_DIR", tmp_path)
    stamp = "example_20261009T120000Z"
    (tmp_path / f"{stamp}.txt").write_text("Save 20% off running shoes. Use RUN20. Ends October 9, 2026 at 4pm UTC.")
    (tmp_path / f"{stamp}.meta.json").write_text(json.dumps({
        "url": "https://example.com/offers", "scraped_at": NOW.isoformat(),
    }))
    path = tmp_path / "example.json"
    timestamp = "2026-10-09T16:00:00Z"
    path.write_text(json.dumps({"brand": "Example", "source_path": f"{stamp}.txt", "promotions": [offer(end_date=timestamp)]}))
    lookup = {"example": {"brand": "Example", "website_domain": "example.com"}}
    result = normalization.normalize_file(path, lookup, NOW)
    assert result["promotions"][0]["end_date"] == timestamp
    assert result["promotions"][0]["source_evidence"]["offer"]["end_date"] == timestamp


def test_brand_lookup_supports_configured_multi_url_sources(tmp_path):
    path = tmp_path / "sources.json"
    path.write_text(json.dumps([{"brand": "Example", "urls": ["https://www.example.com/offers", "https://example.com/rewards"]}]))
    assert normalization.load_brand_lookup(path)["example"]["website_domain"] == "example.com"


def test_identical_fetch_only_refreshes_evidence_for_matching_source_and_hash(tmp_path, monkeypatch):
    raw = tmp_path / "raw_text"
    raw.mkdir()
    normalized = tmp_path / "normalized"
    normalized.mkdir()
    monkeypatch.setattr(run_scraper, "RAW_TEXT_DIR", raw)
    monkeypatch.setattr(run_scraper, "NORMALIZED_DIR", normalized)
    monkeypatch.setattr(run_scraper, "hash_exists_for_brand", lambda *_: True)
    monkeypatch.setattr(run_scraper, "clean_visible_text", lambda _: "Save 20% off running shoes. Use RUN20. " * 5)
    html = "<html><body>Valid offers</body></html>"
    monkeypatch.setattr(run_scraper, "fetch_page", lambda url: FetchResult(url=url, ok=True, status_code=200, html=html, error=None, final_url="https://example.com/offers"))
    text = run_scraper.clean_visible_text(html)
    good = offer(website_domain="example.com", last_confirmed="2026-09-01T12:00:00+00:00")
    good["source_evidence"] = build_source_evidence(good, text, source_url="https://example.com/offers", checked_at=good["last_confirmed"], trusted_domain="example.com")
    bad = copy.deepcopy(good)
    bad["source_evidence"]["content_hash"] = "different-content"
    path = normalized / "example.json"
    path.write_text(json.dumps({"promotions": [good, bad]}))
    source = Source("Example", "fashion", ("https://example.com/offers",), "sales_page", True)
    result = run_scraper.process_source(source)
    assert result["status"] == "skipped_duplicate_hash"
    rows = json.loads(path.read_text())["promotions"]
    assert rows[0]["source_evidence"]["checked_at"] != good["last_confirmed"]
    assert rows[1]["last_confirmed"] == bad["last_confirmed"]

    monkeypatch.setattr(run_scraper, "fetch_page", lambda url: FetchResult(url=url, ok=True, status_code=200, html=html, error=None, final_url="https://evil.test/offers"))
    before = path.read_text()
    run_scraper.process_source(source)
    assert path.read_text() == before


def test_failed_fetch_quarantines_without_fabricating_a_fresh_capture(tmp_path, monkeypatch):
    monkeypatch.setattr(run_scraper, "NORMALIZED_DIR", tmp_path)
    source = Source("Example", "fashion", ("https://example.com/offers",), "sales_page", True)
    p = offer(website_domain="example.com")
    p["source_evidence"] = evidence()
    path = tmp_path / "example.json"
    path.write_text(json.dumps({"promotions": [p]}))
    monkeypatch.setattr(run_scraper, "_process_source", lambda *a, **kw: {"status": "failed", "scraped_at": NOW.isoformat(), "http_status": 403})
    record = run_scraper.process_source(source)
    assert record["http_status"] == 403
    updated = json.loads(path.read_text())["promotions"][0]
    assert updated["status"] == "needs_review"
    assert updated["source_evidence"]["status"] == "unverified"
    assert updated["source_evidence"]["checked_at"] == p["source_evidence"]["checked_at"]


def test_multi_url_fetch_records_resolved_page_not_requested_page(tmp_path, monkeypatch):
    monkeypatch.setattr(run_scraper, "ROOT", tmp_path)
    monkeypatch.setattr(run_scraper, "RAW_TEXT_DIR", tmp_path / "raw_text")
    monkeypatch.setattr(run_scraper, "RAW_HTML_DIR", tmp_path / "raw_html")
    monkeypatch.setattr(run_scraper, "hash_exists_for_brand", lambda *_: False)
    monkeypatch.setattr(run_scraper, "_fetch_one_url", lambda url, **_: ("Save 20% off running shoes.", "<body>offers</body>", "Offers", None, url + "/resolved"))
    source = Source("Example", "fashion", ("https://example.com/offers", "https://example.com/rewards"), "sales_page", True)
    result = run_scraper.process_source(source)
    assert result["status"] == "success"
    text = next((tmp_path / "raw_text").glob("*.txt")).read_text()
    assert "=== https://example.com/offers/resolved ===" in text
