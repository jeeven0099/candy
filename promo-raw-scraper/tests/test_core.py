import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'src'))

from clean_html import clean_visible_text
from email_pipeline import extract_deal_signals, parse_email_message
from hash_content import sha256_text
from personal_email_ranker import PersonalEmailRanker
from run_scraper import detect_bad_page
from source_loader import load_sources, filter_sources


def test_clean_visible_text_removes_script():
    html = '<html><head><script>alert(1)</script></head><body><h1>Rewards</h1><p>Get offers today.</p></body></html>'
    text = clean_visible_text(html)
    assert 'alert' not in text
    assert 'Rewards' in text
    assert 'Get offers today.' in text


def test_hash_stable():
    assert sha256_text('abc') == sha256_text('abc')
    assert sha256_text('abc') != sha256_text('abcd')


def test_source_loading(tmp_path):
    p = tmp_path / 'urls.json'
    p.write_text(json.dumps([
        {'brand': 'Starbucks', 'category': 'coffee', 'url': 'https://example.com', 'source_type': 'rewards_page', 'allowed_to_fetch': True},
        {'brand': 'Blocked', 'category': 'other', 'url': 'https://example.org', 'source_type': 'unknown', 'allowed_to_fetch': False},
    ]))
    sources = load_sources(p)
    assert len(sources) == 2
    selected = filter_sources(sources, allowed_only=True)
    assert len(selected) == 1
    assert selected[0].brand == 'Starbucks'


def test_detect_bad_page_flags_common_blockers():
    assert detect_bad_page('Access to this page has been denied.', '', None) == 'access_denied'
    assert detect_bad_page('Something went wrong.', '', None) == 'generic_error'
    assert detect_bad_page('Sale at L.L.Bean- Quality Apparel & Gear', 'real sale copy', None) is None


def test_email_pipeline_extracts_promo_signals():
    raw = (
        b'From: Example Store <deals@example.com>\r\n'
        b'Subject: Save 20% off today\r\n'
        b'Date: Wed, 13 May 2026 12:00:00 -0500\r\n'
        b'Content-Type: text/plain; charset=utf-8\r\n'
        b'\r\n'
        b'Use code SAVE20 for 20% off. Offer expires May 20.\r\n'
        b'https://example.com/deal\r\n'
    )
    parsed = parse_email_message(raw)
    signals = extract_deal_signals(parsed)

    assert parsed.brand == 'Example Store'
    assert 'SAVE20' in signals['promo_codes']
    assert signals['has_signal'] is True
    assert parsed.links == ['https://example.com/deal']


def test_personal_email_ranker_favors_matching_private_deal():
    promo = {
        'brand': 'Example Store',
        'category': 'fashion',
        'promotion_title': '40% off dresses',
        'discount_type': 'percentage_off',
        'global_quality_score': 72,
        'visibility': 'private_user_offer',
    }
    profile = {
        'favorite_brands': ['Example Store'],
        'favorite_categories': ['fashion'],
        'deal_priorities': ['discount'],
        'hidden_brands': [],
        'brand_affinity': [],
        'category_affinity': [],
    }
    result = PersonalEmailRanker(api_key='').rank(promo, profile)
    assert result.score >= 90
    assert 'favorite_brand' in result.reasons
    assert result.model_name == 'heuristic'


def test_personal_email_ranker_default_is_model_free(monkeypatch):
    monkeypatch.setenv('OPENROUTER_API_KEY', 'not-used-in-default-mode')
    result = PersonalEmailRanker().rank(
        {
            'brand': 'Example Store',
            'category': 'fashion',
            'promotion_title': '20% off',
            'discount_type': 'percentage_off',
            'global_quality_score': 65,
            'visibility': 'public_general_offer',
        },
        {'favorite_brands': [], 'favorite_categories': [], 'hidden_brands': []},
    )
    assert result.model_name == 'heuristic'
