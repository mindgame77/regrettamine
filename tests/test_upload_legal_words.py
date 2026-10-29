"""Upload fix (Alex 2026-10-28): legal words mapped from old words, side "other" rejected, AUM basis press rejected,
news/thesis/socialAccounts records pass the entry check. Each test runs in a rolled-back transaction."""
import os

import pytest

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.fixture()
def cur():
    if not DATABASE_URL:
        pytest.skip("DATABASE_URL is not set")
    import psycopg
    with psycopg.connect(DATABASE_URL) as c:
        try:
            yield c
        finally:
            c.rollback()


@pytest.mark.parametrize("f,want", [
    ({"status": "open", "firm_party_role": "defendant"}, None),
    ({"status": "judgment", "side": "Plaintiff"}, None),
    ({"status": "unknown"}, None),
    ({"status": "Settled", "case_type": "Regulator action"}, None),
    ({"firm_party_role": "other"}, 'side "other" is not allowed: the firm must be the Defendant or the Plaintiff'),
    ({"status": "appeal"}, "status word not on the fixed list (Active, Closed, Settled, Dismissed)"),
    ({"case_type": "tax"}, "case type not on the fixed list (Fraud, Contract, Employment, Securities, Regulator action, IP)"),
])
def test_legal_words(cur, f, want):
    import json
    assert cur.execute("select public._entry_status_bad(%s::jsonb)", (json.dumps(f),)).fetchone()[0] == want


def test_aum_press_rejected(cur):
    import json
    p = {"records": [{"record_id": "a", "field_path": "aum", "value": {"amount_usd": 5, "basis": "press"}, "tier": "T2",
                      "sources": [{"url": "https://www.reuters.com/a", "tier": "T2"}]}]}
    r = cur.execute("select public._entry_check_reasons(%s::jsonb, null)", (json.dumps(p),)).fetchone()[0]
    assert "AUM basis press is not allowed (A7.3)" in r
