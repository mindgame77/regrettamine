"""Fix 2 (rulebook A15.8): money is the full number plus a 3-letter currency; the page builder formats it."""
import os

import pytest

pytest.importorskip("psycopg")
import psycopg  # noqa: E402

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


@pytest.mark.parametrize("amt,cur,want", [
    (14000000000, "USD", "$14B"), (13200000, "EUR", "€13.2M"), (22700000000, "USD", "$22.7B"),
    (106500000000, "USD", "$107B"), (12000000, "CHF", "CHF 12M"), (7929, "USD", "$7.93K"),
    (500, "GBP", "£500"), (1710000000, "USD", "$1.71B"), (None, "USD", None),
])
def test_money_display_matches_page_money(amt, cur, want):
    with psycopg.connect(DATABASE_URL) as c:
        assert c.execute("select public._money_display(%s, %s)", (amt, cur)).fetchone()[0] == want


def _firm(cur):
    return cur.execute("insert into firms (slug, name, published, data_status) values ('zz-money', 'ZZ Money', true, 'real') returning id").fetchone()[0]


@pytest.mark.parametrize("sql", [
    "insert into funds (firm_id, name, raised_usd, data_status) values (%s, 'ZZ', 14000000000, 'real')",          # no currency
    "insert into funds (firm_id, name, raised_usd, raised_currency, data_status) values (%s, 'ZZ', 106.5, 'USD', 'real')",
    "insert into funds (firm_id, name, raised_usd, raised_currency, data_status) values (%s, 'ZZ', 0, 'USD', 'real')",
    "insert into funds (firm_id, name, target_usd, target_currency, data_status) values (%s, 'ZZ', 5000000, 'usd', 'real')",
    "insert into funds (firm_id, name, size_usd, size_currency, data_status) values (%s, 'ZZ', 5000000, 'DOLLARS', 'real')",
    "update firms set aum_amount = 160.24, aum_currency = 'USD' where id = %s",
    "update firms set aum_amount = 160240000000 where id = %s",
    "update firms set fund_assets_amount = 5000000 where id = %s",
])
def test_checks_reject_short_forms_and_missing_currency(sql):
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        with pytest.raises(psycopg.errors.CheckViolation):
            cur.execute(sql, (fid,))
        c.rollback()


def test_builders_read_new_columns():
    with psycopg.connect(DATABASE_URL) as c, c.cursor() as cur:
        fid = _firm(cur)
        assert cur.execute("select public._firm_assets(%s)", (fid,)).fetchone()[0] is None
        cur.execute("update firms set aum_amount = 13200000, aum_currency = 'EUR', fund_assets_amount = 14000000000, fund_assets_currency = 'USD' where id = %s", (fid,))
        assert cur.execute("select public._firm_assets(%s)", (fid,)).fetchone()[0] == "€13.2M"
        cur.execute("""insert into funds (firm_id, name, raised_usd, raised_currency, target_usd, target_currency, closed_on, filing_url, data_status)
                       values (%s, 'ZZ Fund I', 13200000, 'EUR', 20000000, 'EUR', '2026-01-01', 'https://www.sec.gov/Archives/z', 'real'),
                              (%s, 'ZZ Fund 0', null, null, null, null, '2025-01-01', 'https://www.sec.gov/Archives/y', 'real')""", (fid, fid))
        a = cur.execute("select public._firm_activity(%s, true)", (fid,)).fetchone()[0]
        lf = a["latest_fund"]
        assert lf["currency"] == "EUR" and lf["raised_display"] == "€13.2M" and lf["target_display"] == "€20M"
        items = {i["name"]: i for i in a["funds_sec"]["items"]}
        assert items["ZZ Fund I"]["raised_display"] == "€13.2M" and items["ZZ Fund I"]["currency"] == "EUR"
        # No amount: the same keys as before fix 2 (no currency/display keys), so pages without amounts do not change.
        assert set(items["ZZ Fund 0"]) == {"name", "raised_usd", "date", "url"}
        c.rollback()


def test_entry_check_money_reasons():
    with psycopg.connect(DATABASE_URL) as c:
        q = lambda path, v: c.execute("select public._money_problems(%s, %s::jsonb)", (path, v)).fetchone()[0]
        assert q("funds", '{"name": "F", "size_usd": 14000000000, "target_usd": 0, "offering_usd": "Indefinite"}') == []
        assert q("latestRaise", '{"amount": 13200000, "currency": "EUR"}') == []
        assert q("aum", '{"amount_usd": 1000000000, "basis": "form_adv_raum"}') == []
        assert q("hq", '{"amount": 0.13}') == []
        assert "short form" in q("funds", '{"size_usd": 106.5}')[0]
        assert "short form" in q("funds", '{"raised_usd": "$82.2B"}')[0]
        assert "no currency" in q("latestRaise", '{"amount": 14000000000}')[0]
        assert "whole number" in q("funds", '{"size_usd": 1500000000.5}')[0]
        assert "full number" in q("funds", '{"target_usd": {"value": 1}}')[0]
