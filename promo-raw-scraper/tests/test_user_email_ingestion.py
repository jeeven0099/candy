import argparse
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from email_pipeline import parse_email_message
from local_model_interface import RuleBasedLocalModel
from personal_email_ranker import PersonalEmailRanker
import user_email_ingestion as ingestion


def promotional_email():
    return (
        b"From: Example Store <deals@example.com>\r\n"
        b"Subject: Your offer: 30% off today\r\n"
        b"Date: Tue, 06 Oct 2026 12:00:00 +0000\r\n"
        b"Message-ID: <offer@example.com>\r\n"
        b"Content-Type: text/plain; charset=utf-8\r\n\r\n"
        b"Use code SAVE30 for 30% off online. Offer expires October 10, 2026.\r\n"
        b"https://example.com/unsubscribe\r\nhttps://example.com/deal\r\n"
    )


def test_short_email_preserves_normalized_redemption_fields():
    parsed = parse_email_message(promotional_email())
    promos = ingestion.extract_promotions(parsed, "private_user_offer", RuleBasedLocalModel(min_text_length=1))
    assert len(promos) == 1
    normalized = ingestion.normalize_email_promotions(promos)[0]
    assert normalized["source_type"] == "email"
    assert normalized["discount_type"] == "percentage_off"
    assert normalized["discount_value"] == "30%"
    assert normalized["promo_code"] == "SAVE30"
    assert normalized["deal_url"] == "https://example.com/deal"
    assert normalized["end_date"] == "2026-10-10"
    assert normalized["visibility"] == "private_user_offer"
    assert "global_quality_score" in normalized
    assert normalized["confidence_score"] >= 0.7


def test_numeric_discount_without_marketing_keywords_is_extracted():
    parsed = parse_email_message(b"From: Store <store@example.com>\r\nSubject: 30% off today\r\n\r\n30% off online.")
    promos = ingestion.extract_promotions(parsed, "public_general_offer", RuleBasedLocalModel(min_text_length=1, require_keywords=False))
    assert promos[0]["discount_value"] == "30%"


def test_web_parser_retains_its_existing_short_text_filter():
    promos = RuleBasedLocalModel().parse_text("Coupon: 30% off", "Store", None, "web")
    assert promos[0].extraction_status == "no_offer_found"


def test_non_deal_email_does_not_become_a_promotion():
    parsed = parse_email_message(b"From: Store <store@example.com>\r\nSubject: Our story\r\n\r\nWelcome to our newsletter.")
    assert ingestion.extract_promotions(parsed, "public_general_offer", RuleBasedLocalModel(min_text_length=1)) == []


@pytest.mark.parametrize("age_days,labels,expected", [
    (1, ("CATEGORY_PROMOTIONS",), True),
    (14, ("CATEGORY_PROMOTIONS",), True),
    (15, ("CATEGORY_PROMOTIONS",), False),
    (1, ("CATEGORY_PERSONAL",), False),
    (-1, ("CATEGORY_PROMOTIONS",), False),
])
def test_scope_checks_label_and_received_date(age_days, labels, expected):
    now = datetime(2026, 10, 6, tzinfo=timezone.utc)
    message = ingestion.GmailMessage("one", "thread", None, (now - timedelta(days=age_days)).isoformat(), b"", labels)
    assert ingestion.is_in_scope(message, now) is expected


def test_pagination_retains_promotions_and_date_restrictions(monkeypatch):
    calls = []
    class Response:
        def raise_for_status(self):
            pass
        def json(self):
            return {"messages": [{"id": "second"}]} if len(calls) == 2 else {"messages": [{"id": "first"}], "nextPageToken": "next"}
    def fake_get(url, **kwargs):
        calls.append(kwargs["params"])
        return Response()
    monkeypatch.setattr(ingestion.requests, "get", fake_get)
    assert ingestion.list_gmail_messages("token", "from:example.com", 0) == [{"id": "first"}, {"id": "second"}]
    assert calls[1]["pageToken"] == "next"
    for params in calls:
        assert "category:promotions newer_than:14d" in params["q"]
        assert params["labelIds"] == "CATEGORY_PROMOTIONS"


def test_sync_requires_explicit_account():
    with pytest.raises(SystemExit, match="user-id"):
        ingestion.iter_connections(None, None, None, False)


def test_expiry_keeps_deal_through_end_date():
    assert ingestion._parse_expires_at({"end_date": "2026-10-10"}) == "2026-10-11T00:00:00+00:00"


def test_sync_stores_only_selected_users_in_scope_deals(monkeypatch):
    now = datetime.now(timezone.utc)
    message = ingestion.GmailMessage("gmail-id", "thread", None, now.isoformat(), promotional_email(), ("CATEGORY_PROMOTIONS",))
    unrelated = ingestion.GmailMessage("personal-id", "other", None, now.isoformat(), promotional_email(), ("CATEGORY_PERSONAL",))
    class Admin:
        def __init__(self):
            self.writes = []
        def get(self, table, params):
            return [{"access_token": "token", "access_token_expires_at": (now + timedelta(hours=1)).isoformat()}] if table == "gmail_connection_tokens" else []
        def insert(self, table, payload):
            return {"id": "job-id"}
        def upsert(self, table, payload, on_conflict):
            self.writes.append((table, payload))
        def patch(self, table, params, payload):
            self.writes.append((table, {**payload, **params}))
    class ProfileResponse:
        def raise_for_status(self):
            pass
        def json(self):
            return {"emailAddress": "owner@gmail.com"}
    monkeypatch.setattr(ingestion.requests, "get", lambda *a, **kw: ProfileResponse())
    monkeypatch.setattr(ingestion, "list_gmail_messages", lambda *a: [{"id": "one"}, {"id": "two"}])
    monkeypatch.setattr(ingestion, "fetch_gmail_message", lambda token, message_id: message if message_id == "one" else unrelated)
    args = argparse.Namespace(reason="test", gmail_query=ingestion.DEFAULT_GMAIL_QUERY, limit=0, min_rank_score=70, extraction_model="rule_based")
    sb = Admin()
    seen, extracted = ingestion.ingest_for_user(sb, {"user_id": "owner-id", "google_email": "owner@gmail.com"}, args, RuleBasedLocalModel(min_text_length=1), PersonalEmailRanker(model_name="heuristic"))
    assert (seen, extracted) == (1, 1)
    stored = [payload for table, payload in sb.writes if table == "user_email_deals" and "promotion_json" in payload]
    assert len(stored) == 1
    assert stored[0]["user_id"] == "owner-id"
    assert stored[0]["gmail_message_id"] == "gmail-id"
    assert stored[0]["promotion_json"]["promo_code"] == "SAVE30"
    assert stored[0]["personal_rank_model"] == "heuristic"
    assert all(table in {"gmail_connections", "user_email_deals", "email_sync_jobs"} for table, _ in sb.writes)
